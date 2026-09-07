; SkOS BIOS stage 1
; 16-bit real-mode loader. The build system patches the boot manifest
; with the actual stage-2/kernel layout after assembly.

bits 16
org 0x7C00

%define BOOT_MANIFEST_OFFSET 0x180
%define BOOT_MANIFEST_SIZE   80
%define BOOT_DRIVE_ADDRESS   0x7BFE
%define STAGE2_LOAD_SEGMENT  0x0000
%define STAGE2_LOAD_OFFSET   0x8000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld

    ; Preserve the BIOS boot drive for later stages.
    mov [boot_drive], dl
    mov [BOOT_DRIVE_ADDRESS], dl

    ; Require INT 13h Extensions (EDD).
    mov ah, 0x41
    mov bx, 0x55AA
    int 0x13
    jc disk_error
    cmp bx, 0xAA55
    jne disk_error
    test cx, 1
    jz disk_error

    ; The manifest is patched by tools/build.py.
    ; DAP offset 2 = sector count (word).
    mov ax, [boot_manifest + 24]
    test ax, ax
    jz manifest_error
    mov [dap_sector_count], ax

    ; DAP offset 8 = starting LBA (qword).
    mov ax, [boot_manifest + 8]
    mov [dap_lba + 0], ax
    mov ax, [boot_manifest + 10]
    mov [dap_lba + 2], ax
    mov ax, [boot_manifest + 12]
    mov [dap_lba + 4], ax
    mov ax, [boot_manifest + 14]
    mov [dap_lba + 6], ax

    mov si, dap
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error

    jmp STAGE2_LOAD_SEGMENT:STAGE2_LOAD_OFFSET

manifest_error:
    mov si, msg_manifest
    jmp print_error

disk_error:
    mov si, msg_disk

print_error:
    mov ah, 0x0E
.print:
    lodsb
    test al, al
    jz .halt
    int 0x10
    jmp .print
.halt:
    cli
    hlt
    jmp .halt

boot_drive db 0

msg_disk db 'SkOS boot16: disk read error', 0
msg_manifest db 'SkOS boot16: invalid manifest', 0

; Disk Address Packet (DAP), BIOS INT 13h AH=42h.
dap:
    db 0x10                 ; packet size
    db 0                    ; reserved
    dw 0                    ; sector count (filled from manifest)
    dw STAGE2_LOAD_OFFSET  ; transfer offset
    dw STAGE2_LOAD_SEGMENT ; transfer segment
    dq 0                    ; starting LBA (filled from manifest)

dap_sector_count equ dap + 2
dap_lba equ dap + 8

; Fixed, versioned boot manifest. Build-time metadata is patched into the
; boot sector after NASM produces the 512-byte binary.
times BOOT_MANIFEST_OFFSET - ($ - $$) db 0
boot_manifest:
    db 'SKBM'              ; magic
    dw 1                   ; version
    dw BOOT_MANIFEST_SIZE  ; header size
    dq 0                   ; stage2_lba
    dq 0                   ; stage2_bytes
    dq 0                   ; stage2_sectors
    dq 0                   ; kernel_lba
    dq 0                   ; kernel_bytes
    dq 0                   ; kernel_sectors
    dq 0                   ; kernel_load_phys
    dq 0                   ; kernel_entry
    dd 0                   ; kernel_crc32
    dd 0                   ; reserved

; Boot signature must occupy bytes 510-511.
times 510 - ($ - $$) db 0
dw 0xAA55
