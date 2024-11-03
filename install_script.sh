#!/bin/bash

# Color definitions
BOLD_GREEN='\033[1;32m'
BOLD_RED='\033[1;31m'
BOLD_YELLOW='\033[1;33m'
RESET='\033[0m'

# Error handling
set -eo pipefail

# Helper function for command execution and logging
print_and_execute() {
    echo -e "${BOLD_GREEN}+ $@${RESET}" >&2
    "$@"
}

# Helper function for section headers
print_header() {
    echo -e "\n${BOLD_GREEN}=== $1 ===${RESET}\n"
}

# Check if running on MacOS
if [ "$(uname -s)" != "Darwin" ]; then
    echo -e "${BOLD_RED}Error: This script is only for MacOS${RESET}"
    exit 1
fi

# Install Homebrew if not already installed
print_header "🔎 Checking for Homebrew"
if ! command -v brew &> /dev/null; then
    echo "⬇️ Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for Apple Silicon Macs
    if [ -f "/opt/homebrew/bin/brew" ]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    echo "✅ Homebrew already installed"
fi

# Install iTerm2
print_header "⬇️ Installing iTerm2"
print_and_execute brew install --cask iterm2

# Install Oh My Zsh if not already installed
print_header "⬇️ Installing Oh My Zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo "✅ Oh My Zsh already installed"
fi

# Install Slack
print_header "⬇️ Installing Slack"
print_and_execute brew install --cask slack

# Install Rye
print_header "⬇️ Installing Rye"
print_and_execute curl -sSf https://rye.astral.sh/get | bash

# Add Rye to PATH
echo 'source "$HOME/.rye/env"' >> ~/.zshrc

print_header "✅✅✅ Installation Complete! ✅✅✅"
echo -e "${BOLD_GREEN}Please restart your terminal or run 'source ~/.zshrc' to apply changes${RESET}"
echo -e "${BOLD_YELLOW}Note: You may need to manually open iTerm2 and Slack from your Applications folder${RESET}"
