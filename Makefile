# ANSI color codes
GREEN=\033[0;32m
YELLOW=\033[0;33m
RED=\033[0;31m
BLUE=\033[0;34m
RESET=\033[0m


########################################################
# Install Applications
########################################################

install:
	@echo "$(YELLOW)⬇️ Installing standard useful applications...$(RESET)"
	chmod +x install_script.sh
  ./install_script.sh
	@echo "$(GREEN)✅Installation of applications completed.$(RESET)"
