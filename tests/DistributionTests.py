import os
import pathlib
import plistlib
import struct
import subprocess
import tempfile


def run(*arguments):
    return subprocess.check_output(arguments, stderr=subprocess.STDOUT)


def finder_records(path):
    data = path.read_bytes()
    assert data[:8] == b"\x00\x00\x00\x01Bud1"
    root_offset, root_size, root_copy = struct.unpack_from(">III", data, 8)
    assert root_offset == root_copy and root_offset + root_size + 4 <= len(data)
    count = struct.unpack_from(">I", data, root_offset + 4)[0]
    addresses = struct.unpack_from(f">{count}I", data, root_offset + 12)
    position = root_offset + 12 + ((count + 255) // 256) * 1024
    toc_count = struct.unpack_from(">I", data, position)[0]
    position += 4
    table = {}
    for _ in range(toc_count):
        length = data[position]
        name = data[position + 1:position + 1 + length]
        position += 1 + length
        table[name] = struct.unpack_from(">I", data, position)[0]
        position += 4
    block = (addresses[table[b"DSDB"]] & ~31) + 4
    leaf, levels, total, nodes, page_size = struct.unpack_from(">IIIII", data, block)
    assert levels == 0 and nodes == 1 and page_size == 4096
    position = (addresses[leaf] & ~31) + 4
    child, record_count = struct.unpack_from(">II", data, position)
    assert child == 0 and record_count == total
    position += 8
    records = {}
    for _ in range(record_count):
        length = struct.unpack_from(">I", data, position)[0] * 2
        position += 4
        name = data[position:position + length].decode("utf-16be")
        position += length
        code, kind = struct.unpack_from(">4s4s", data, position)
        position += 8
        if kind == b"blob":
            length = struct.unpack_from(">I", data, position)[0]
            position += 4
            value = data[position:position + length]
            position += length
        elif kind in (b"long", b"type"):
            value = data[position:position + 4]
            position += 4
        else:
            raise AssertionError(f"Tipo inesperado: {kind}")
        records[name, code] = value
    return records


project = pathlib.Path(__file__).resolve().parents[1]
architecture = run("uname", "-m").decode().strip()
image = project / "build" / f"Kaze-Mac-{architecture}.dmg"
run("hdiutil", "verify", str(image))
with tempfile.TemporaryDirectory(prefix="kaze-distribution-") as directory:
    mount = pathlib.Path(directory) / "volume"
    mount.mkdir()
    run("hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
        "-mountpoint", str(mount), str(image))
    try:
        assert os.readlink(mount / "Applications") == "/Applications"
        assert {path.name for path in mount.iterdir() if not path.name.startswith(".")} == {"Kaze.app", "Applications"}
        app = mount / "Kaze.app"
        assert (mount / ".VolumeIcon.icns").read_bytes() == (app / "Contents/Resources/AppIcon.icns").read_bytes()
        finder_info = bytes.fromhex(run("xattr", "-px", "com.apple.FinderInfo", str(mount)).decode())
        assert struct.unpack_from(">H", finder_info, 8)[0] & 0x0400
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        assert info["CFBundleIdentifier"] == "com.soraagency.kaze"
        assert info["SUFeedURL"] == f"https://github.com/Sora-Agency/kaze/releases/latest/download/appcast-{architecture}.xml"
        assert info["SURequireSignedFeed"] and info["SUVerifyUpdateBeforeExtraction"]
        framework = app / "Contents/Frameworks/Sparkle.framework"
        assert framework.is_dir() and (framework / "Sparkle").is_file()
        assert (app / "Contents/Resources/Sparkle/LICENSE").is_file()
        for name in ("rules-v1.json", "rules-v1.signature"):
            assert (app / "Contents/Resources/Rules" / name).read_bytes() == (project / "src/Rules" / name).read_bytes()
        for name in ("Qwen-LICENSE.txt", "llama-LICENSE.txt"):
            assert (app / "Contents/Resources/AI" / name).read_bytes() == (project / "src/AI" / name).read_bytes()
        assert not list(app.rglob("*.gguf")) and not list(app.rglob("engine.tar.gz"))
        assert not list(app.rglob("llama-completion"))
        subprocess.run(["xcrun", "swift", str(project / "scripts/verify-rules.swift"), str(project)], check=True)
        assert b"@rpath/Sparkle.framework" in run("otool", "-L", str(app / "Contents/MacOS/Kaze"))
        run("codesign", "--verify", "--deep", "--strict", str(app))
        assert run("lipo", "-archs", str(app / "Contents/MacOS/Kaze")).decode().strip() == architecture
        for name in ("LICENSE", "TERMS.txt", "PRIVACY.txt", "THIRD_PARTY_NOTICES.txt"):
            assert (app / "Contents/Resources" / name).read_bytes() == (project / name).read_bytes()
        assert info["CFBundleDevelopmentRegion"] == "en"
        assert info["CFBundleLocalizations"] == ["en", "es"]
        for language in ("en", "es"):
            localized = app / "Contents/Resources" / f"{language}.lproj"
            for name in ("Localizable.strings", "Localizable.stringsdict"):
                assert (localized / name).read_bytes() == (project / "src/Localization" / f"{language}.lproj" / name).read_bytes()
            for name in ("TERMS.txt", "PRIVACY.txt"):
                original = project / name if language == "es" else project / "src/Localization/en.lproj" / name
                assert (localized / name).read_bytes() == original.read_bytes()
        assert (app / "Contents/Resources/localization.zsh").read_bytes() == (project / "src/localization.zsh").read_bytes()
        records = finder_records(mount / ".DS_Store")
        assert struct.unpack_from(">II", records["Kaze.app", b"Iloc"]) == (172, 244)
        assert struct.unpack_from(">II", records["Applications", b"Iloc"]) == (468, 244)
        assert records[".", b"vstl"] == b"icnv"
        assert records[".", b"icvl"] == b"icnv"
        assert plistlib.loads(records[".", b"bwsp"])["WindowBounds"] == "{{180, 120}, {640, 432}}"
        view = plistlib.loads(records[".", b"icvp"])
        assert view["backgroundType"] == 2 and view["iconSize"] == 88
        assert b"install.tiff" in view["backgroundImageAlias"]
        assert os.fsencode(pathlib.Path.home()) not in (mount / ".DS_Store").read_bytes()
        alias = view["backgroundImageAlias"]
        assert struct.unpack_from(">H", alias, 4)[0] == len(alias)
        position = 150
        tags = []
        while position + 4 <= len(alias):
            tag, size = struct.unpack_from(">HH", alias, position)
            tags.append(tag)
            position += 4 + size + (size & 1)
            if tag == 0xffff:
                break
        assert tags[-1] == 0xffff and position == len(alias) and 20 not in tags
        alias_file = pathlib.Path(directory) / "background.alias"
        alias_file.write_bytes(alias)
        checker = pathlib.Path(directory) / "DMGLayoutTests"
        run("xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-target", f"{architecture}-apple-macosx13.0",
            str(project / "tests/DMGLayoutTests.swift"), "-o", str(checker))
        print(run(str(checker), str(mount), str(alias_file)).decode().strip())
        installed = pathlib.Path(directory) / "Applications/Kaze.app"
        run("ditto", str(app), str(installed))
        run("codesign", "--verify", "--strict", str(installed))
        run("diff", "-qr", str(app), str(installed))
    finally:
        run("hdiutil", "detach", str(mount))
print("DMG: montaje, Aplicaciones, layout, recursos y copia de instalación verificados.")
