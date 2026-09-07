#!/usr/bin/env python3
"""SkOS automatic build and BIOS image generator.

The build graph is discovered from the repository instead of being maintained
as a hand-written source-file list. Boot metadata is generated from the actual
artifacts and patched into the stage-1 boot manifest.
"""

from __future__ import annotations

import argparse
import math
import os
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

SECTOR_SIZE = 512
BOOT_MANIFEST_OFFSET = 0x180
BOOT_MANIFEST_FORMAT = "<4sHHQQQQQQQQII"
BOOT_MANIFEST_SIZE = struct.calcsize(BOOT_MANIFEST_FORMAT)
BOOT_SIGNATURE_OFFSET = 510
STAGE2_LBA = 1
STAGE2_LOAD_ADDRESS = 0x8000
MAX_SINGLE_EDD_READ_SECTORS = 127

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
BIOS_BUILD = BUILD / "bios"
KERNEL_BUILD = BUILD / "kernel"
BOOT16_SRC = ROOT / "boot" / "bios" / "boot16.asm"
BOOT32_SRC = ROOT / "boot" / "bios" / "boot32.asm"
BOOT16_BIN = BIOS_BUILD / "boot16.bin"
BOOT32_BIN = BIOS_BUILD / "boot32.bin"
KERNEL_LINKER = ROOT / "kernel" / "linker.ld"
KERNEL_ELF = KERNEL_BUILD / "kernel.elf"
KERNEL_BIN = KERNEL_BUILD / "kernel.bin"
IMAGE = BIOS_BUILD / "skos-bios.img"


def die(message: str) -> "NoReturn":
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        die(f"required tool not found: {name}")
    return path


def run(command: list[str]) -> None:
    print("+", " ".join(command))
    subprocess.run(command, cwd=ROOT, check=True)


def sector_count(size: int) -> int:
    return math.ceil(size / SECTOR_SIZE)


def discover_kernel_sources() -> list[Path]:
    allowed = {".c", ".S", ".asm"}
    ignored_parts = {"build", ".git"}
    result: list[Path] = []
    kernel_root = ROOT / "kernel"
    if not kernel_root.exists():
        return result
    for path in kernel_root.rglob("*"):
        if not path.is_file() or path.suffix not in allowed:
            continue
        if any(part in ignored_parts for part in path.parts):
            continue
        result.append(path)
    return sorted(result)


def assemble_bootloader() -> tuple[bytes, bytes]:
    require_tool("nasm")
    BIOS_BUILD.mkdir(parents=True, exist_ok=True)

    run(["nasm", "-f", "bin", str(BOOT32_SRC), "-o", str(BOOT32_BIN)])
    run(["nasm", "-f", "bin", str(BOOT16_SRC), "-o", str(BOOT16_BIN)])

    boot16 = BOOT16_BIN.read_bytes()
    boot32 = BOOT32_BIN.read_bytes()

    if len(boot16) != SECTOR_SIZE:
        die(f"boot16 must be exactly 512 bytes, got {len(boot16)}")
    if boot16[BOOT_SIGNATURE_OFFSET : BOOT_SIGNATURE_OFFSET + 2] != b"\x55\xAA":
        die("boot16 is missing the 0xAA55 boot signature")
    if not boot32:
        die("boot32 is empty")

    return boot16, boot32


def compile_kernel() -> tuple[bytes, int] | tuple[None, None]:
    sources = discover_kernel_sources()
    if not KERNEL_LINKER.exists():
        if sources:
            die("kernel sources exist but kernel/linker.ld is missing")
        return None, None
    if not sources:
        die("kernel/linker.ld exists but no kernel source files were discovered")

    require_tool(os.environ.get("CC", "gcc"))
    require_tool(os.environ.get("LD", "ld"))
    require_tool(os.environ.get("OBJCOPY", "objcopy"))
    require_tool(os.environ.get("NM", "nm"))

    KERNEL_BUILD.mkdir(parents=True, exist_ok=True)
    objects: list[Path] = []

    cc = os.environ.get("CC", "gcc")
    for index, source in enumerate(sources):
        relative = source.relative_to(ROOT)
        object_path = KERNEL_BUILD / f"{index:04d}_{relative.name}.o"
        suffix = source.suffix
        if suffix == ".c":
            run([
                cc,
                "-std=c11",
                "-ffreestanding",
                "-fno-stack-protector",
                "-fno-pie",
                "-mno-red-zone",
                "-mcmodel=kernel",
                "-m64",
                "-Wall",
                "-Wextra",
                "-Ikernel/include",
                "-c",
                str(source),
                "-o",
                str(object_path),
            ])
        elif suffix == ".S":
            run([
                cc,
                "-ffreestanding",
                "-fno-pie",
                "-mno-red-zone",
                "-m64",
                "-Ikernel/include",
                "-c",
                str(source),
                "-o",
                str(object_path),
            ])
        elif suffix == ".asm":
            run(["nasm", "-f", "elf64", str(source), "-o", str(object_path)])
        objects.append(object_path)

    ld = os.environ.get("LD", "ld")
    run([
        ld,
        "-nostdlib",
        "-z",
        "max-page-size=0x1000",
        "-T",
        str(KERNEL_LINKER),
        "-o",
        str(KERNEL_ELF),
        *map(str, objects),
    ])

    objcopy = os.environ.get("OBJCOPY", "objcopy")
    run([objcopy, "-O", "binary", str(KERNEL_ELF), str(KERNEL_BIN)])

    kernel = KERNEL_BIN.read_bytes()
    if not kernel:
        die("kernel binary is empty")

    nm = os.environ.get("NM", "nm")
    result = subprocess.run(
        [nm, "-n", str(KERNEL_ELF)],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    entry: int | None = None
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] in {"_start", "kernel_entry"}:
            entry = int(fields[0], 16)
            if fields[2] == "_start":
                break
    if entry is None:
        die("kernel entry symbol '_start' or 'kernel_entry' was not found")

    return kernel, entry


