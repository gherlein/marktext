# Makefile for MarkText
# Detects platform and provides prereqs, build, dev, lint, clean targets.

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Detect platform
ifeq ($(UNAME_S),Linux)
  PLATFORM := linux
else ifeq ($(UNAME_S),Darwin)
  PLATFORM := mac
else ifneq (,$(findstring MINGW,$(UNAME_S)))
  PLATFORM := win
else ifneq (,$(findstring MSYS,$(UNAME_S)))
  PLATFORM := win
else
  PLATFORM := unknown
endif

# Node version requirement
NODE_MAJOR_MIN := 18
NODE_MAJOR_MAX := 24

# Detect package manager for Linux
ifeq ($(PLATFORM),linux)
  ifneq (,$(shell which apt-get 2>/dev/null))
    PKG_MGR := apt
  else ifneq (,$(shell which dnf 2>/dev/null))
    PKG_MGR := dnf
  else ifneq (,$(shell which pacman 2>/dev/null))
    PKG_MGR := pacman
  else
    PKG_MGR := unknown
  endif
endif

.PHONY: help prereqs prereqs-node prereqs-system build install uninstall dev lint clean run-tests test

# Version from package.json
VERSION := $(shell node -p "require('./package.json').version" 2>/dev/null || echo "0.0.0")

# Default target: print available targets
help:
	@echo "MarkText build system (detected platform: $(PLATFORM), arch: $(UNAME_M))"
	@echo ""
	@echo "Targets:"
	@echo "  prereqs     - Install all prerequisites (system libs + node deps)"
	@echo "  build       - Build distributable package for this platform"
	@echo "  install     - Install after building (platform-specific)"
	@echo "  uninstall   - Remove installed MarkText"
	@echo "  dev         - Run in development mode"
	@echo "  lint        - Run linter"
	@echo "  test        - Run lint (alias for run-tests)"
	@echo "  run-tests   - Run lint"
	@echo "  clean       - Remove build artifacts"
	@echo ""
	@echo "Sub-targets:"
	@echo "  prereqs-system  - Install system-level dependencies only"
	@echo "  prereqs-node    - Install Node.js dependencies only (npm install)"
	@echo ""
	@echo "Platform: $(PLATFORM)  Arch: $(UNAME_M)"
ifeq ($(PLATFORM),linux)
	@echo "Package manager: $(PKG_MGR)"
endif

# ---- Prerequisites ----

prereqs: prereqs-system prereqs-node

prereqs-system:
	@echo "==> Checking prerequisites for $(PLATFORM)..."
	@# Check for Node.js
	@if ! command -v node >/dev/null 2>&1; then \
		echo "ERROR: Node.js is not installed."; \
		echo ""; \
		echo "Install Node.js $(NODE_MAJOR_MIN)-$(NODE_MAJOR_MAX) via one of:"; \
		echo "  https://nodejs.org/"; \
		echo "  nvm: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"; \
		echo "       nvm install 22"; \
		exit 1; \
	fi
	@# Check Node.js version range
	@NODE_MAJOR=$$(node -e "console.log(process.versions.node.split('.')[0])"); \
	if [ "$$NODE_MAJOR" -lt "$(NODE_MAJOR_MIN)" ] || [ "$$NODE_MAJOR" -gt "$(NODE_MAJOR_MAX)" ]; then \
		echo "WARNING: Node.js v$$NODE_MAJOR detected. Recommended: v$(NODE_MAJOR_MIN)-v$(NODE_MAJOR_MAX)."; \
	else \
		echo "  Node.js v$$(node --version) OK"; \
	fi
	@# Check for npm
	@if ! command -v npm >/dev/null 2>&1; then \
		echo "ERROR: npm is not installed. It should come with Node.js."; \
		exit 1; \
	fi
	@# Check for Python (needed by node-gyp)
	@if ! command -v python3 >/dev/null 2>&1; then \
		echo "WARNING: python3 not found. node-gyp requires Python 3.6+."; \
		echo "  Install Python 3 for your platform."; \
	else \
		echo "  python3 OK"; \
	fi
	@# Check for C++ compiler
	@if ! command -v c++ >/dev/null 2>&1 && ! command -v g++ >/dev/null 2>&1 && ! command -v clang++ >/dev/null 2>&1; then \
		echo "WARNING: No C++ compiler found. Native modules require a C++ toolchain."; \
	else \
		echo "  C++ compiler OK"; \
	fi
