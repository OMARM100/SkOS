bits 64

global _start
section .text.boot
_start:
    cli
    mov rsp, 0x0000000000088000

    ; RDI contains BootInfo from the bootloader.
    mov rax, 0xB8000
    mov word [rax], 0x074B
    mov word [rax + 2], 0x076F
    mov word [rax + 4], 0x074B
    mov word [rax + 6], 0x0741
    mov word [rax + 8], 0x074D
    mov word [rax + 10], 0x0744
    mov word [rax + 12], 0x073A
    mov word [rax + 14], 0x0200
    mov word [rax + 16], 0x074C
    mov word [rax + 18], 0x076F
    mov word [rax + 20], 0x074E
    mov word [rax + 22], 0x0747
    mov word [rax + 24], 0x074D
    mov word [rax + 26], 0x074F
    mov word [rax + 28], 0x0744
    mov word [rax + 30], 0x0745
    mov word [rax + 32], 0x0200

.hang:
    hlt
    jmp .hang
