#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# macOS counterpart of apt_install_no_gui_noble.sh
# Safe to re-run. Uses Homebrew, SDKMAN, nvm, rustup.
#
# Matches what was installed on the Apple Silicon Mac (install-apps-osx):
#   Java/Maven/Gradle -> SDKMAN Temurin 21 (not brew openjdk, no Java 17)
#   Node              -> nvm LTS (not brew node)
#   Docker            -> Docker Desktop cask (not brew docker / colima)
#   Rust              -> rustup in ~/.cargo (not brew rust)
#   gocryptfs         -> go install into ~/go/bin (brew formula needs Linux libfuse)
#   flyctl            -> official installer into ~/.fly
#   kubectl           -> brew kubernetes-cli
#
# Shell config is separate: settings/osx/home/create_links
# Deferred until needed: azure-cli, psql/mysql/redis/mongosh, temporal, opencode
# Linux-only (skipped): acpi, brightnessctl, gparted, xsensors, pavucontrol,
#   nvme-cli, encfs, pcscd, openssh-server, gthumb, archivemount, flatpak,
#   podman, fish, yarnpkg, gcc/build-essential, playwright deps, openjdk apt.

if [ "$(uname -s)" != Darwin ]; then
    echo "This script is for macOS. On Linux use apt_install_no_gui_noble.sh"
    exit 1
fi

failed=()
warn=()

################################################################################
# Helpers

load_brew() {
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    else
        return 1
    fi
}

install_formulae() {
    if [ "$#" -eq 0 ]; then
        return 0
    fi
    echo -e "\n==> brew install --formula $*\n"
    if brew install --formula "$@"; then
        return 0
    fi
    echo "Batch install had errors; retrying one by one"
    local p
    for p in "$@"; do
        brew install --formula "$p" || failed+=("$p")
    done
}

# docker-desktop and macfuse often need a sudo password; do not abort the rest.
install_cask() {
    local p
    for p in "$@"; do
        echo -e "\n==> brew install --cask ${p}\n"
        if brew install --cask "$p"; then
            continue
        fi
        case "$p" in
            docker-desktop|macfuse)
                echo "WARN cask ${p}: often needs sudo. Re-run: brew install --cask ${p}"
                warn+=("cask:${p}")
                ;;
            *)
                echo "FAILED cask: ${p}"
                failed+=("cask:${p}")
                ;;
        esac
    done
}

################################################################################
# Xcode Command Line Tools (brew + compilers)

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are missing. Starting the installer..."
    xcode-select --install
    echo "Re-run $0 after the CLT install finishes."
    exit 1
fi

################################################################################
# Homebrew

if ! load_brew; then
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if ! load_brew; then
        echo "Homebrew is not on PATH after install"
        exit 1
    fi
fi

export HOMEBREW_NO_ENV_HINTS=1
brew update
export HOMEBREW_NO_AUTO_UPDATE=1

# Bash 5: SDKMAN no longer runs on macOS /bin/bash 3.2
install_formulae bash

################################################################################
# Taps

brew tap hashicorp/tap

################################################################################
# CLI packages (Homebrew names for the noble apt list + OSX extras:
# eza, bat, helm, terraform, aws-vault, ykman, fd, rga, pnpm, bun, ...)

install_formulae \
    ca-certificates dos2unix git wget aria2 pigz moreutils autossh gnupg pinentry-mac

install_formulae \
    coreutils gnu-sed findutils grep gnu-tar diffutils watch tree

# ncdu    -> CLI disk usage analyzer
# p7zip   -> 7z archiver used by 7z*.sh
# git-gui -> basic Git GUI (git gui / gitk)
install_formulae \
    fd ripgrep eza bat fzf yq jq tmux htop midnight-commander ncdu vim git-gui \
    git-lfs pv progress p7zip lrzip zip aspell keychain universal-ctags \
    shellcheck fdupes gh

