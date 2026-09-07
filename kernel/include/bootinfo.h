#ifndef SKOS_BOOTINFO_H
#define SKOS_BOOTINFO_H

#include <stdint.h>

#define SKOS_BOOTINFO_MAGIC   UINT32_C(0x534B4249)
#define SKOS_BOOTINFO_VERSION UINT16_C(1)

struct skos_bootinfo {
    uint32_t magic;
    uint16_t version;
    uint16_t size;
    uint64_t kernel_load_address;
    uint64_t kernel_size;
    uint64_t kernel_entry;
    uint64_t manifest_address;
    uint32_t kernel_crc32;
    uint32_t reserved;
};

#endif
