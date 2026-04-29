export TARGET = iphone:clang:latest:11.0
export ARCHS = arm64

INSTALL_TARGET_PROCESSES = MobileMLBB

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EdgyESP

EdgyESP_FILES = ESPOnly.mm
EdgyESP_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore

DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/tweak.mk