# neovim   -> chosen for the interactive TUI diff and left-to-right merge
#             (nvim -d, :diffget //2 //3) instead of a GUI merge tool
# ente-cli -> CLI part of Ente Auth (2FA): export and decrypt the vault;
#             the GUI app is the ente-auth cask in brew_install_all_goodies.sh
install_formulae neovim ente-cli

install_formulae \
    nmap socat sshpass opensc swig ykman aws-vault

install_formulae \
    ffmpeg imagemagick poppler exiftool tesseract tesseract-lang ripgrep-all rclone

install_formulae \
    cmake ninja pkgconf autoconf automake libtool sqlite

install_formulae \
    pyenv uv pipx go rbenv ruby-build pnpm bun

install_formulae \
    kubernetes-cli helm awscli hashicorp/tap/terraform nvm

################################################################################
# Casks (gcloud is a cask; Docker Desktop and macFUSE may prompt for sudo)
#
# macfuse -> FUSE file system driver / kernel extension; needed by the
#            gocryptfs_*.sh and mount_*.sh mounts. After install macOS may ask
#            to allow the kernel extension in System Settings > Privacy.

install_cask gcloud-cli docker-desktop macfuse

################################################################################
# Git LFS hooks

if command -v git >/dev/null 2>&1; then
    git lfs install --skip-repo || failed+=("git-lfs-install")
fi

################################################################################
# SDKMAN — Java 21 Temurin, Maven, Gradle (no Java 17)

BREW_BASH="$(brew --prefix)/bin/bash"
if [ ! -x "${BREW_BASH}" ]; then
    echo "Homebrew bash missing at ${BREW_BASH}"
    failed+=("bash")
else
    export SDKMAN_DIR="${HOME}/.sdkman"
    if [ ! -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]; then
        echo "Installing SDKMAN..."
        curl -s "https://get.sdkman.io?rcupdate=false" | "${BREW_BASH}" \
            || failed+=("sdkman")
    fi

    if [ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]; then
        if [ -f "${SDKMAN_DIR}/etc/config" ]; then
            sed -i '' 's/sdkman_auto_answer=false/sdkman_auto_answer=true/' \
                "${SDKMAN_DIR}/etc/config"
        fi

        sdk_run() {
            "${BREW_BASH}" -c "
                export SDKMAN_DIR=\"${HOME}/.sdkman\"
                source \"${SDKMAN_DIR}/bin/sdkman-init.sh\"
                $*
            "
        }

        java21_tem=""
        for d in "${SDKMAN_DIR}/candidates/java"/21*-tem; do
            [ -d "$d" ] && java21_tem=$d && break
        done
        if [ -z "${java21_tem}" ]; then
            sdk_run 'sdk install java 21-tem' || failed+=("sdk:java")
        fi
        if [ ! -e "${SDKMAN_DIR}/candidates/maven/current" ]; then
            sdk_run 'sdk install maven' || failed+=("sdk:maven")
        fi
        if [ ! -e "${SDKMAN_DIR}/candidates/gradle/current" ]; then
            sdk_run 'sdk install gradle' || failed+=("sdk:gradle")
        fi
    fi
fi

################################################################################
# nvm — Node LTS (multiple versions; do not also brew install node)

export NVM_DIR="${HOME}/.nvm"
mkdir -p "${NVM_DIR}"
NVM_SH="$(brew --prefix nvm)/nvm.sh"
if [ -s "${NVM_SH}" ]; then
    # shellcheck disable=SC1090
    . "${NVM_SH}"
    current="$(nvm current 2>/dev/null || true)"
    if [ -z "${current}" ] || [ "${current}" = none ]; then
        nvm install --lts || failed+=("nvm-node")
        nvm alias default 'lts/*' || true
    fi
    if command -v corepack >/dev/null 2>&1; then
        corepack enable || true
    fi
else
    failed+=("nvm.sh")
fi

################################################################################
# gocryptfs — brew formula depends on Linux libfuse; build with Go

