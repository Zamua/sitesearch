XCODEGEN := nix shell nixpkgs\#xcodegen -c xcodegen
BUILD_DIR := $(CURDIR)/.build
APP := $(BUILD_DIR)/Release/SiteSearch.app

.PHONY: help gen build test e2e install run clean

help:
	@echo "gen      generate SiteSearch.xcodeproj from project.yml"
	@echo "build    build Release app into .build/"
	@echo "test     run the unit test suite"
	@echo "e2e      verify every default site pattern against the live site"
	@echo "install  copy the built app to /Applications and launch it once"
	@echo "clean    remove generated project and build products"

test: gen
	xcodebuild -project SiteSearch.xcodeproj -scheme SiteSearch -configuration Debug -derivedDataPath $(BUILD_DIR)/dd test

e2e:
	scripts/e2e-sites.sh

gen:
	$(XCODEGEN) generate

build: gen
	xcodebuild -project SiteSearch.xcodeproj -target SiteSearch -configuration Release SYMROOT=$(BUILD_DIR) build

install: build
	rm -rf /Applications/SiteSearch.app
	ditto "$(APP)" /Applications/SiteSearch.app
	open /Applications/SiteSearch.app

clean:
	rm -rf "$(BUILD_DIR)" SiteSearch.xcodeproj
