PYTHON ?= python3

.PHONY: all build run clean info

all: build

build:
	$(PYTHON) tools/build.py build

run:
	$(PYTHON) tools/build.py run

clean:
	$(PYTHON) tools/build.py clean

info:
	$(PYTHON) tools/build.py info
