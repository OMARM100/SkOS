; SkOS BIOS stage 2
; Protocol: real-mode BIOS load -> protected mode -> long mode -> kernel.
; The kernel layout is completely described by the LBA0 manifest.

bits 16
org 0x8000

%include "boot/include/boot_protocol.inc"

%define BOOT_SECTOR_PHYS        0x00007C00
%define MANIFEST_PHYS           (BOOT_SECTOR_PHYS + BOOT_MANIFEST_OFFSET)

; Bootloader-owned low memory.
; Kernel staging is intentionally below 640 KiB so the BIOS DAP can reach it.
%define KERNEL_STAGING_PHYS     0x00020000
%define KERNEL_STAGING_LIMIT    0x000A0000
%define MAX_KERNEL_SECTORS      ((KERNEL_STAGING_LIMIT - KERNEL_STAGING_PHYS) / 512)

%define STACK_PHYS              0x000A4000
%define PML4_PHYS               0x000A5000
%define PDPT_PHYS               0x000A6000
%define PD_PHYS                 0x000A7000
%define BOOTINFO_PHYS           0x000A8000

%define MAX_EDD_SECTORS         127
%define MAX_IDENTITY_PHYS       0x40000000 ; 1 GiB, covered by one PD
%define TWO_MIB                 0x00200000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x8800
    cld
    mov [boot_drive], dl

    ; Validate the common manifest first.
    cmp dword [MANIFEST_PHYS], BOOT_MANIFEST_MAGIC
    jne manifest_error_rm
    cmp word [MANIFEST_PHYS + 4], BOOT_MANIFEST_VERSION
    jne manifest_error_rm
    cmp word [MANIFEST_PHYS + 6], BOOT_MANIFEST_SIZE
    jb manifest_error_rm

    ; Kernel size/sectors are limited by our low-memory staging window.
    mov eax, dword [MANIFEST_PHYS + MANIFEST_KERNEL_SECTORS]
    mov edx, dword [MANIFEST_PHYS + MANIFEST_KERNEL_SECTORS + 4]
    test edx, edx
    jnz kernel_too_large_rm
    test eax, eax
    jz kernel_missing_rm
    cmp eax, MAX_KERNEL_SECTORS
    ja kernel_too_large_rm
    mov [kernel_sectors_remaining], eax

    mov eax, dword [MANIFEST_PHYS + MANIFEST_KERNEL_BYTES]
    mov edx, dword [MANIFEST_PHYS + MANIFEST_KERNEL_BYTES + 4]
    test edx, edx
    jnz kernel_too_large_rm
    test eax, eax
    jz kernel_missing_rm
    mov [kernel_bytes_runtime], eax

    ; The first-stage manifest stores a 64-bit load address, but this BIOS
    ; loader deliberately supports physical addresses below 4 GiB only.
    mov eax, dword [MANIFEST_PHYS + MANIFEST_KERNEL_LOAD]
    mov edx, dword [MANIFEST_PHYS + MANIFEST_KERNEL_LOAD + 4]
    test edx, edx
    jnz invalid_layout_rm
    cmp eax, 0x00100000
    jb invalid_layout_rm
    mov [kernel_load_phys], eax

    mov eax, dword [MANIFEST_PHYS + MANIFEST_KERNEL_ENTRY]
    mov edx, dword [MANIFEST_PHYS + MANIFEST_KERNEL_ENTRY + 4]
    test edx, edx
    jnz invalid_layout_rm
    mov [kernel_entry], eax

    ; Check kernel_bytes <= kernel_sectors * 512.
    mov eax, [kernel_sectors_remaining]
    shl eax, 9
    cmp [kernel_bytes_runtime], eax
    ja invalid_layout_rm

    ; Check load + kernel_bytes without 32-bit wraparound and keep the whole
    ; image inside the identity-mapped 1 GiB bootstrap address space.
    mov eax, [kernel_load_phys]
    add eax, [kernel_bytes_runtime]
    jc invalid_layout_rm
    cmp eax, MAX_IDENTITY_PHYS
    ja invalid_layout_rm
    mov [kernel_end_phys], eax

    ; Entry must point inside the loaded image.
    mov eax, [kernel_entry]
    cmp eax, [kernel_load_phys]
    jb invalid_layout_rm
    cmp eax, [kernel_end_phys]
    jae invalid_layout_rm

    ; BIOS EDD disk reads happen entirely in real mode. The kernel is loaded
    ; in <=127-sector chunks into consecutive low-memory staging buffers.
    mov eax, dword [MANIFEST_PHYS + MANIFEST_KERNEL_LBA]
    mov dword [kernel_dap + 8], eax
    mov eax, dword [MANIFEST_PHYS + MANIFEST_KERNEL_LBA + 4]
    mov dword [kernel_dap + 12], eax
    mov word [kernel_dap + 6], KERNEL_STAGING_PHYS >> 4

.load_chunk:
    mov eax, [kernel_sectors_remaining]
    test eax, eax
    jz .disk_done
    cmp eax, MAX_EDD_SECTORS
    jbe .count_ready
    mov eax, MAX_EDD_SECTORS
.count_ready:
    mov word [kernel_dap + 2], ax

    mov si, kernel_dap
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error_rm

    ; Advance LBA by the chunk size.
    movzx eax, word [kernel_dap + 2]
    add dword [kernel_dap + 8], eax
    adc dword [kernel_dap + 12], 0

    ; 512 bytes = 32 paragraphs. Advance the DAP buffer segment accordingly.
    shl ax, 5
    add word [kernel_dap + 6], ax

    sub dword [kernel_sectors_remaining], eax
    jmp .load_chunk

