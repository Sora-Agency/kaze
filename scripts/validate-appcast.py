import argparse
import base64
import pathlib
import plistlib
import re
import xml.etree.ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
RELEASES = "https://github.com/Sora-Agency/kaze/releases"


def validate_appcast(feed, archive, info, architecture, tag):
    if architecture not in ("arm64", "x86_64"):
        raise ValueError("Arquitectura de actualización inválida.")
    if tag != "v" + info["CFBundleShortVersionString"]:
        raise ValueError("Versión de actualización incorrecta.")
    root = ET.fromstring(feed.read_bytes())
    items = root.findall("./channel/item")
    if root.tag != "rss" or len(items) != 1:
        raise ValueError("El feed debe contener exactamente una actualización.")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None or len(item.findall("enclosure")) != 1:
        raise ValueError("Falta el archivo de actualización.")
    expected_name = f"Kaze-Mac-{architecture}.dmg"
    if archive.name != expected_name or enclosure.get("url") != f"{RELEASES}/download/{tag}/{expected_name}":
        raise ValueError("URL o arquitectura de actualización incorrecta.")
    if enclosure.get("length") != str(archive.stat().st_size):
        raise ValueError("Tamaño de actualización incorrecto.")
    for field, expected in (("version", info["CFBundleVersion"]),
                            ("shortVersionString", info["CFBundleShortVersionString"]),
                            ("minimumSystemVersion", info["LSMinimumSystemVersion"])):
        if item.findtext(SPARKLE + field) != expected:
            raise ValueError(f"Metadatos de actualización incorrectos: {field}.")
    signature = enclosure.get(SPARKLE + "edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Firma EdDSA de actualización inválida.")
    if info.get("SURequireSignedFeed"):
        signed = re.search(rb"<!-- sparkle-signatures:\s*edSignature: ([A-Za-z0-9+/=]+)\s+length: ([0-9]+)\s*-->\s*$", feed.read_bytes())
        if signed is None or len(base64.b64decode(signed[1], validate=True)) != 64:
            raise ValueError("El feed debe estar firmado.")
    return signature


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--feed", type=pathlib.Path, required=True)
    parser.add_argument("--archive", type=pathlib.Path, required=True)
    parser.add_argument("--info", type=pathlib.Path, required=True)
    parser.add_argument("--architecture", required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    info = plistlib.loads(args.info.read_bytes())
    print(validate_appcast(args.feed, args.archive, info, args.architecture, args.tag))


if __name__ == "__main__":
    main()
