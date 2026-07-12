.PHONY: project open clean help

# Generate Xcode project using XcodeGen
# Requires: brew install xcodegen
project:
	xcodegen generate
	@echo "✅ Xcode project generated. Open with 'make open'"

# Open in Xcode
open:
	open VoiceUncloak.xcodeproj

# Build for simulator
build:
	xcodebuild -project VoiceUncloak.xcodeproj \
		-scheme VoiceUncloak \
		-destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
		build

# Clean
clean:
	rm -rf VoiceUncloak.xcodeproj
	rm -rf ~/Library/Developer/Xcode/DerivedData/VoiceUncloak-*

# Install XcodeGen if not installed
setup:
	@if ! which xcodegen > /dev/null 2>&1; then \
		echo "Installing XcodeGen..."; \
		brew install xcodegen; \
	else \
		echo "✅ XcodeGen already installed"; \
	fi

help:
	@echo "Usage:"
	@echo "  make setup    - Install XcodeGen (one time)"
	@echo "  make project  - Generate Xcode project"
	@echo "  make open     - Open project in Xcode"
	@echo "  make build    - Build for simulator"
	@echo "  make clean    - Remove generated files"
