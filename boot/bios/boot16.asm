; SkOS BIOS stage 1
; Loads stage 2 using the build-generated manifest in the boot sector.

bits 16
org 0x7C00

%include "../include/boot_protocol.inc"

%define BOOT_DRIVE_ADDRESS   0x7BFE
%define STAGE2_LOAD_SEGMENT  0x0000
%define STAGE2_LOAD_OFFSET   0x8000
%define MAX_EDD_SECTORS      127

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld

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

    ; Validate the build-generated manifest before trusting its fields.
    cmp dword [boot_manifest], BOOT_MANIFEST_MAGIC
    jne manifest_error
    cmp word [boot_manifest + 4], BOOT_MANIFEST_VERSION
    jne manifest_error
    cmp word [boot_manifest + 6], BOOT_MANIFEST_SIZE
    jb manifest_error

    mov ax, [boot_manifest + MANIFEST_STAGE2_SECTORS]
    test ax, ax
    jz manifest_error
    cmp ax, MAX_EDD_SECTORS
    ja manifest_error
    mov [dap_sector_count], ax

    mov eax, dword [boot_manifest + MANIFEST_STAGE2_LBA]
    mov dword [dap_lba], eax
    mov eax, dword [boot_manifest + MANIFEST_STAGE2_LBA + 4]
    mov dword [dap_lba + 4], eax

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

dap:
    db 0x10
    db 0
    dw 0
    dw STAGE2_LOAD_OFFSET
    dw STAGE2_LOAD_SEGMENT
    dq 0

dap_sector_count equ dap + 2
dap_lba equ dap + 8

times BOOT_MANIFEST_OFFSET - ($ - $$) db 0
boot_manifest:
    db 'SKBM'
    dw BOOT_MANIFEST_VERSION
    dw BOOT_MANIFEST_SIZE
    times BOOT_MANIFEST_SIZE - 8 db 0

times 510 - ($ - $$) db 0
dw 0xAA55
