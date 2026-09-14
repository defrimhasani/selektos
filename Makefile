SHELL := /bin/bash

VERSION ?= $(shell tr -d '[:space:]' < VERSION)
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
ARCHS ?= $(shell uname -m)

.PHONY: icon app dist dist-universal notarize

icon:
	swift Scripts/generate-icon.swift

app: icon
	VERSION="$(VERSION)" BUILD_NUMBER="$(BUILD_NUMBER)" ARCHS="$(ARCHS)" CREATE_ARCHIVES=0 Scripts/package-macos.sh

dist: icon
	VERSION="$(VERSION)" BUILD_NUMBER="$(BUILD_NUMBER)" ARCHS="$(ARCHS)" CREATE_ARCHIVES=1 Scripts/package-macos.sh

dist-universal:
	$(MAKE) dist ARCHS="arm64 x86_64"

notarize:
	VERSION="$(VERSION)" NOTARY_PROFILE="$(NOTARY_PROFILE)" Scripts/notarize-macos.sh
