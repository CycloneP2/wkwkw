export TARGET = iphone:clang:latest:11.0
export ARCHS = arm64

INSTALL_TARGET_PROCESSES = MobileMLBB

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EdgyESP

EdgyESP_FILES = ESPOnly.mm
EdgyESP_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore

DEBUG = 0
FINALPACKAGE = 1

# Build langsung .dylib tanpa packaging .deb
AFTER_INSTALL = true
_THEOS_INTERNAL_MAKE_PACKAGE = true

include $(THEOS)/makefiles/tweak.mk

# Ekstrak .dylib setelah build
after-package::
	@echo "Extracting .dylib from .deb..."
	@mkdir -p .theos/obj/dylib
	@dpkg-deb -x $(THEOS_STAGING_DIR)/*.deb .theos/obj/dylib/ 2>/dev/null || true
	@cp .theos/obj/dylib/Library/MobileSubstrate/DynamicLibraries/*.dylib . 2>/dev/null || true
	@echo "✅ .dylib available at: ./$(TWEAK_NAME).dylib"
