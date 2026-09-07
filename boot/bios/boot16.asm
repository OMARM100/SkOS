; SkOS BIOS bootstrap - stage 1
; 16-bit real mode entry point.
; This stage deliberately does only early CPU/disk preparation and
; transfers control to the 32-bit stage.
;
; Layout assumption for the first development image:
;   LBA 0: this 512-byte boot sector
;   Later LBAs: stage2.bin (loaded by a future disk-loader implementation)
;
BITS 16
ORG 0x7C00

%define STAGE2_LOAD_SEG 0x0800
%define STAGE2_LOAD_OFF 0x0000
%define STAGE2_LOAD_ADDR 0x8000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; Preserve BIOS boot drive for the disk-loading stage.
    mov [boot_drive], dl

    ; Make the CPU state deterministic before handing off.
    cld

    ; TODO(M1): load boot32.bin from disk into 0x8000.
    ; For now this is an explicit development stop so the stage boundary
    ; remains clear while the disk format/loader is being implemented.
    mov si, msg_stage1
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
msg_stage1 db 'SkOS boot16: real mode stage ready', 13, 10, 0

times 510-($-$$) db 0
dw 0xAA55
