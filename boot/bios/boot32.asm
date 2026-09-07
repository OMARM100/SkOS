; SkOS BIOS stage 2
; 16-bit entry from stage 1, then transition to 32-bit protected mode.
; The build system determines the exact stage-2 size; this file has no
; fixed-size padding requirement.

bits 16
org 0x8000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x9000

    ; Enable A20 using the fast gate.
    in al, 0x92
    or al, 00000010b
    out 0x92, al

    lgdt [gdt_descriptor]

    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax

    jmp 0x08:protected_mode

bits 32
protected_mode:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov esp, 0x90000

    ; Diagnostic checkpoint. Long mode and kernel loading come next.
    mov edi, 0xB8000
    mov esi, message
.write:
    lodsb
    test al, al
    jz .halt
    mov [edi], al
    mov byte [edi + 1], 0x07
    add edi, 2
    jmp .write
.halt:
    cli
    hlt
    jmp .halt

align 8
GDT:
    dq 0x0000000000000000
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
GDT_end:

gdt_descriptor:
    dw GDT_end - GDT - 1
    dd GDT

message db 'SkOS boot32: protected mode entered', 0
