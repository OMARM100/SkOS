# SkOS BIOS Bootloader

## Current boot chain

```text
BIOS
  |
  v
boot16.asm   (16-bit real mode, sector 0)
  |
  | INT 13h Extensions / EDD
  | stage2 LBA + sector count from Boot Manifest
  v
boot32.asm   (16-bit entry -> 32-bit protected mode)
  |
  | kernel LBA + size + checksum from Boot Manifest
  | BIOS read -> staging buffer -> final physical address
  v
x86_64 long mode
  |
  | RDI = BootInfo
  v
kernel _start
```

The boot path now has a real metadata contract instead of assuming a fixed
stage-2 or kernel size. The current implementation is intentionally limited to
a single EDD transfer of at most 127 sectors for each BIOS read.

## Dynamic disk layout

`tools/build.py` measures the generated binaries and lays them out
consecutively:

```text
LBA 0                         boot16 (512 bytes)
LBA 1 .. stage2_end           boot32 (rounded to sectors)
next LBA .. kernel_end        kernel (rounded to sectors)
```

The image size is calculated as:

```text
1 + stage2_sectors + kernel_sectors
```

No fixed total image size is encoded in the build system.

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
| `0x38` | 8 | Kernel physical load address (reserved for future loaders) |
| `0x40` | 8 | Kernel entry address |
| `0x48` | 4 | Kernel CRC-32 |
| `0x4C` | 4 | Reserved |

The complete manifest is 80 bytes. Its position and format are intentionally
stable so future boot stages can consume the same metadata without assuming a
particular kernel size or disk location.

## Stage 1 policy

Stage 1 uses BIOS INT 13h Extensions (`AH=42h`). It reads the stage-2 LBA and
sector count from the manifest and copies them into its Disk Address Packet at
runtime. The current implementation performs one EDD transfer and therefore
the build system rejects stage 2 larger than 127 sectors.

## Stage 2 policy

Stage 2 validates the manifest, reads the kernel LBA/sector count, and performs
a second BIOS EDD transfer into a staging buffer below 1 MiB. It then copies the
exact kernel byte count to physical address `0x00100000`, verifies CRC-32, builds
minimal identity-mapped page tables, enables PAE + EFER.LME + paging, and enters
x86_64 long mode.

The initial page-table layout identity maps the first 2 MiB using one 2-MiB
page. This is deliberately minimal and will be replaced by the kernel's proper
VMM/page-table ownership in a later milestone.

## Kernel handoff

The bootloader constructs a minimal versioned BootInfo structure at physical
`0x93000` and enters the kernel through `_start` with:

```text
RDI = physical address of BootInfo
```

The current test kernel is linked at `0x00100000` and writes a visible long-mode
checkpoint to VGA text memory before halting. This is a bring-up test, not yet
the final kernel entry ABI.

## Build system

`Makefile` is only a thin entry point. The actual orchestration is in
`tools/build.py`.

The Python builder:

1. Assembles both BIOS stages.
2. Recursively discovers kernel `.c`, `.S`, and `.asm` files.
3. Compiles and links the kernel when `kernel/linker.ld` exists.
4. Calculates exact byte and sector sizes.
5. Calculates kernel CRC-32.
6. Patches the boot manifest.
7. Generates the raw BIOS image from the calculated layout.

Source paths are sorted before compilation, so adding a new kernel source file
does not require editing a source list in the build files.

Useful commands:

```bash
make
make info
make run
make clean
```

## Next architecture step

The next implementation work is to move the temporary BootInfo definition into
a shared kernel/boot ABI header, make the kernel own the early page tables, and
replace the temporary single-transfer BIOS policy with chunked disk reads. Then
we can proceed into the M1/M2 kernel initialization path without coupling the
kernel to BIOS implementation details.
