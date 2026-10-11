import argparse
import hashlib
import pathlib
import plistlib
import re
import shutil
import zipfile


def validate_version(project, tag):
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", tag):
        raise ValueError("El tag debe tener el formato vMAJOR.MINOR.PATCH.")
    info = plistlib.loads((project / "src/Info.plist").read_bytes())
    version = info["CFBundleShortVersionString"]
    if tag != "v" + version:
        raise ValueError(f"El tag {tag} no coincide con la versión {version} de la app.")
    notes = (project / "docs/RELEASE_NOTES.md").read_text()
    if notes.splitlines()[0] != "# Kaze " + version:
        raise ValueError("Actualiza docs/RELEASE_NOTES.md para esta versión.")
    return info


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_artifact(folder, architecture):
    expected = {f"Kaze-Mac-{architecture}.dmg", f"Kaze-Mac-{architecture}.zip", "Kaze-Source.zip"}
    manifest = folder / f"Kaze-SHA256-{architecture}.txt"
    verified = set()
    for line in manifest.read_text().splitlines():
        match = re.fullmatch(r"([a-f0-9]{64})  (.+)", line)
        if not match or match[2] not in expected or match[2] in verified:
            raise ValueError(f"Manifiesto inválido: {manifest.name}")
        if digest(folder / match[2]) != match[1]:
            raise ValueError(f"Hash incorrecto: {architecture}/{match[2]}")
        verified.add(match[2])
    if verified != expected:
        raise ValueError(f"Faltan archivos en el manifiesto de {architecture}.")


def source_contents(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("El ZIP de fuentes contiene entradas duplicadas.")
        return {entry.filename: (archive.read(entry), entry.external_attr >> 16)
                for entry in archive.infolist() if not entry.is_dir()}


def write_manifest(path, folder, names):
    path.write_text("".join(f"{digest(folder / name)}  {name}\n" for name in names))


def prepare_release(project, tag, artifacts, output):
    info = validate_version(project, tag)
    architectures = ("arm64", "x86_64")
    sources = []
    for architecture in architectures:
        folder = artifacts / f"kaze-{architecture}"
        verify_artifact(folder, architecture)
        sources.append(source_contents(folder / "Kaze-Source.zip"))
    if sources[0] != sources[1]:
        raise ValueError("Las dos arquitecturas no contienen el mismo código fuente.")
    if plistlib.loads(sources[0]["Kaze-Source/src/Info.plist"][0]) != info:
        raise ValueError("Los artefactos no corresponden a la versión del checkout.")
    if output.exists() and any(output.iterdir()):
        raise ValueError("El directorio de salida debe estar vacío.")
    output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(artifacts / "kaze-arm64/Kaze-Source.zip", output / "Kaze-Source.zip")
    for architecture in architectures:
        names = [f"Kaze-Mac-{architecture}.{extension}" for extension in ("dmg", "zip")]
        for name in names:
            shutil.copyfile(artifacts / f"kaze-{architecture}" / name, output / name)
        write_manifest(output / f"Kaze-SHA256-{architecture}.txt", output, names + ["Kaze-Source.zip"])
    write_manifest(output / "SHA256SUMS", output, sorted(path.name for path in output.iterdir()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--artifacts", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    arguments = parser.parse_args()
    project = pathlib.Path(__file__).resolve().parents[1]
    try:
        if arguments.check_only:
            validate_version(project, arguments.tag)
        else:
            if arguments.artifacts is None or arguments.output is None:
                parser.error("Se requieren --artifacts y --output.")
            prepare_release(project, arguments.tag, arguments.artifacts, arguments.output)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Release: {error}\n")
    print(f"Release {arguments.tag}: validación completada.")


if __name__ == "__main__":
    main()
