; SkOS BIOS boot protocol v1
; Shared manifest offsets. The manifest lives inside the LBA0 boot sector.

%define BOOT_MANIFEST_OFFSET        0x180
%define BOOT_MANIFEST_MAGIC         0x4D424B53 ; little-endian "SKBM"
%define BOOT_MANIFEST_VERSION       1
%define BOOT_MANIFEST_SIZE          80

%define MANIFEST_STAGE2_LBA        0x08
%define MANIFEST_STAGE2_BYTES      0x10
%define MANIFEST_STAGE2_SECTORS    0x18
%define MANIFEST_KERNEL_LBA        0x20
%define MANIFEST_KERNEL_BYTES      0x28
%define MANIFEST_KERNEL_SECTORS    0x30
%define MANIFEST_KERNEL_LOAD       0x38
%define MANIFEST_KERNEL_ENTRY      0x40
%define MANIFEST_KERNEL_CRC32      0x48

%define BOOTINFO_MAGIC              0x534B4249 ; little-endian "SKBI"
%define BOOTINFO_VERSION            1
%define BOOTINFO_SIZE               64
