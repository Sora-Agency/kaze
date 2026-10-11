import argparse
import pathlib
import plistlib
import re
import subprocess
import time


def attached_device(image, run):
    result = run(["hdiutil", "info", "-plist"], capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace").strip())
    for item in plistlib.loads(result.stdout).get("images", []):
        if pathlib.Path(item["image-path"]).resolve() != image.resolve():
            continue
        for entity in item.get("system-entities", []):
            device = entity.get("dev-entry", "")
            if re.fullmatch(r"/dev/disk[0-9]+", device):
                return device
        raise RuntimeError("No se encontró el dispositivo del disco temporal.")
    return None


def detach_image(image, run=subprocess.run, wait=time.sleep, attempts=5):
    error = "No se pudo expulsar el disco temporal."
    for attempt in range(attempts):
        device = attached_device(image, run)
        if device is None:
            return
        result = run(["hdiutil", "detach", "-force", device], capture_output=True)
        if result.returncode == 0:
            return
        error = result.stderr.decode(errors="replace").strip() or error
        if attempt + 1 < attempts:
            wait(2)
    if attached_device(image, run) is not None:
        raise RuntimeError(error)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=pathlib.Path)
    arguments = parser.parse_args()
    try:
        detach_image(arguments.image)
    except (RuntimeError, OSError, ValueError) as error:
        parser.exit(1, f"DMG: {error}\n")


if __name__ == "__main__":
    main()