export GOPATH="${HOME}/go"
export GOBIN="${HOME}/go/bin"
export PATH="${GOBIN}:${PATH}"
mkdir -p "${GOBIN}"
if ! command -v gocryptfs >/dev/null 2>&1; then
    if command -v go >/dev/null 2>&1; then
        echo "Installing gocryptfs with go install..."
        go install github.com/rfjakob/gocryptfs/v2@latest || failed+=("gocryptfs")
    else
        failed+=("gocryptfs")
    fi
fi

################################################################################
# rustup — ~/.cargo is already on PATH in zshenv

if [ ! -x "${HOME}/.cargo/bin/rustc" ]; then
    echo "Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --no-modify-path || failed+=("rustup")
fi

################################################################################
# flyctl — ~/.fly/bin is already on PATH in zshrc

if [ ! -x "${HOME}/.fly/bin/flyctl" ]; then
    echo "Installing flyctl..."
    export FLYCTL_INSTALL="${HOME}/.fly"
    curl -fsSL https://fly.io/install.sh | sh -s -- --non-interactive \
        || failed+=("flyctl")
fi

################################################################################
# pyenv — 3.12 (same series as the Mac bootstrap)

export PYENV_ROOT="${HOME}/.pyenv"
export PATH="${PYENV_ROOT}/shims:${PYENV_ROOT}/bin:${PATH}"
if command -v pyenv >/dev/null 2>&1; then
    if ! pyenv versions --bare 2>/dev/null | grep -q '^3\.12'; then
        echo "Installing Python 3.12 with pyenv..."
        pyenv install 3.12 || failed+=("pyenv:3.12")
        pyenv global 3.12 || true
    fi
fi

################################################################################
# Python CLI apps -> pipx (isolated venvs). ykman is brew, not pipx.

export PATH="${HOME}/.local/bin:${PATH}"
if command -v pipx >/dev/null 2>&1; then
    pipx_installed="$(pipx list --short 2>/dev/null | awk '{print $1}')"
    if ! echo "${pipx_installed}" | grep -qx rbtools; then
        pipx install rbtools || failed+=("pipx:rbtools")
    fi
    if ! echo "${pipx_installed}" | grep -qx glacier-cli; then
        pipx install git+https://github.com/basak/glacier-cli.git || failed+=("pipx:glacier-cli")
    fi
else
    failed+=("pipx")
fi

################################################################################
# macos_input_source — zshprompt switches the keyboard back to U.S.

echo -e "\n==> clang macos_input_source\n"
if clang -Os -framework Carbon -o "${DIR}/macos_input_source" \
    "${DIR}/macos_input_source.c"; then
    chmod +x "${DIR}/macos_input_source"
else
    failed+=("macos_input_source")
fi

################################################################################
# Summary

echo -e "\n################################################################################"
echo "# Done"
echo "################################################################################"
echo "brew:    $(command -v brew)  ($(brew --prefix))"
echo "git:     $(git --version 2>/dev/null | head -1)"
echo "java:    $(command -v java 2>/dev/null || echo missing)  (SDKMAN after a new shell)"
echo "mvn:     $(command -v mvn 2>/dev/null || echo missing)"
echo "node:    $(command -v node >/dev/null 2>&1 && node -v || echo missing)"
echo "kubectl: $(command -v kubectl 2>/dev/null || echo missing)"
echo
echo "Open a new terminal so SDKMAN / nvm / brew PATH apply."
echo "Shell rc files:  cd ${DIR}/settings/osx/home && source create_links"
echo "Docker Desktop:  open -a Docker   # then: docker version"
echo "gcloud:          gcloud init"
echo "macFUSE:         System Settings → Privacy & Security if it asks for a kernel extension"

if [ "${#warn[@]}" -gt 0 ]; then
    echo
    echo "Need sudo / retry:"
    printf '  %s\n' "${warn[@]}"
fi

if [ "${#failed[@]}" -gt 0 ]; then
    echo
    echo "Failed:"
    printf '  %s\n' "${failed[@]}"
    exit 1
fi
