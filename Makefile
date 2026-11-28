JOBS ?= 8
POWERSHELL ?= powershell.exe
GODOT_EXE ?=

BUILD_SCRIPT = $(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File tools/build_release.ps1 -Jobs $(JOBS)
GODOT_ARG = $(if $(strip $(GODOT_EXE)),-GodotExe "$(GODOT_EXE)")

.PHONY: build release
build:
	$(BUILD_SCRIPT) -BuildOnly

release:
	$(BUILD_SCRIPT) $(GODOT_ARG)
