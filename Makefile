# Rawi build. TCC permission grants bind to the code signature, so an
# ad-hoc identity ("-") means re-granting Accessibility and Input Monitoring on
# every rebuild: the grant is pinned to one build's hash. A certificate named
# "Rawi Local Signing" in the login keychain is used automatically when present,
# which pins grants to the certificate instead -- see README "Keeping
# permissions across rebuilds". Without one, the build falls back to ad-hoc.
LOCAL_CERT    := Rawi Local Signing
SIGN_IDENTITY ?= $(shell security find-certificate -c "$(LOCAL_CERT)" >/dev/null 2>&1 && echo "$(LOCAL_CERT)" || echo -)
# ~/Applications needs no sudo, and TCC grants and login items behave identically
# there. Override with INSTALL_DIR=/Applications if you prefer (needs admin).
INSTALL_DIR   ?= $(HOME)/Applications
APP           := build/Rawi.app
INSTALLED     := $(INSTALL_DIR)/Rawi.app
BIN           := .build/release/Rawi

.PHONY: all build bundle install uninstall run test clean warm doctor icon

# The icon on its own, for looking at it without installing.
icon: build
	rm -rf build/Rawi.iconset
	$(BIN) --write-iconset build/Rawi.iconset
	iconutil -c icns build/Rawi.iconset -o build/Rawi.icns
	@echo "Wrote build/Rawi.icns"

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Rawi
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	@# The icon is drawn from the same mark the menu bar uses, so no bitmap
	@# lives in the repository and the two cannot drift apart.
	rm -rf build/Rawi.iconset
	$(BIN) --write-iconset build/Rawi.iconset > /dev/null
	iconutil -c icns build/Rawi.iconset -o $(APP)/Contents/Resources/Rawi.icns
	codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none $(APP)
	@codesign -dv $(APP) 2>&1 | grep -E 'Identifier|Signature' || true
	@codesign -dr - $(APP) 2>&1 | grep designated || true
	@echo "Built $(APP)"

install: bundle
	@if pgrep -x Rawi > /dev/null; then \
		echo "Quitting the running instance..."; \
		pkill -x Rawi || true; sleep 1; \
	fi
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALLED)
	cp -R $(APP) $(INSTALL_DIR)/
	@# A build that traps on launch installs perfectly and then does nothing, and
	@# the app it replaced is already gone. That shipped once: a line wired to the
	@# controller before the controller existed, past a green test suite, because
	@# nothing between `swift test` and a human opening the app ever started it.
	@echo ""
	@echo "Checking it starts..."
	@open $(INSTALLED)
	@sleep 6
	@if pgrep -x Rawi > /dev/null; then \
		echo "Running."; \
	else \
		echo ""; \
		echo "FAILED TO START. The last lines it managed to log:"; \
		tail -5 $(HOME)/Library/Logs/Rawi/rawi.log 2>/dev/null || true; \
		echo ""; \
		echo "Run '.build/debug/Rawi' after 'swift build' for the trap message."; \
		exit 1; \
	fi
	@echo ""
	@echo "Installed to $(INSTALLED)"
	@echo "Check setup with: $(INSTALLED)/Contents/MacOS/Rawi --doctor"
	@echo "Then grant Input Monitoring and Accessibility -- see README section 2."

uninstall:
	-pkill -x Rawi
	rm -rf $(INSTALLED)
	@echo "Removed. Config and models were left in place:"
	@echo "  ~/.config/rawi/"
	@echo "  ~/Library/Application Support/Rawi/"

run: bundle
	-pkill -x Rawi
	WF_DEBUG=1 $(APP)/Contents/MacOS/Rawi

test:
	swift test

doctor: bundle
	@$(APP)/Contents/MacOS/Rawi --doctor

# whisper.cpp compiles Metal shaders on its first run (~30s). Doing it here means
# the first real dictation is not mistaken for a hang.
warm:
	@echo "Warming the whisper.cpp Metal shader cache (one-time, ~30s)..."
	@whisper-cli --help > /dev/null 2>&1 || true
	@echo "Done."

clean:
	swift package clean
	rm -rf build
