# CodeIsland — convenience targets wrapping build.sh and scripts/dev-hot-restart.sh.
#
# Common usage:
#   make            # = make build (release .app bundle, signed)
#   make debug      # swift build (debug, fastest incremental)
#   make run        # quit any running app, then launch the debug binary
#   make restart    # = debug + run
#   make hot        # file-watch loop: rebuild + relaunch on source change
#   make release    # release .app bundle, no notarization
#   make dmg        # release bundle + notarized DMG (needs SIGN_ID / keychain)
#   make clean      # swift package clean + remove .build
#   make test       # swift test
#
# Override vars from the command line, e.g.:
#   make run APP_PATH=/Applications/CodeIsland.app
#   make release SIGN_ID="Developer ID Application: ..."
#
# If Xcode.app is installed, use its toolchain even if xcode-select points at CLT.
ifneq ($(wildcard /Applications/Xcode.app/Contents/Developer),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif

APP_NAME      := CodeIsland
DEBUG_BIN     := .build/debug/$(APP_NAME)
RELEASE_APP   := .build/release/$(APP_NAME).app
# Allow overriding the app path to launch (e.g. /Applications/CodeIsland.app).
APP_PATH      ?= $(DEBUG_BIN)
BUILD_CONFIG  ?= debug

.DEFAULT_GOAL := build

.PHONY: build debug release run restart relaunch hot test clean help

# --- Build -----------------------------------------------------------------

# Default: build the signed release .app bundle (same as ./build.sh).
build:
	./build.sh

# Fastest incremental build — just swift build, no bundling or signing.
debug:
	swift build

# Release .app bundle without notarization.
release:
	./build.sh

# Release .app bundle + notarized DMG. Requires a Developer ID and the
# "CodeIsland" notarytool keychain profile. Pass SIGN_ID to pick the identity.
dmg:
	./build.sh --notarize

# --- Run / Restart ---------------------------------------------------------

# Quit any running CodeIsland process and launch $(APP_PATH).
# Accepts a signed .app bundle OR a bare executable (the latter warns that
# Buddy Bluetooth entitlements won't be available).
run:
	@bin/run-quit-launch.sh "$(APP_PATH)"

# Build debug, then run.
restart: debug run

# Alias matching the dev-hot-restart.sh script's vocabulary.
relaunch: restart

# File-watch loop: rebuild + relaunch on source change.
hot:
	scripts/dev-hot-restart.sh $(HOT_ARGS)

# --- Misc ------------------------------------------------------------------

test:
	swift test

clean:
	swift package clean
	@rm -rf .build

help:
	@printf '%s\n' \
	  'CodeIsland Makefile — common targets:' \
	  '  make            build   (release .app bundle, signed — default)' \
	  '  make debug      swift build (debug, fastest)' \
	  '  make run        quit running app, launch APP_PATH ($(APP_PATH))' \
	  '  make restart    debug + run' \
	  '  make hot        file-watch: rebuild + relaunch on source change' \
	  '  make release    release .app bundle (no notarization)' \
	  '  make dmg        release bundle + notarized DMG (needs SIGN_ID)' \
	  '  make test        swift test' \
	  '  make clean      swift package clean + remove .build' \
	  '' \
	  'Overrides: APP_PATH=<path to launch>  SIGN_ID=<codesign identity>'
