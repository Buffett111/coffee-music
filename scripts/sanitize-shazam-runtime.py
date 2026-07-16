#!/usr/bin/env python3
"""Produce a privacy-clean runtime for CoffeeSync's bundled Python engine.

The ShazamIO runtime is intentionally checked in so the app remains usable
without a separate Python installation.  This tool removes package managers,
developer entry points, tests, bytecode caches, and build metadata that are
not needed at runtime.  It also strips native debug symbols before a release
bundle is signed.

Native extension modules may contain source-location strings that are used by
their own error handling.  Those are not safe to alter in-place: replacing a
NUL-terminated string can corrupt the module.  This script therefore only
normalizes text metadata and relies on symbol stripping for native binaries.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
from pathlib import Path


TEXT_PATH = re.compile(rb"/(?:Users|private/var/folders)/[^\r\n\"']+")
DEVELOPMENT_PACKAGES = (
    "_distutils_hack",
    "pip",
    "pip-26.1.2.dist-info",
    "setuptools",
    "setuptools-82.0.1.dist-info",
)
STDLIB_DEVELOPMENT_DIRECTORIES = (
    "config-3.10-darwin",
    "distutils",
    "ensurepip",
    "idlelib",
    "lib2to3",
    "pydoc_data",
    "test",
    "tkinter",
    "turtledemo",
    "venv",
)


def remove(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)


def redact_text_metadata(path: Path) -> bool:
    content = path.read_bytes()
    if b"\x00" in content or (
        b"/Users/" not in content and b"/private/var/folders/" not in content
    ):
        return False
    updated = TEXT_PATH.sub(b"/redacted", content)

    if updated == content:
        return False
    path.write_bytes(updated)
    return True


def strip_native_binaries(runtime: Path) -> int:
    candidates = [runtime / "bin" / "python3.10"]
    candidates.extend(runtime.rglob("*.dylib"))
    candidates.extend(runtime.rglob("*.so"))
    stripped = 0
    for candidate in candidates:
        if not candidate.is_file():
            continue
        result = subprocess.run(
            ["strip", "-S", str(candidate)],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(f"Unable to strip {candidate}: {result.stderr.strip()}")
        stripped += 1
    return stripped


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("runtime", type=Path)
    arguments = parser.parse_args()
    runtime = arguments.runtime.resolve()
    site_packages = runtime / "lib" / "python3.10" / "site-packages"
    stdlib = runtime / "lib" / "python3.10"
    if not (runtime / "bin" / "python3.10").is_file() or not site_packages.is_dir():
        raise SystemExit("Expected a CoffeeSync Python 3.10 runtime directory.")

    for entry in (runtime / "bin").iterdir():
        if entry.name != "python3.10":
            remove(entry)
    for package in DEVELOPMENT_PACKAGES:
        remove(site_packages / package)
    remove(site_packages / "distutils-precedence.pth")
    for directory in STDLIB_DEVELOPMENT_DIRECTORIES:
        remove(stdlib / directory)
    for directory in (runtime / "lib").glob("itcl*"):
        remove(directory)
    for directory in (runtime / "lib").glob("tcl*"):
        remove(directory)
    for directory in (runtime / "lib").glob("tk*"):
        remove(directory)
    for directory in (runtime / "lib").glob("thread*"):
        remove(directory)
    for binary in (runtime / "lib").glob("libtcl*"):
        remove(binary)
    for binary in (runtime / "lib").glob("libtk*"):
        remove(binary)
    for directory in site_packages.rglob(".hash"):
        remove(directory)
    for directory in site_packages.rglob("tests"):
        remove(directory)
    for directory in site_packages.rglob("test"):
        remove(directory)
    for directory in site_packages.rglob("testing"):
        remove(directory)
    remove(site_packages / "numpy" / "distutils")
    for directory in site_packages.rglob("sboms"):
        remove(directory)
    for directory in runtime.rglob("__pycache__"):
        remove(directory)
    for bytecode in runtime.rglob("*.pyc"):
        remove(bytecode)

    stripped = strip_native_binaries(runtime)
    text_extensions = {".cfg", ".hash", ".json", ".py", ".sh", ".txt"}
    redacted = sum(
        redact_text_metadata(path)
        for path in runtime.rglob("*")
        if path.is_file() and path.suffix in text_extensions
    )
    print(
        f"Sanitized {runtime}: stripped {stripped} native files; "
        f"redacted {redacted} text metadata files."
    )


if __name__ == "__main__":
    main()
