# WhisperFlow build. TCC permission grants bind to the code signature, so an
# ad-hoc identity ("-") means re-granting Accessibility and Input Monitoring on
# every rebuild. Create a self-signed certificate once and pass it here to make
# grants persist -- see README "Keeping permissions across rebuilds".
SIGN_IDENTITY ?= -
APP           := build/WhisperFlow.app
BIN           := .build/release/WhisperFlow

.PHONY: all build bundle install uninstall run test clean warm

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/WhisperFlow
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none $(APP)
	@codesign -dv $(APP) 2>&1 | grep -E 'Identifier|Signature' || true
	@echo "Built $(APP)"

install: bundle
	@if pgrep -x WhisperFlow > /dev/null; then \
		echo "Quitting the running instance..."; \
		pkill -x WhisperFlow || true; sleep 1; \
	fi
	rm -rf /Applications/WhisperFlow.app
	cp -R $(APP) /Applications/
	@echo ""
	@echo "Installed to /Applications/WhisperFlow.app"
	@echo "Launch it with:  open -a WhisperFlow"
	@echo "Then grant Input Monitoring and Accessibility -- see README."

uninstall:
	-pkill -x WhisperFlow
	rm -rf /Applications/WhisperFlow.app
	@echo "Removed. Config and models were left in place:"
	@echo "  ~/.config/whisperflow/"
	@echo "  ~/Library/Application Support/WhisperFlow/"

run: bundle
	-pkill -x WhisperFlow
	WF_DEBUG=1 $(APP)/Contents/MacOS/WhisperFlow

test:
	swift test

# whisper.cpp compiles Metal shaders on its first run (~30s). Doing it here means
# the first real dictation is not mistaken for a hang.
warm:
	@echo "Warming the whisper.cpp Metal shader cache (one-time, ~30s)..."
	@whisper-cli --help > /dev/null 2>&1 || true
	@echo "Done."

clean:
	swift package clean
	rm -rf build
