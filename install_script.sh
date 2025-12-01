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

# Install Kitty
print_header "⬇️ Installing Kitty"
print_and_execute brew install --cask kitty

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

# Install AltTab
print_header "⬇️ Installing AltTab"
print_and_execute brew install --cask alt-tab

# Install HiddenBar
print_header "⬇️ Installing HiddenBar"
print_and_execute brew install --cask hiddenbar

# Install Secretive
print_header "⬇️ Installing Secretive"
print_and_execute brew install secretive


# Install tree
print_header "⬇️ Installing tree"
unalias tree # tree is set to lsd by default, so we need to unalias
print_and_execute brew install tree
echo "alias tree='/opt/homebrew/bin/tree'" >> ~/.zshrc
source ~/.zshrc

# Install uv
print_header "⬇️ Installing uv"
print_and_execute curl -LsSf https://astral.sh/uv/install.sh | sh

# Install ffmpeg
print_header "⬇️ Installing ffmpeg"
print_and_execute brew install ffmpeg
# Install yt-dlp
print_header "⬇️ Installing yt-dlp"
print_and_execute brew install yt-dlp




print_header "✅✅✅ Installation Complete! ✅✅✅"
echo -e "${BOLD_GREEN}Please restart your terminal or run 'source ~/.zshrc' to apply changes${RESET}"
echo -e "${BOLD_YELLOW}Note: You may need to manually open Slack from your Applications folder${RESET}"
