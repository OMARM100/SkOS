; SkOS BIOS bootstrap - stage 2
; 32-bit protected-mode entry point.
; Entered by boot16 after the stage-2 image has been loaded at 0x8000.
;
; The 16 -> 32 transition is intentionally isolated in this file so the
; protected-mode implementation can evolve without touching stage 1.

BITS 16
ORG 0x8000

%define CODE32 0x08
%define DATA32 0x10

stage2_start:
    cli

    ; Disable legacy NMI while changing descriptor state.
    in al, 0x70
    or al, 0x80
    out 0x70, al

    lgdt [gdt_descriptor]

    ; Enter protected mode.
    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax

    jmp CODE32:protected_mode_entry

BITS 32
protected_mode_entry:
    mov ax, DATA32
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    mov esp, 0x90000

    ; Development marker. A real implementation will replace this with
    ; hardware-independent boot services and then the 64-bit transition.
    mov esi, msg_stage2
    call print_string_32

.halt:
    cli
    hlt
    jmp .halt

print_string_32:
    ; VGA text memory is used only as a temporary BIOS-stage diagnostic.
    mov edi, 0xB8000
    mov ah, 0x07
.next:
    lodsb
    test al, al
    jz .done
    mov [edi], ax
    add edi, 2
    jmp .next
.done:
    ret

align 8
GDT_START:
    dq 0x0000000000000000
    ; 32-bit code: base 0, limit 4 GiB, executable/readable.
    dq 0x00CF9A000000FFFF
    ; 32-bit data: base 0, limit 4 GiB, writable.
    dq 0x00CF92000000FFFF
GDT_END:

gdt_descriptor:
    dw GDT_END - GDT_START - 1
    dd GDT_START

msg_stage2 db 'SkOS boot32: protected mode entered', 0
