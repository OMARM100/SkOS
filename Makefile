NASM ?= nasm
QEMU ?= qemu-system-x86_64

BUILD_DIR := build/bios
IMAGE := $(BUILD_DIR)/skos-bios.img
BOOT16 := $(BUILD_DIR)/boot16.bin
BOOT32 := $(BUILD_DIR)/boot32.bin
IMAGE_SECTORS := 33

.PHONY: all bios run clean

all: bios

bios: $(IMAGE)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BOOT16): boot/bios/boot16.asm | $(BUILD_DIR)
	$(NASM) -f bin $< -o $@
	test "$$(stat -c%s $@)" -eq 512

$(BOOT32): boot/bios/boot32.asm | $(BUILD_DIR)
	$(NASM) -f bin $< -o $@
	test "$$(stat -c%s $@)" -eq 16384

$(IMAGE): $(BOOT16) $(BOOT32) | $(BUILD_DIR)
	dd if=/dev/zero of=$@ bs=512 count=$(IMAGE_SECTORS) status=none
	dd if=$(BOOT16) of=$@ bs=512 seek=0 conv=notrunc status=none
	dd if=$(BOOT32) of=$@ bs=512 seek=1 conv=notrunc status=none

run: $(IMAGE)
	$(QEMU) -drive format=raw,file=$(IMAGE)

clean:
	rm -rf $(BUILD_DIR)
