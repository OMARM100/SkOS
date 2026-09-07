; SkOS BIOS stage 2: real mode -> protected mode -> long mode.
; Kernel metadata comes from the versioned boot manifest in sector 0.

bits 16
org 0x8000

%define BOOT_SECTOR_PHYS        0x7C00
%define MANIFEST_PHYS           (BOOT_SECTOR_PHYS + 0x180)
%define MANIFEST_KERNEL_LBA     (MANIFEST_PHYS + 0x20)
%define MANIFEST_KERNEL_BYTES   (MANIFEST_PHYS + 0x28)
%define MANIFEST_KERNEL_SECTORS (MANIFEST_PHYS + 0x30)
%define MANIFEST_KERNEL_ENTRY   (MANIFEST_PHYS + 0x40)
%define MANIFEST_KERNEL_CRC     (MANIFEST_PHYS + 0x48)

%define KERNEL_STAGING_PHYS     0x00020000
%define KERNEL_LOAD_PHYS        0x00100000
%define BOOTINFO_PHYS           0x00093000
%define PML4_PHYS               0x00090000
%define PDPT_PHYS               0x00091000
%define PD_PHYS                 0x00092000
%define STACK_PHYS              0x00088000

bits 16
start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x8800
    mov [boot_drive], dl

    ; Fast A20 gate. QEMU normally starts with A20 enabled, but the
    ; bootloader must not depend on firmware state before using >1 MiB.
    in al, 0x92
    or al, 0x02
    and al, 0xFE
    out 0x92, al

    lgdt [gdt16_descriptor]
    mov eax, cr0
    or eax, 1
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
    mov esp, STACK_PHYS

    cmp dword [MANIFEST_PHYS], 0x4D424B53 ; "SKBM"
    jne manifest_error
    cmp word [MANIFEST_PHYS + 4], 1
    jne manifest_error

    mov eax, dword [MANIFEST_KERNEL_SECTORS]
    test eax, eax
    jz kernel_missing
    cmp eax, 127
    ja kernel_too_large

    ; Build the kernel EDD packet. BIOS reads require real mode.
    mov eax, dword [MANIFEST_KERNEL_LBA]
    mov dword [kernel_dap + 8], eax
    mov eax, dword [MANIFEST_KERNEL_LBA + 4]
    mov dword [kernel_dap + 12], eax
    mov ax, word [MANIFEST_KERNEL_SECTORS]
    mov word [kernel_dap + 2], ax

    mov eax, cr0
    and eax, 0xFFFFFFFE
    mov cr0, eax
    jmp 0x0000:realmode_kernel_read

bits 16
realmode_kernel_read:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x8800
    mov dl, [boot_drive]
    mov si, kernel_dap
    mov ah, 0x42
    int 0x13
    jc disk_error

    cli
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:kernel_copy

bits 32
kernel_copy:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov esp, STACK_PHYS

    mov esi, KERNEL_STAGING_PHYS
    mov edi, KERNEL_LOAD_PHYS
    mov ecx, dword [MANIFEST_KERNEL_BYTES]
    test ecx, ecx
    jz kernel_missing
    cld
    rep movsb

    push dword [MANIFEST_KERNEL_BYTES]
    push dword KERNEL_LOAD_PHYS
    call crc32_buffer
    add esp, 8
    cmp eax, dword [MANIFEST_KERNEL_CRC]
    jne checksum_error

    ; Zero page-table pages and BootInfo storage.
    mov edi, PML4_PHYS
    xor eax, eax
    mov ecx, 3072
    rep stosd

    mov dword [PML4_PHYS], PDPT_PHYS | 0x003
    mov dword [PDPT_PHYS], PD_PHYS | 0x003
    mov dword [PD_PHYS], 0x00000083
    mov dword [PD_PHYS + 4], 0

    mov edi, BOOTINFO_PHYS
    xor eax, eax
    mov ecx, 64
    rep stosd
    mov dword [BOOTINFO_PHYS], 0x534B4249 ; "SKBI"
    mov word [BOOTINFO_PHYS + 4], 1
    mov word [BOOTINFO_PHYS + 6], 64
    mov dword [BOOTINFO_PHYS + 8], KERNEL_LOAD_PHYS
    mov eax, dword [MANIFEST_KERNEL_BYTES]
    mov dword [BOOTINFO_PHYS + 12], eax
    mov eax, dword [MANIFEST_KERNEL_ENTRY]
    mov dword [BOOTINFO_PHYS + 16], eax
    mov eax, dword [MANIFEST_KERNEL_ENTRY + 4]
    mov dword [BOOTINFO_PHYS + 20], eax
    mov dword [BOOTINFO_PHYS + 24], MANIFEST_PHYS
    mov eax, dword [MANIFEST_KERNEL_CRC]
    mov dword [BOOTINFO_PHYS + 28], eax

    ; Enable PAE and long-mode extension.
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    mov eax, PML4_PHYS
    mov cr3, eax
    mov eax, cr0
    or eax, (1 << 31) | 1
    mov cr0, eax

    lgdt [gdt64_descriptor]
    jmp 0x18:long_mode

bits 64
long_mode:
    mov ax, 0x20
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov rsp, STACK_PHYS

    ; Boot ABI: RDI points to the versioned BootInfo structure.
    mov rdi, BOOTINFO_PHYS
    mov rax, qword [MANIFEST_KERNEL_ENTRY]
    test rax, rax
    jz .halt
    jmp rax
.halt:
    cli
    hlt
    jmp .halt

bits 32
crc32_buffer:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    mov esi, [ebp + 8]
    mov ecx, [ebp + 12]
    mov eax, 0xFFFFFFFF
.next_byte:
    test ecx, ecx
    jz .done
    movzx ebx, byte [esi]
    xor eax, ebx
    mov edi, 8
.bit:
    shr eax, 1
    jnc .no_poly
    xor eax, 0xEDB88320
.no_poly:
    dec edi
    jnz .bit
    inc esi
    dec ecx
    jmp .next_byte
.done:
    not eax
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret

bits 16
kernel_dap:
    db 0x10
    db 0
    dw 0
    dw KERNEL_STAGING_PHYS & 0x000F
    dw KERNEL_STAGING_PHYS >> 4
    dq 0

boot_drive db 0

msg_disk db 'SkOS: kernel disk read error', 0
msg_manifest db 'SkOS: invalid boot manifest', 0
msg_no_kernel db 'SkOS: kernel not present', 0
msg_kernel_large db 'SkOS: kernel too large', 0
msg_checksum db 'SkOS: kernel checksum error', 0

bits 32
print_error:
    mov edi, 0xB8000
    mov ah, 0x07
.print:
    lodsb
    test al, al
    jz .halt
    stosb
    mov byte [edi], ah
    inc edi
    jmp .print
.halt:
    cli
    hlt
    jmp .halt

manifest_error:
    mov esi, msg_manifest
    jmp print_error
kernel_missing:
    mov esi, msg_no_kernel
    jmp print_error
kernel_too_large:
    mov esi, msg_kernel_large
    jmp print_error
checksum_error:
    mov esi, msg_checksum
    jmp print_error
disk_error:
    mov esi, msg_disk
    jmp print_error

bits 16
align 8
gdt16:
    dq 0x0000000000000000
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
gdt16_end:
gdt16_descriptor:
    dw gdt16_end - gdt16 - 1
    dd gdt16

align 8
gdt64:
    dq 0x0000000000000000
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
    dq 0x00AF9A000000FFFF
    dq 0x00AF92000000FFFF
gdt64_end:
gdt64_descriptor:
    dw gdt64_end - gdt64 - 1
    dq gdt64
