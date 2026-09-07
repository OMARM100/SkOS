bits 64

global _start
section .text.boot
_start:
    cli

    ; RDI contains struct skos_bootinfo * from the BIOS bootloader.
    ; Validate the ABI before doing anything else in the kernel.
    test rdi, rdi
    jz .halt
    cmp dword [rdi], 0x534B4249 ; "SKBI"
    jne .halt
    cmp word [rdi + 4], 1
    jne .halt
    cmp word [rdi + 6], 64
    jne .halt

    mov rsp, 0x00000000000B0000

    mov rax, 0xB8000
    mov word [rax + 0], 0x0753 ; S
    mov word [rax + 2], 0x076B ; k
    mov word [rax + 4], 0x074F ; O
    mov word [rax + 6], 0x0753 ; S
    mov word [rax + 8], 0x0720 ; space
    mov word [rax + 10], 0x0742 ; B
    mov word [rax + 12], 0x076F ; o
    mov word [rax + 14], 0x074F ; O
    mov word [rax + 16], 0x074C ; L
    mov word [rax + 18], 0x0720 ; space
    mov word [rax + 20], 0x074F ; O
    mov word [rax + 22], 0x074B ; K

.hang:
    hlt
    jmp .hang

.halt:
    cli
    hlt
    jmp .halt
