# Rawi build. TCC permission grants bind to the code signature, so an
# ad-hoc identity ("-") means re-granting Accessibility and Input Monitoring on
# every rebuild. Create a self-signed certificate once and pass it here to make
# grants persist -- see README "Keeping permissions across rebuilds".
SIGN_IDENTITY ?= -
# ~/Applications needs no sudo, and TCC grants and login items behave identically
# there. Override with INSTALL_DIR=/Applications if you prefer (needs admin).
INSTALL_DIR   ?= $(HOME)/Applications
APP           := build/Rawi.app
INSTALLED     := $(INSTALL_DIR)/Rawi.app
BIN           := .build/release/Rawi

.PHONY: all build bundle install uninstall run test clean warm doctor

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Rawi
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none $(APP)
	@codesign -dv $(APP) 2>&1 | grep -E 'Identifier|Signature' || true
	@echo "Built $(APP)"

install: bundle
	@if pgrep -x Rawi > /dev/null; then \
		echo "Quitting the running instance..."; \
		pkill -x Rawi || true; sleep 1; \
	fi
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALLED)
	cp -R $(APP) $(INSTALL_DIR)/
	@echo ""
	@echo "Installed to $(INSTALLED)"
	@echo "Launch it with:  open $(INSTALLED)"
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