.disk_done:
    ; Fast A20 gate. The kernel is loaded above 1 MiB.
    in al, 0x92
    or al, 0x02
    and al, 0xFE
    out 0x92, al

    lgdt [gdt32_descriptor]
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
    cld

    ; Copy the complete staged image to its build-selected physical address.
    mov esi, KERNEL_STAGING_PHYS
    mov edi, [kernel_load_phys]
    mov ecx, [kernel_bytes_runtime]
    rep movsb

    ; Validate the exact bytes that will be executed.
    push dword [kernel_bytes_runtime]
    push dword [kernel_load_phys]
    call crc32_buffer
    add esp, 8
    cmp eax, dword [MANIFEST_PHYS + MANIFEST_KERNEL_CRC32]
    jne checksum_error

    ; Clear the bootstrap page-table pages and BootInfo.
    mov edi, PML4_PHYS
    xor eax, eax
    mov ecx, 4096
    rep stosd

    ; Identity map from physical 0 through kernel_end using 2 MiB pages.
    ; One PD is enough because the supported bootstrap range is 1 GiB.
    mov eax, [kernel_end_phys]
    add eax, TWO_MIB - 1
    shr eax, 21
    test eax, eax
    jz invalid_layout
    cmp eax, 512
    ja invalid_layout
    mov [identity_page_count], eax

    mov dword [PML4_PHYS], PDPT_PHYS | 0x003
    mov dword [PML4_PHYS + 4], 0
    mov dword [PDPT_PHYS], PD_PHYS | 0x003
    mov dword [PDPT_PHYS + 4], 0

    mov edi, PD_PHYS
    xor eax, eax
    mov ecx, [identity_page_count]
.fill_pd:
    mov dword [edi], eax
    mov dword [edi + 4], 0
    or dword [edi], 0x083 ; present | writable | 2 MiB page
    add eax, TWO_MIB
    add edi, 8
    loop .fill_pd

    mov edi, BOOTINFO_PHYS
    xor eax, eax
    mov ecx, BOOTINFO_SIZE / 4
    rep stosd

    mov dword [BOOTINFO_PHYS], BOOTINFO_MAGIC
    mov word [BOOTINFO_PHYS + 4], BOOTINFO_VERSION
    mov word [BOOTINFO_PHYS + 6], BOOTINFO_SIZE
    mov eax, [kernel_load_phys]
    mov dword [BOOTINFO_PHYS + 8], eax
    mov dword [BOOTINFO_PHYS + 12], 0
    mov eax, [kernel_bytes_runtime]
    mov dword [BOOTINFO_PHYS + 16], eax
    mov dword [BOOTINFO_PHYS + 20], 0
    mov eax, [kernel_entry]
    mov dword [BOOTINFO_PHYS + 24], eax
    mov dword [BOOTINFO_PHYS + 28], 0
    mov dword [BOOTINFO_PHYS + 32], MANIFEST_PHYS
    mov dword [BOOTINFO_PHYS + 36], 0
    mov eax, dword [MANIFEST_PHYS + MANIFEST_KERNEL_CRC32]
    mov dword [BOOTINFO_PHYS + 40], eax

    ; Enter long mode.
    mov eax, cr4
    or eax, 1 << 5             ; PAE
    mov cr4, eax

    mov ecx, 0xC0000080        ; EFER
    rdmsr
    or eax, 1 << 8             ; LME
    wrmsr

    mov eax, PML4_PHYS
    mov cr3, eax
    mov eax, cr0
    or eax, (1 << 31) | 1      ; PG | PE
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

    ; Boot ABI: RDI = struct skos_bootinfo *.
    mov edi, BOOTINFO_PHYS
    mov eax, dword [kernel_entry]
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
kernel_sectors_remaining dd 0
kernel_bytes_runtime     dd 0
kernel_load_phys          dd 0
kernel_entry              dd 0
kernel_end_phys           dd 0
identity_page_count       dd 0
boot_drive                db 0

msg_disk db 'SkOS: kernel disk read error', 0
msg_manifest db 'SkOS: invalid boot manifest', 0
msg_no_kernel db 'SkOS: kernel not present', 0
msg_kernel_large db 'SkOS: kernel too large', 0
msg_layout db 'SkOS: invalid kernel layout', 0
msg_checksum db 'SkOS: kernel checksum error', 0

print_error_rm:
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov ah, 0x07
.print:
    lodsb
    test al, al
    jz .halt
    stosw
    jmp .print
.halt:
    cli
    hlt
    jmp .halt

manifest_error_rm:
    mov si, msg_manifest
    jmp print_error_rm
kernel_missing_rm:
    mov si, msg_no_kernel
    jmp print_error_rm
kernel_too_large_rm:
    mov si, msg_kernel_large
    jmp print_error_rm
invalid_layout_rm:
    mov si, msg_layout
    jmp print_error_rm
disk_error_rm:
    mov si, msg_disk
    jmp print_error_rm

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
invalid_layout:
    mov esi, msg_layout
    jmp print_error
checksum_error:
    mov esi, msg_checksum
    jmp print_error
disk_error:
    mov esi, msg_disk
    jmp print_error

bits 16
align 8
gdt32:
    dq 0x0000000000000000
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
gdt32_end:
gdt32_descriptor:
    dw gdt32_end - gdt32 - 1
    dd gdt32

align 8
gdt64:
    dq 0x0000000000000000
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
    dq 0x00AF9A000000FFFF
    dq 0x00CF92000000FFFF
gdt64_end:
gdt64_descriptor:
    dw gdt64_end - gdt64 - 1
    dd gdt64

align 8
kernel_dap:
    db 0x10
    db 0
    dw 0
    dw KERNEL_STAGING_PHYS & 0x000F
    dw KERNEL_STAGING_PHYS >> 4
    dq 0