def patch_manifest(boot16: bytes, stage2: bytes, kernel: bytes | None, kernel_entry: int | None) -> bytes:
    image_boot = bytearray(boot16)
    if BOOT_MANIFEST_OFFSET + BOOT_MANIFEST_SIZE > BOOT_SIGNATURE_OFFSET:
        die("boot manifest does not fit before the boot signature")

    stage2_bytes = len(stage2)
    stage2_sectors = sector_count(stage2_bytes)
    if stage2_sectors > MAX_SINGLE_EDD_READ_SECTORS:
        die(
            f"stage2 is {stage2_sectors} sectors; current BIOS loader supports at most "
            f"{MAX_SINGLE_EDD_READ_SECTORS} sectors per read"
        )

    kernel_bytes = len(kernel) if kernel is not None else 0
    kernel_sectors = sector_count(kernel_bytes) if kernel_bytes else 0
    kernel_lba = STAGE2_LBA + stage2_sectors if kernel_bytes else 0

    # Kernel physical loading/entry metadata is reserved for the long-mode
    # loader. Until that loader exists, keep the load target zero rather than
    # pretending that the 32-bit stage can directly execute the kernel.
    kernel_load_phys = 0
    kernel_entry_value = kernel_entry or 0
    kernel_crc32 = zlib.crc32(kernel) & 0xFFFFFFFF if kernel is not None else 0

    struct.pack_into(
        BOOT_MANIFEST_FORMAT,
        image_boot,
        BOOT_MANIFEST_OFFSET,
        b"SKBM",
        1,
        BOOT_MANIFEST_SIZE,
        STAGE2_LBA,
        stage2_bytes,
        stage2_sectors,
        kernel_lba,
        kernel_bytes,
        kernel_sectors,
        kernel_load_phys,
        kernel_entry_value,
        kernel_crc32,
        0,
    )
    return bytes(image_boot)


def build() -> None:
    boot16, stage2 = assemble_bootloader()
    kernel, kernel_entry = compile_kernel()
    boot16 = patch_manifest(boot16, stage2, kernel, kernel_entry)

    stage2_sectors = sector_count(len(stage2))
    kernel_sectors = sector_count(len(kernel)) if kernel else 0
    total_sectors = 1 + stage2_sectors + kernel_sectors

    BIOS_BUILD.mkdir(parents=True, exist_ok=True)
    with IMAGE.open("wb") as image:
        image.truncate(total_sectors * SECTOR_SIZE)
        image.seek(0)
        image.write(boot16)
        image.seek(STAGE2_LBA * SECTOR_SIZE)
        image.write(stage2)
        if kernel:
            image.seek((STAGE2_LBA + stage2_sectors) * SECTOR_SIZE)
            image.write(kernel)

    print()
    print("SkOS build complete")
    print(f"  boot16:       {len(boot16)} bytes")
    print(f"  stage2:       {len(stage2)} bytes / {stage2_sectors} sectors @ LBA {STAGE2_LBA}")
    if kernel:
        print(
            f"  kernel:       {len(kernel)} bytes / {kernel_sectors} sectors "
            f"@ LBA {STAGE2_LBA + stage2_sectors}"
        )
        print(f"  kernel entry: 0x{kernel_entry:016x}")
    else:
        print("  kernel:       not built (kernel/linker.ld not present yet)")
    print(f"  image:        {IMAGE} ({total_sectors} sectors)")


def info() -> None:
    sources = discover_kernel_sources()
    print(f"repo:          {ROOT}")
    print(f"kernel sources: {len(sources)}")
    for source in sources:
        print(f"  - {source.relative_to(ROOT)}")
    print(f"kernel linker: {'present' if KERNEL_LINKER.exists() else 'not present'}")
    print(f"manifest:      offset=0x{BOOT_MANIFEST_OFFSET:x}, size={BOOT_MANIFEST_SIZE} bytes")
    print(f"stage2 limit:  {MAX_SINGLE_EDD_READ_SECTORS} sectors/read")


def clean() -> None:
    if BUILD.exists():
        shutil.rmtree(BUILD)
    (BUILD / ".gitkeep").parent.mkdir(parents=True, exist_ok=True)
    (BUILD / ".gitkeep").touch()
    print("clean: build artifacts removed")


def run_qemu() -> None:
    if not IMAGE.exists():
        build()
    qemu = os.environ.get("QEMU", "qemu-system-x86_64")
    require_tool(qemu)
    run([qemu, "-drive", f"format=raw,file={IMAGE}"])


def main() -> None:
    parser = argparse.ArgumentParser(description="Build SkOS and generate its BIOS disk image")
    parser.add_argument("command", nargs="?", choices=["build", "run", "clean", "info"], default="build")
    args = parser.parse_args()

    if args.command == "build":
        build()
    elif args.command == "run":
        build()
        run_qemu()
    elif args.command == "clean":
        clean()
    elif args.command == "info":
        info()


if __name__ == "__main__":
    main()
