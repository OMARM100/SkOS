; SkOS BIOS bootstrap - stage 2
; 32-bit protected-mode entry point.
;
; Entered by boot16 at physical address 0x8000.
; This stage owns the 16 -> 32 transition and provides a deterministic
; protected-mode environment for the next boot milestone.

BITS 16
ORG 0x8000

%define CODE32 0x08
%define DATA32 0x10

stage2_start:
    cli
    cld

    ; Start with known real-mode segment state.
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; Enable A20 using the fast system-control port supported by QEMU.
    in al, 0x92
    or al, 0x02
    and al, 0xFE
    out 0x92, al

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

    ; Temporary diagnostic only. Later milestones replace this with
    ; architecture-independent boot services and the 64-bit transition.
    mov esi, msg_stage2
    call print_string_32

.halt:
    cli
    hlt
    jmp .halt

print_string_32:
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

; Stage 1 reserves exactly 32 sectors for this stage.
; Fail the build if stage 2 ever outgrows the reserved region.
times 16384-($-$$) db 0
