PROJECT := CoffeeSync.xcodeproj
SCHEME := CoffeeSync
DERIVED_DATA := $(CURDIR)/build/DerivedData
VERSION ?= 1.0.0

.PHONY: build test package clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'platform=macOS' -derivedDataPath "$(DERIVED_DATA)" \
		build CODE_SIGNING_ALLOWED=NO

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' -derivedDataPath "$(DERIVED_DATA)" \
		test CODE_SIGNING_ALLOWED=NO

package:
	VERSION=$(VERSION) scripts/package-dmg.sh

clean:
	rm -rf build dist
