# SkOS BIOS Bootloader

## Current boot chain

```text
BIOS
  |
  v
boot16.asm   (16-bit real mode, sector 0)
  |
  | INT 13h Extensions / EDD
  | reads stage2 using the boot manifest
  v
boot32.asm   (16-bit entry -> 32-bit protected mode)
  |
  v
halt / diagnostic checkpoint
```

The next bootloader milestone is the 32-bit to 64-bit long-mode transition,
followed by kernel loading and a versioned BootInfo handoff.

## Dynamic disk layout

The disk image is no longer built around a fixed stage-2 size or a fixed total
sector count. `tools/build.py` measures the generated binaries and lays them
out consecutively:

```text
LBA 0                         boot16 (512 bytes)
LBA 1 .. stage2_end           boot32 (rounded to sectors)
next LBA .. kernel_end       kernel (when a kernel linker script exists)
```

The image size is therefore:

```text
1 + stage2_sectors + kernel_sectors
```

where both sector counts are calculated by the build system.

## Boot manifest

`boot16` contains a fixed-position, versioned manifest beginning at byte
`0x180`. The build system patches it after NASM assembly.

| Offset | Size | Field |
|---:|---:|---|
| `0x00` | 4 | Magic `SKBM` |
| `0x04` | 2 | Manifest version |
| `0x06` | 2 | Header size |
| `0x08` | 8 | Stage-2 LBA |
| `0x10` | 8 | Stage-2 byte size |
| `0x18` | 8 | Stage-2 sector count |
| `0x20` | 8 | Kernel LBA |
| `0x28` | 8 | Kernel byte size |
| `0x30` | 8 | Kernel sector count |
| `0x38` | 8 | Kernel physical load address |
| `0x40` | 8 | Kernel entry address |
| `0x48` | 4 | Kernel CRC-32 |
| `0x4C` | 4 | Reserved |

The complete manifest is 80 bytes. Its position and format are intentionally
stable so future boot stages can consume the same metadata without assuming a
particular kernel size or disk location.

At the current stage, the kernel load address remains zero because stage 2
has not implemented long mode and kernel loading yet. The kernel entry address
and checksum are nevertheless generated once a kernel build is introduced.

## Stage-1 loading policy

Stage 1 uses BIOS INT 13h Extensions (`AH=42h`) and copies the manifest's
stage-2 LBA and sector count into the Disk Address Packet at runtime. The
current implementation performs one EDD transfer and therefore enforces a
127-sector maximum for stage 2 at build time. A larger stage 2 will fail the
build rather than silently producing an image the current loader cannot read.

## Build system

`Makefile` is now only a thin entry point. The actual build orchestration is in
`tools/build.py`.

The Python build system:

1. Assembles the BIOS boot stages.
2. Recursively discovers kernel `.c`, `.S`, and `.asm` files.
3. Compiles and links the kernel when `kernel/linker.ld` exists.
4. Calculates exact byte and sector sizes.
5. Calculates the kernel CRC-32.
6. Patches the boot manifest.
7. Generates the raw BIOS image using the calculated layout.

This means adding a new kernel source file does **not** require editing a
source list in the build files. Source discovery is deterministic because the
paths are sorted before compilation.

Useful commands:

```bash
make
make info
make run
make clean
```

## Next implementation step

The next bootloader change should make `boot32` consume the manifest, build the
required paging structures, enter x86_64 long mode, load the kernel according
to its manifest metadata, verify its checksum, and transfer control through a
versioned kernel-entry/BootInfo ABI.
