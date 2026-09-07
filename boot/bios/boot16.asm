; SkOS BIOS bootstrap - stage 1
; 16-bit real-mode boot sector.
;
; Disk layout:
;   LBA 0       : boot16 (this sector)
;   LBA 1..32   : boot32 (32 sectors / 16 KiB reserved)
;
; boot32 is loaded to physical address 0x8000 and entered with a far jump.
; The BIOS boot drive is preserved at 0x7BFE for the next stage.

BITS 16
ORG 0x7C00

%define STAGE2_LOAD_ADDR  0x8000
%define STAGE2_SECTORS    32
%define BOOT_DRIVE_ADDR   0x7BFE

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld

    mov [boot_drive], dl
    mov [BOOT_DRIVE_ADDR], dl

    ; Verify INT 13h Extensions (EDD) before using an LBA read.
    mov ah, 0x41
    mov bx, 0x55AA
    int 0x13
    jc disk_error
    cmp bx, 0xAA55
    jne disk_error
    test cx, 1
    jz disk_error

    ; Read the complete reserved stage-2 area from LBA 1.
    mov si, disk_address_packet
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error

    cli
    jmp 0x0000:STAGE2_LOAD_ADDR

disk_error:
    mov si, msg_error
    call print_string
.halt:
    cli
    hlt
    jmp .halt

print_string:
.next:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    mov bh, 0x00
    int 0x10
    jmp .next
.done:
    ret

boot_drive db 0
msg_error db 'SkOS boot16: disk read failed', 13, 10, 0

disk_address_packet:
    db 0x10, 0x00
    dw STAGE2_SECTORS
    dw STAGE2_LOAD_ADDR
    dw 0x0000
    dq 0x0000000000000001

times 510-($-$$) db 0
dw 0xAA55
