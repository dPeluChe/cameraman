.PHONY: help build build-arm dmg release verify clean clean-build clean-dist open-dist

XCODE_PROJECT := CameramanApp/CameramanApp.xcodeproj
SCHEME        := CameramanApp
CONFIG        := Release
DERIVED       := CameramanApp/build
APP_BIN       := $(DERIVED)/Build/Products/$(CONFIG)/CameramanApp.app/Contents/MacOS/CameramanApp

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

build: ## Universal Release build (arm64 + x86_64) for distribution
	xcodebuild -project $(XCODE_PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination 'generic/platform=macOS' -derivedDataPath $(DERIVED) ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" clean build

build-arm: ## Native arm64-only Release build (faster, dev only)
	xcodebuild -project $(XCODE_PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' -derivedDataPath $(DERIVED) clean build

verify: ## Confirm the built binary is universal
	@archs="$$(lipo -archs $(APP_BIN))"; \
	if echo "$$archs" | grep -q arm64 && echo "$$archs" | grep -q x86_64; then \
	  echo "✅ Universal binary: $$archs"; \
	else \
	  echo "❌ Not a universal binary: $$archs"; exit 1; \
	fi

dmg: ## Package the existing Release build into a .dmg
	./scripts/build-dmg.sh

release: build verify dmg ## Universal build + verify + DMG (full beta pipeline)

clean: clean-build clean-dist ## Remove build and dist artifacts

clean-build: ## Remove Xcode derived data
	rm -rf $(DERIVED)

clean-dist: ## Remove generated DMGs and staging
	rm -rf dist

open-dist: ## Open the dist/ folder in Finder
	open dist
