#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# macOS counterpart of apt_install_all_goodies_*.sh
# CLI stack first, then a short GUI cask list. Safe to re-run.

if [ "$(uname -s)" != Darwin ]; then
    echo "This script is for macOS. On Linux use apt_install_all_goodies.sh"
    exit 1
fi

"${DIR}/brew_install_no_gui.sh" "$@" || exit $?

# no_gui runs in a child shell; pick up Homebrew if this shell does not have it yet
if ! command -v brew >/dev/null 2>&1; then
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

failed=()

casks=( postman calibre thunderbird telegram slack keepassxc jetbrains-toolbox )

for i in "${casks[@]}"; do
    echo -e "\n==> brew install --cask ${i}\n"
    brew install --cask "$i" || failed+=("$i")
done

echo -e "\n################################################################################"
echo "# GUI casks"
echo "################################################################################"
printf '  %s\n' "${casks[@]}"

if [ "${#failed[@]}" -gt 0 ]; then
    echo
    echo "Failed casks:"
    printf '  %s\n' "${failed[@]}"
    exit 1
fi
