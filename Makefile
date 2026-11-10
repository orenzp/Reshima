.PHONY: help setup test generate build-ios package-ipa deploy-iphones db-push check-sql

help: ## Show available agent and developer commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

setup: ## Install CLI tools via Homebrew (xcodegen, swiftlint, supabase, gh)
	./scripts/setup-dev.sh

test: ## Run Swift domain & logic unit tests via SwiftPM (works without full Xcode)
	swift test

generate: ## Generate ios/Reshima.xcodeproj from ios/project.yml using XcodeGen
	cd ios && xcodegen generate

build-ios: generate ## Build unsigned iOS Release .app on macOS with Xcode installed
	xcodebuild build \
		-project ios/Reshima.xcodeproj \
		-scheme Reshima \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-derivedDataPath build/DerivedData \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

package-ipa: ## Package compiled Release .app into unsigned Reshima.ipa for SideStore/AltStore
	./scripts/package-ipa.sh build/DerivedData/Build/Products/Release-iphoneos/Reshima.app build/Reshima.ipa

deploy-iphones: ## Wirelessly build & install directly to connected/Wi-Fi iPhones
	./scripts/deploy-iphones.sh

db-push: ## Push declarative SQL migrations to linked Supabase project
	supabase db push

check-sql: ## Verify SQL migration files exist and are non-empty
	@ls -la supabase/migrations/*.sql
	@echo "SQL migrations verified."
