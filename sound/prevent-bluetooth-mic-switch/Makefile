
# ANSI color codes
GREEN=\033[0;32m
YELLOW=\033[0;33m
RED=\033[0;31m
BLUE=\033[0;34m
RESET=\033[0m

########################################################
# Check dependencies
########################################################

check_switchaudio:
	@echo "$(YELLOW)Checking SwitchAudioSource version...$(RESET)"
	@if ! command -v SwitchAudioSource > /dev/null 2>&1; then \
		echo "$(RED)SwitchAudioSource is not installed. Please install SwitchAudioSource before proceeding.$(RESET)"; \
		exit 1; \
	else \
		SwitchAudioSource --version; \
	fi

########################################################
# Install dependencies
########################################################

install_switchaudio:
	@echo "$(GREEN)Installing SwitchAudioSource...$(RESET)"
	@brew install switchaudio-osx
	@echo "$(GREEN)Installation complete.$(RESET)"

install: install_switchaudio
	@echo "$(GREEN)All dependencies installed.$(RESET)"


########################################################
# Install script
########################################################

all: install
	@echo "$(GREEN)Setting up script to prevent bluetooth mic switch...$(RESET)"
	@chmod +x setup_script.sh
	@./setup_script.sh
	@echo "$(GREEN)Installation complete.$(RESET)"

# @launchctl unload ~/Library/LaunchAgents/com.user.bluetooth-mic-switch.plist
# @launchctl load ~/Library/LaunchAgents/com.user.bluetooth-mic-switch.plist

view:
	@cat ~/.bluetooth_mic_switch_config

########################################################
# Debug
########################################################

debug_script:
	@echo "$(GREEN)Debugging script...$(RESET)"
	@launchctl list | grep com.user.bluetooth-mic-switch
	@echo "$(YELLOW)Output log:$(RESET)"
	@cat /tmp/bluetooth_mic_switch.out
	@echo "$(YELLOW)Error log:$(RESET)"
	@cat /tmp/bluetooth_mic_switch.err
	@echo "$(GREEN)Debugging complete.$(RESET)"
