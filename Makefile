APP := SlimBattery.app

.PHONY: app install clean

## Build a release .app bundle, ad-hoc signed.
app:
	swift build -c release --product SlimBattery
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp "$$(swift build -c release --show-bin-path)/SlimBattery" $(APP)/Contents/MacOS/SlimBattery
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

## Copy the bundle to /Applications.
install: app
	rm -rf /Applications/$(APP)
	cp -R $(APP) /Applications/

clean:
	rm -rf $(APP) .build
