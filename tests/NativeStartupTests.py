import pathlib
import subprocess
import tempfile
import time
import shutil
import sys
import plistlib


root = pathlib.Path(__file__).resolve().parents[1]
source_app = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "package/Kaze.app"


def usage(pid):
    output = subprocess.check_output(
        ["/bin/ps", "-p", str(pid), "-o", "time=", "-o", "rss="], text=True
    ).split()
    minutes, seconds = output[0].split(":")
    return int(minutes) * 60 + float(seconds), int(output[1]) * 1024


with tempfile.TemporaryDirectory(prefix="kaze-native-startup-") as directory:
    app = pathlib.Path(directory) / "Kaze.app"
    shutil.copytree(source_app, app, symlinks=True)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    print(f"Testing native app {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})", flush=True)
    executable = app / "Contents/MacOS/Kaze"
    cases = [(None, None)] + [(monitor, appearance) for monitor in ("YES", "NO") for appearance in ("dark", "light")]
    for monitor, appearance in cases:
        arguments = [str(executable), "-SUEnableAutomaticChecks", "NO"]
        if monitor is not None: arguments += ["-kaze.monitor.enabled", monitor]
        if appearance is not None: arguments += ["-kaze.appearance", appearance]
        process = subprocess.Popen(
            arguments,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            time.sleep(6)
            assert process.poll() is None, "Native app exited during launch"
            before, memory = usage(process.pid)
            time.sleep(4)
            after, final_memory = usage(process.pid)
            assert after - before < 1.5, (
                f"Native UI did not settle: {after - before:.2f}s CPU over 4s "
                f"(monitor={monitor}, appearance={appearance})"
            )
            assert final_memory - memory < 40 * 1024 * 1024, "Idle UI memory keeps growing"
            print(f"PASS: native startup settles, monitor={monitor}, "
                  f"appearance={appearance}, CPU={after - before:.2f}s")
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