ifeq ($(PLATFORM),linux)
	@echo "==> Installing Linux system dependencies..."
  ifeq ($(PKG_MGR),apt)
	-sudo apt-get update
	sudo apt-get install -y libx11-dev libxkbfile-dev libsecret-1-dev libfontconfig-dev rpm build-essential python3
  else ifeq ($(PKG_MGR),dnf)
	sudo dnf install -y libX11-devel libxkbfile-devel libsecret-devel fontconfig-devel rpm-build gcc-c++ python3 make
  else ifeq ($(PKG_MGR),pacman)
	sudo pacman -S --needed libx11 libxkbfile libsecret fontconfig base-devel python rpm-tools
  else
	@echo "WARNING: Unknown package manager. Install these manually:"
	@echo "  libx11-dev libxkbfile-dev libsecret-1-dev libfontconfig-dev"
	@echo "  C++ compiler, python3, make"
  endif
endif
ifeq ($(PLATFORM),mac)
	@echo "==> Checking macOS dependencies..."
	@if ! command -v xcode-select >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then \
		echo "Installing Xcode command line tools..."; \
		xcode-select --install; \
	else \
		echo "  Xcode CLI tools OK"; \
	fi
endif
ifeq ($(PLATFORM),win)
	@echo "==> Windows prerequisites:"
	@echo "  Ensure you have:"
	@echo "  - Visual Studio 2019+ with C++ workload, or run:"
	@echo "    npm install --global windows-build-tools"
	@echo "  - Windows 10 SDK (if on older Windows)"
endif
	@echo "==> System prerequisites complete."

prereqs-node:
	@echo "==> Installing Node.js dependencies..."
	npm install
	@echo "==> Node.js dependencies installed."

# ---- Build ----

build:
ifeq ($(PLATFORM),linux)
	@echo "==> Building MarkText for Linux..."
	npm run build:linux
else ifeq ($(PLATFORM),mac)
	@echo "==> Building MarkText for macOS..."
	npm run build:mac
else ifeq ($(PLATFORM),win)
	@echo "==> Building MarkText for Windows..."
	npm run build:win
else
	@echo "ERROR: Unsupported platform '$(UNAME_S)'. Build manually with:"
	@echo "  npm run build:linux  (or build:mac, build:win)"
	@exit 1
endif
	@echo "==> Build complete. Output is in the build/ directory."

# ---- Install ----

install:
ifeq ($(PLATFORM),linux)
	@# Prefer deb on apt systems, rpm on dnf, AppImage as fallback
  ifeq ($(PKG_MGR),apt)
	@DEB=$$(ls -t dist/marktext-linux-*.deb 2>/dev/null | head -1); \
	if [ -n "$$DEB" ]; then \
		echo "==> Installing $$DEB ..."; \
		sudo dpkg -i "$$DEB"; \
		sudo apt-get install -f -y; \
	else \
		echo "ERROR: No .deb found in dist/. Run 'make build' first."; \
		exit 1; \
	fi
  else ifeq ($(PKG_MGR),dnf)
	@RPM=$$(ls -t dist/marktext-linux-*.rpm 2>/dev/null | head -1); \
	if [ -n "$$RPM" ]; then \
		echo "==> Installing $$RPM ..."; \
		sudo dnf install -y "$$RPM"; \
	else \
		echo "ERROR: No .rpm found in dist/. Run 'make build' first."; \
		exit 1; \
	fi
  else ifeq ($(PKG_MGR),pacman)
	@RPM=$$(ls -t dist/marktext-linux-*.rpm 2>/dev/null | head -1); \
	APPIMAGE=$$(ls -t dist/marktext-linux-*.AppImage 2>/dev/null | head -1); \
	if [ -n "$$APPIMAGE" ]; then \
		echo "==> Installing AppImage to /usr/local/bin/marktext ..."; \
		sudo install -m 755 "$$APPIMAGE" /usr/local/bin/marktext; \
	elif [ -n "$$RPM" ]; then \
		echo "==> Converting and installing $$RPM (requires rua/debtap or manual install)..."; \
		echo "  Alternatively, copy the AppImage: sudo install -m 755 dist/*.AppImage /usr/local/bin/marktext"; \
		exit 1; \
	else \
		echo "ERROR: No AppImage or .rpm found in dist/. Run 'make build' first."; \
		exit 1; \
	fi
  else
	@APPIMAGE=$$(ls -t dist/marktext-linux-*.AppImage 2>/dev/null | head -1); \
	if [ -n "$$APPIMAGE" ]; then \
		echo "==> Installing AppImage to /usr/local/bin/marktext ..."; \
		sudo install -m 755 "$$APPIMAGE" /usr/local/bin/marktext; \
		echo "==> Installing desktop entry..."; \
		sudo install -m 644 build/linux/marktext.desktop /usr/share/applications/marktext.desktop; \
		sudo install -m 644 static/icon.png /usr/share/icons/hicolor/256x256/apps/marktext.png; \
	else \
		echo "ERROR: No AppImage found in dist/. Run 'make build' first."; \
		exit 1; \
	fi
  endif
	@echo "==> MarkText installed. Run 'marktext' to launch."
