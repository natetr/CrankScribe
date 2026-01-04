# CrankScribe Makefile
# Build orchestration for Playdate app with C extension

# Playdate SDK path
SDK ?= $(PLAYDATE_SDK_PATH)
ifeq ($(SDK),)
$(error PLAYDATE_SDK_PATH not set. Please set it to your Playdate SDK directory)
endif

# Product name
PRODUCT = CrankScribe

# Source directory
SRC_DIR = Source

# Build output
PDX = $(PRODUCT).pdx

# Playdate compiler
PDC = $(SDK)/bin/pdc

# Default target
.PHONY: all
all: extension $(PDX)

# Build C extension
.PHONY: extension
extension:
	@echo "Building C extension..."
	$(MAKE) -C extension

# Build PDX bundle
$(PDX): $(SRC_DIR)/main.lua $(SRC_DIR)/pdxinfo
	@echo "Building Playdate bundle..."
	$(PDC) $(SRC_DIR) $(PDX)

# Copy extension library to PDX (if needed)
.PHONY: bundle
bundle: extension $(PDX)
	@echo "Bundling extension with PDX..."
	@if [ -f extension/mic_capture.pdx ]; then \
		cp -r extension/mic_capture.pdx/* $(PDX)/; \
	fi

# Run in Playdate Simulator
.PHONY: run
run: all
	@echo "Opening in Playdate Simulator..."
	open $(PDX)

# Run simulator directly
.PHONY: simulator
simulator: all
	@echo "Launching Playdate Simulator..."
	open -a "Playdate Simulator" $(PDX)

# Sideload to connected Playdate device
.PHONY: device
device: all
	@echo "Sideloading to Playdate..."
	$(SDK)/bin/pdutil install $(PDX)

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(PDX)
	$(MAKE) -C extension clean

# Watch for changes and rebuild (requires fswatch)
.PHONY: watch
watch:
	@echo "Watching for changes..."
	fswatch -o $(SRC_DIR) | xargs -n1 -I{} make all

# Show help
.PHONY: help
help:
	@echo "CrankScribe Build System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all        Build extension and PDX bundle (default)"
	@echo "  extension  Build only the C extension"
	@echo "  run        Build and open in Playdate Simulator"
	@echo "  simulator  Build and launch Playdate Simulator"
	@echo "  device     Build and sideload to connected Playdate"
	@echo "  clean      Remove build artifacts"
	@echo "  watch      Watch for changes and auto-rebuild"
	@echo "  help       Show this help message"
	@echo ""
	@echo "Requirements:"
	@echo "  - PLAYDATE_SDK_PATH must be set to your Playdate SDK directory"
	@echo "  - Xcode Command Line Tools for C extension compilation"
