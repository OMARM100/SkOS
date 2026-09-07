# SkOS BIOS Bootloader — M1

## Current milestone

This milestone implements the first real BIOS boot path:

```text
BIOS
  ↓
LBA 0: boot16 (16-bit real mode)
  ↓ INT 13h Extensions / LBA
LBA 1..32: boot32
  ↓
32-bit protected mode
  ↓
VGA diagnostic + halt
```

The 64-bit long-mode transition is intentionally a separate next step.

## Disk layout

| LBA | Size | Component |
|---:|---:|---|
| 0 | 512 B | `boot16.bin` |
| 1–32 | 16 KiB | `boot32.bin` |

The development image is exactly 33 sectors.

## Stage 1 contract

`boot16.asm` is loaded by the BIOS at physical address `0x7C00`.

It:

1. establishes deterministic real-mode segments and stack;
2. preserves the BIOS boot drive;
3. verifies INT 13h Extensions (EDD);
4. reads 32 sectors starting at LBA 1 to physical `0x8000`;
5. performs a far jump to `0000:8000`.

The boot drive is also preserved at physical address `0x7BFE` for later stages.

## Stage 2 contract

`boot32.asm` starts at physical address `0x8000` in 16-bit real mode.

It:

1. disables interrupts;
2. establishes real-mode segment state;
3. enables A20 through the fast system-control port;
4. loads its private GDT;
5. sets `CR0.PE`;
6. performs a far jump to the 32-bit code selector;
7. initializes 32-bit data segments and stack at `0x90000`;
8. writes a temporary diagnostic marker to VGA text memory;
9. halts.

## Development rules

- Stage 1 remains small and disk-loader focused.
- Stage 2 owns the 16→32 transition.
- No kernel code is executed yet.
- No filesystem assumptions are made by the BIOS loader.
- The next boot step is 32→64 long mode, followed by a defined BootInfo handoff to the kernel.

## Build

From the repository root:

```bash
make
make run
```

The build intentionally validates that `boot16.bin` is exactly 512 bytes and `boot32.bin` is exactly 16 KiB.