else ifeq ($(PLATFORM),mac)
	@DMG=$$(ls -t dist/marktext-mac-*.dmg 2>/dev/null | head -1); \
	if [ -n "$$DMG" ]; then \
		echo "==> Mounting $$DMG ..."; \
		MOUNT_DIR=$$(hdiutil attach "$$DMG" -nobrowse | grep '/Volumes/' | awk '{print $$NF}'); \
		echo "==> Copying MarkText.app to /Applications ..."; \
		cp -R "$$MOUNT_DIR/marktext.app" /Applications/ 2>/dev/null || \
		cp -R "$$MOUNT_DIR/MarkText.app" /Applications/ 2>/dev/null || \
		cp -R "$$MOUNT_DIR/"*.app /Applications/; \
		hdiutil detach "$$MOUNT_DIR" -quiet; \
		echo "==> MarkText installed to /Applications."; \
	else \
		echo "ERROR: No .dmg found in dist/. Run 'make build' first."; \
		exit 1; \
	fi
else ifeq ($(PLATFORM),win)
	@SETUP=$$(ls -t dist/marktext-win-*-setup.exe 2>/dev/null | head -1); \
	if [ -n "$$SETUP" ]; then \
		echo "==> Running installer $$SETUP ..."; \
		cmd //c "$$SETUP"; \
	else \
		echo "ERROR: No installer found in dist/. Run 'make build' first."; \
		exit 1; \
	fi
else
	@echo "ERROR: Unsupported platform '$(UNAME_S)'."
	@exit 1
endif

uninstall:
ifeq ($(PLATFORM),linux)
  ifeq ($(PKG_MGR),apt)
	sudo apt-get remove -y marktext || true
  else ifeq ($(PKG_MGR),dnf)
	sudo dnf remove -y marktext || true
  else
	sudo rm -f /usr/local/bin/marktext
	sudo rm -f /usr/share/applications/marktext.desktop
	sudo rm -f /usr/share/icons/hicolor/256x256/apps/marktext.png
  endif
	@echo "==> MarkText uninstalled."
else ifeq ($(PLATFORM),mac)
	rm -rf /Applications/marktext.app /Applications/MarkText.app
	@echo "==> MarkText removed from /Applications."
else ifeq ($(PLATFORM),win)
	@echo "==> Use Windows Settings > Apps to uninstall MarkText."
else
	@echo "ERROR: Unsupported platform."
endif

# ---- Development ----

dev:
	@echo "==> Starting MarkText in dev mode..."
	npm run dev

# ---- Lint / Test ----

lint:
	npm run lint

test: lint

run-tests: lint

# ---- Clean ----

clean:
	@echo "==> Cleaning build artifacts..."
	rm -rf out/
	rm -rf dist/
	rm -rf build/linux build/mac build/windows
	rm -rf build/*.AppImage build/*.deb build/*.rpm build/*.snap
	rm -rf build/*.dmg build/*.zip build/*.pkg
	rm -rf build/*.exe build/*.msi build/*.nsis
	rm -f build/*.blockmap build/*.yml build/*.yaml
	rm -rf node_modules/.cache
	rm -rf .eslintcache
	@echo "==> Clean complete."
	@echo "  (Run 'rm -rf node_modules && npm install' to fully reset dependencies.)"
