LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
INSTALL_DIR = $(HOME)/Applications

.PHONY: build test install logs uninstall clean

build:
	scripts/bundle.sh

test:
	swift test

# Copy to ~/Applications, register with Launch Services, and (re)launch.
install: build
	-pkill -x Linkroute
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/Linkroute.app"
	cp -R build/Linkroute.app "$(INSTALL_DIR)/"
	# Only the installed copy should be registered as a browser, not the build output.
	-$(LSREGISTER) -u build/Linkroute.app
	$(LSREGISTER) -f "$(INSTALL_DIR)/Linkroute.app"
	open "$(INSTALL_DIR)/Linkroute.app"

# Stream routing decisions (handy with: defaults write com.webbontheweb.Linkroute dryRun -bool YES)
logs:
	log stream --level info --predicate 'subsystem == "com.webbontheweb.Linkroute"'

# Turn off "Open at Login" in the menu first; macOS keeps that item until the app removes it.
uninstall:
	-pkill -x Linkroute
	-$(LSREGISTER) -u "$(INSTALL_DIR)/Linkroute.app"
	rm -rf "$(INSTALL_DIR)/Linkroute.app"

clean:
	rm -rf .build build
