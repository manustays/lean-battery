APP := LeanBattery.app
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
ZIP := dist/LeanBattery-$(VERSION).zip

.PHONY: app install zip verify clean

## Build a release .app bundle (arm64), ad-hoc signed.
app:
	swift build -c release --arch arm64 --product LeanBattery
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release --arch arm64 --show-bin-path)/LeanBattery" $(APP)/Contents/MacOS/LeanBattery
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	sh scripts/make-icon.sh
	[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns $(APP)/Contents/Resources/ || true
	codesign --force --sign - $(APP)

## Copy the bundle to /Applications.
install: app
	rm -rf /Applications/$(APP)
	cp -R $(APP) /Applications/

## Package the built bundle as the release artifact.
zip: app
	mkdir -p dist
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	@echo "$(ZIP)"

## Check the bundle and zip are publishable.
verify: zip
	sh scripts/verify-release.sh $(VERSION)

clean:
	rm -rf $(APP) dist .build
