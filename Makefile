.PHONY: help all build release bundle bundle-release test clean install uninstall run format lint icon notarize

SWIFT_BUILD_FLAGS = --disable-sandbox
APP_INSTALL_PATH = /Applications

help: ## This help screen
	@IFS=$$'\n' ; \
	help_lines=(`fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##/:/'`); \
	printf "%-30s %s\n" "Target" "Function" ; \
	printf "%-30s %s\n" "------" "----" ; \
	for help_line in $${help_lines[@]}; do \
		IFS=$$':' ; \
		help_split=($$help_line) ; \
		help_command=`echo $${help_split[0]} | sed -e 's/^ *//' -e 's/ *$$//'` ; \
		help_info=`echo $${help_split[2]} | sed -e 's/^ *//' -e 's/ *$$//'` ; \
		printf '\033[36m'; \
		printf "%-30s %s" $$help_command ; \
		printf '\033[0m'; \
		printf "%s\n" $$help_info; \
	done

all: ## Default target
all: bundle

build: ## Build debug executable only (no app bundle)
	swift build -c debug $(SWIFT_BUILD_FLAGS)

release: ## Build release executable only (no app bundle)
	swift build -c release $(SWIFT_BUILD_FLAGS)

bundle: ## Build debug app bundle
	./scripts/bundle.sh debug

bundle-release: ## Build release app bundle
	./scripts/bundle.sh release

test: ## Run tests
	swift test $(SWIFT_BUILD_FLAGS)

clean: ## Clean build artifacts
	swift package clean
	rm -rf .build dist

install: ## Install app bundle to /Applications (may require sudo)
install: bundle-release
	@echo "Installing Micspresso.app to $(APP_INSTALL_PATH)..."
	@if [ -w $(APP_INSTALL_PATH) ]; then \
		rm -rf $(APP_INSTALL_PATH)/Micspresso.app; \
		cp -r .build/release/Micspresso.app $(APP_INSTALL_PATH)/; \
	else \
		sudo rm -rf $(APP_INSTALL_PATH)/Micspresso.app; \
		sudo cp -r .build/release/Micspresso.app $(APP_INSTALL_PATH)/; \
	fi
	@echo "Installed! Launch with: open $(APP_INSTALL_PATH)/Micspresso.app"

uninstall: ## Uninstall from /Applications (may require sudo)
	@rm -rf $(APP_INSTALL_PATH)/Micspresso.app 2>/dev/null || \
		sudo rm -rf $(APP_INSTALL_PATH)/Micspresso.app
	@echo "Uninstalled Micspresso"

run: ## Run the debug build (via app bundle)
run: bundle
	.build/debug/Micspresso.app/Contents/MacOS/micspresso

format: ## Format code (requires swift-format)
	swift-format -i -r Sources/ Tests/

lint: ## Lint code (requires swift-format)
	swift-format lint -r Sources/ Tests/

icon: ## Regenerate Resources/AppIcon.icns from icon.svg (requires librsvg)
	./scripts/make-icon.sh

notarize: ## Build, sign, notarize, staple, and archive (needs .env + keychain profile or APPLE_ID env)
	@set -e; \
	if [ -z "$$APPLE_ID" ] || [ -z "$$APPLE_APP_PASSWORD" ] || [ -z "$$TEAM_ID" ]; then \
		PROFILE=$${NOTARY_PROFILE:-micspresso-notarization}; \
		echo "Using keychain profile: $$PROFILE"; \
		./scripts/bundle.sh release; \
		APP_BUNDLE=.build/release/Micspresso.app; \
		ZIP_PATH=.build/release/Micspresso-notary.zip; \
		codesign --verify --deep --strict --verbose=2 "$$APP_BUNDLE"; \
		rm -f "$$ZIP_PATH"; \
		ditto -c -k --keepParent "$$APP_BUNDLE" "$$ZIP_PATH"; \
		xcrun notarytool submit "$$ZIP_PATH" --keychain-profile "$$PROFILE" --wait; \
		xcrun stapler staple "$$APP_BUNDLE"; \
		xcrun stapler validate "$$APP_BUNDLE"; \
		rm -f "$$ZIP_PATH"; \
		echo "Notarized: $$APP_BUNDLE"; \
	else \
		./scripts/release.sh; \
	fi
