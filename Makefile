.PHONY: all dev reset-defaults test clean

all: dev

dev:
	@echo "Stopping running Loom processes..."
	@killall Loom LoomWidget 2>/dev/null || true
	@echo "Building Loom (Debug)..."
	@xcodebuild -scheme Loom -configuration Debug -derivedDataPath .build/DerivedData build
	@echo "Launching Loom.app..."
	@open .build/DerivedData/Build/Products/Debug/Loom.app

reset-defaults:
	@echo "Clearing migration and provider settings..."
	@killall Loom LoomWidget 2>/dev/null || true
	@defaults delete com.chaiwithcode.loom com.loom.didMigrateT3CodeProvider_v1 2>/dev/null || true
	@defaults delete com.chaiwithcode.loom enabledProviderIDs 2>/dev/null || true
	@defaults delete com.loom com.loom.didMigrateT3CodeProvider_v1 2>/dev/null || true
	@defaults delete com.loom enabledProviderIDs 2>/dev/null || true
	@$(MAKE) dev

test:
	@echo "Running SPM test suite..."
	@swift test
	@echo "Building Xcode macOS scheme..."
	@xcodebuild -scheme Loom -destination 'platform=macOS' build

clean:
	@echo "Cleaning DerivedData..."
	@rm -rf .build/DerivedData
	@swift package clean
