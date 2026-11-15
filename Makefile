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

.PHONY: all build bundle install uninstall run test clean warm doctor icon coreml release

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

# A zip for the GitHub release page. Signed ad-hoc, never with a local
# certificate: nobody else has yours, and the zip must not depend on this keychain.
# Ad-hoc is not notarized, so macOS asks the downloader to approve it once; the
# README says how. `ditto` keeps the bundle intact where `zip` can break it.
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
ARCH    := $(shell uname -m)
ZIP     := build/Rawi-$(VERSION)-$(ARCH).zip

release:
	$(MAKE) bundle SIGN_IDENTITY=-
	codesign --verify --strict $(APP)
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	@shasum -a 256 $(ZIP) | tee $(ZIP).sha256
	@echo "Built $(ZIP)"

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

# The encoder is the whole cost of a dictation: whisper pads every recording to
# a thirty-second window and encodes all of it, whichever few seconds you
# actually spoke. On this M4 that is 1200ms on the GPU and 513ms on the Neural
# Engine. Homebrew's whisper.cpp is built with COREML=0, so the Neural Engine is
# not an option until you build it yourself -- which is all this target does.
#
# Costs: ~1.2GB for the encoder, a few minutes to build, and one slow first
# launch while macOS compiles the model for the Neural Engine. That compile is
# cached; every launch after it is normal. Rawi stands the command line in while
# it waits and swaps back on its own once the server answers.
COREML_DIR   := $(HOME)/Library/Application Support/Rawi/whisper-coreml
MODELS_DIR   := $(HOME)/Library/Application Support/Rawi/models
WHISPER_TAG  ?= v1.9.2
COREML_MODEL ?= large-v3-turbo

coreml:
	@command -v cmake >/dev/null || { echo "cmake is needed: brew install cmake"; exit 1; }
	@xcrun --find coremlc >/dev/null 2>&1 || { echo "Xcode is needed to compile the Core ML model"; exit 1; }
	@mkdir -p build/whisper-coreml "$(MODELS_DIR)"
	@test -d build/whisper-coreml/src || \
		git clone --depth 1 --branch $(WHISPER_TAG) https://github.com/ggml-org/whisper.cpp.git build/whisper-coreml/src
	@echo "Building whisper.cpp $(WHISPER_TAG) with Core ML..."
	@# ALLOW_FALLBACK matters: without it a missing or mismatched encoder is
	@# fatal rather than quietly going back to the GPU.
	cmake -S build/whisper-coreml/src -B build/whisper-coreml/build \
		-DCMAKE_BUILD_TYPE=Release -DWHISPER_COREML=1 -DWHISPER_COREML_ALLOW_FALLBACK=1 >/dev/null
	cmake --build build/whisper-coreml/build --config Release -j >/dev/null
	rm -rf "$(COREML_DIR)"
	cmake --install build/whisper-coreml/build --prefix "$(COREML_DIR)" >/dev/null
	@# cmake installs the dylibs but bakes no rpath into the binaries, so they
	@# cannot find them; the ad-hoc signature has to be reapplied after editing.
	@for b in whisper-server whisper-cli; do \
		install_name_tool -add_rpath "@loader_path/../lib" "$(COREML_DIR)/bin/$$b" 2>/dev/null; \
		codesign -f -s - "$(COREML_DIR)/bin/$$b" 2>/dev/null; \
	done
	@# whisper.cpp looks for the encoder beside the model, with ".bin" replaced
	@# by "-encoder.mlmodelc" and any "-qX_X" suffix stripped -- so one encoder
	@# serves every quantisation of the same model.
	@test -d "$(MODELS_DIR)/ggml-$(COREML_MODEL)-encoder.mlmodelc" || { \
		echo "Fetching the Core ML encoder for $(COREML_MODEL) (~1.2GB)..."; \
		curl -fL --progress-bar -o build/whisper-coreml/encoder.zip \
			"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$(COREML_MODEL)-encoder.mlmodelc.zip" && \
		unzip -q -o build/whisper-coreml/encoder.zip -d "$(MODELS_DIR)" && \
		rm -f build/whisper-coreml/encoder.zip; }
	@"$(COREML_DIR)/bin/whisper-cli" --help >/dev/null 2>&1 || { echo "the built binary will not run"; exit 1; }
	@echo
	@echo "Built. Point Rawi at it in ~/.config/rawi/config.json:"
	@echo '  "serverBinary": "$(COREML_DIR)/bin/whisper-server",'
	@echo '  "binary":       "$(COREML_DIR)/bin/whisper-cli"'
	@echo
	@echo "Then restart Rawi. The first launch is slow while the Neural Engine"
	@echo "model compiles; it is cached after that."
