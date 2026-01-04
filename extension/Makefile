# CrankScribe Microphone Extension Makefile
#
# Builds the C extension for mic capture

# Playdate SDK path - can be overridden by environment variable
SDK ?= $(PLAYDATE_SDK_PATH)
ifeq ($(SDK),)
$(error PLAYDATE_SDK_PATH not set. Please set it to your Playdate SDK directory)
endif

# Extension name
PRODUCT = mic_capture

# Source files
SRC = mic_capture.c

# Include the Playdate extension build rules
include $(SDK)/C_API/buildsupport/common.mk

# Clean build artifacts
.PHONY: clean
clean:
	rm -rf build/
	rm -f $(PRODUCT).pdx
