#!/usr/bin/env bash
#
# fastfetch-config — one-shot installer for macOS and Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/daniloscimone/fastfetch-config/main/install.sh | bash
#
# Installs fastfetch, a Nerd Font, and this repository's config.jsonc.
# Any existing config is backed up, never overwritten silently.

set -euo pipefail

REPO_SLUG="daniloscimone/fastfetch-config"
RAW_BASE="https://raw.githubusercontent.com/${REPO_SLUG}/main"
FF_DL="https://github.com/fastfetch-cli/fastfetch/releases/latest/download"
NF_DL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"

FONT_NAME="${FONT_NAME:-JetBrainsMono}"
INSTALL_FONT=1
INSTALL_FASTFETCH=1
FONT_FULL=0
FONT_OK=1

# ---------------------------------------------------------------- output ----

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
    C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
    C_RESET=""; C_DIM=""; C_BOLD=""
    C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi

step() { printf '%s==>%s %s%s%s\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"; }
info() { printf '    %s\n' "$1"; }
dim()  { printf '    %s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }
ok()   { printf '    %s✔%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn() { printf '    %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1" >&2; }
die()  { printf '\n%serror:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<EOF
${C_BOLD}fastfetch-config installer${C_RESET}

Usage: ./install.sh [options]

Options:
  --font NAME       Nerd Font to install (default: JetBrainsMono).
                    Use the name as published by ryanoasis/nerd-fonts,
                    e.g. Hack, FiraCode, Meslo, CascadiaCode, Iosevka.
  --font-full       Install every weight and variant instead of the
                    Regular/Bold/Italic/BoldItalic set.
  --no-font         Do not install a font.
  --no-fastfetch    Do not install fastfetch, only the config.
  -h, --help        Show this help.

Environment:
  FONT_NAME         Same as --font.
  NO_COLOR          Disable coloured output.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --font)        [ $# -ge 2 ] || die "--font requires a value"; FONT_NAME="$2"; shift 2 ;;
        --font=*)      FONT_NAME="${1#*=}"; shift ;;
        --font-full)   FONT_FULL=1; shift ;;
        --no-font)     INSTALL_FONT=0; shift ;;
        --no-fastfetch) INSTALL_FASTFETCH=0; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "unknown option: $1 (try --help)" ;;
    esac
done

# ------------------------------------------------------------ environment ----

WORKDIR=""
cleanup() { [ -n "$WORKDIR" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

case "$(uname -s)" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *)      PLATFORM="unix"  ;;
esac

case "$(uname -m)" in
    x86_64|amd64)   ARCH="amd64"   ;;
    aarch64|arm64)  ARCH="aarch64" ;;
    armv7l)         ARCH="armv7l"  ;;
    armv6l)         ARCH="armv6l"  ;;
    i686|i386)      ARCH="i686"    ;;
    riscv64)        ARCH="riscv64" ;;
    ppc64le)        ARCH="ppc64le" ;;
    s390x)          ARCH="s390x"   ;;
    *)              ARCH=""        ;;
esac

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if   have sudo; then SUDO="sudo"
    elif have doas; then SUDO="doas"
    fi
fi

# Downloads $1 to $2 using whatever is available.
download() {
    if   have curl; then curl -fsSL --retry 3 -o "$2" "$1"
    elif have wget; then wget -qO "$2" "$1"
    else die "neither curl nor wget is available"
    fi
}

# ------------------------------------------------------------- fastfetch ----

install_fastfetch_release() {
    # Last resort: unpack an upstream release into ~/.local.
    [ -n "$ARCH" ] || die "unsupported architecture: $(uname -m)"

    local slug tarball
    if [ "$PLATFORM" = "macos" ]; then
        slug="fastfetch-macos-${ARCH}"
    else
        slug="fastfetch-linux-${ARCH}"
    fi
    tarball="${WORKDIR}/${slug}.tar.gz"

    info "downloading ${slug}.tar.gz"
    download "${FF_DL}/${slug}.tar.gz" "$tarball" \
        || die "could not download a fastfetch release for ${slug}"

    tar -xzf "$tarball" -C "$WORKDIR"
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share"
    cp "${WORKDIR}/${slug}/usr/bin/fastfetch" "$HOME/.local/bin/fastfetch"
    chmod +x "$HOME/.local/bin/fastfetch"
    if [ -d "${WORKDIR}/${slug}/usr/share/fastfetch" ]; then
        rm -rf "$HOME/.local/share/fastfetch"
        cp -R "${WORKDIR}/${slug}/usr/share/fastfetch" "$HOME/.local/share/fastfetch"
    fi

    export PATH="$HOME/.local/bin:$PATH"
    ok "installed to ~/.local/bin/fastfetch"
    case ":${PATH}:" in
        *":$HOME/.local/bin:"*) ;;
        *) warn "add ~/.local/bin to your PATH to run fastfetch" ;;
    esac
}

install_fastfetch_deb() {
    [ -n "$ARCH" ] || return 1
    local deb="${WORKDIR}/fastfetch.deb"
    info "package not in the repositories, using the upstream .deb"
    download "${FF_DL}/fastfetch-linux-${ARCH}.deb" "$deb" || return 1
    $SUDO dpkg -i "$deb" >/dev/null 2>&1 || $SUDO apt-get -f install -y >/dev/null 2>&1
    have fastfetch
}

install_fastfetch_rpm() {
    [ -n "$ARCH" ] || return 1
    local rpm="${WORKDIR}/fastfetch.rpm"
    info "package not in the repositories, using the upstream .rpm"
    download "${FF_DL}/fastfetch-linux-${ARCH}.rpm" "$rpm" || return 1
    $SUDO rpm -i "$rpm" >/dev/null 2>&1 || return 1
    have fastfetch
}

install_fastfetch() {
    step "fastfetch"

    if have fastfetch; then
        ok "already installed ($(fastfetch --version 2>/dev/null | head -n1))"
        return
    fi

    if [ "$PLATFORM" = "macos" ]; then
        if have brew; then
            info "installing with Homebrew"
            brew install fastfetch >/dev/null 2>&1 || install_fastfetch_release
        else
            warn "Homebrew not found"
            install_fastfetch_release
        fi
    elif [ -n "$SUDO" ] || [ "$(id -u)" -eq 0 ]; then
        if have pacman; then
            info "installing with pacman"
            $SUDO pacman -S --needed --noconfirm fastfetch >/dev/null 2>&1 \
                || install_fastfetch_release
        elif have apt-get; then
            info "installing with apt"
            $SUDO apt-get update -qq >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq fastfetch >/dev/null 2>&1 \
                || install_fastfetch_deb \
                || install_fastfetch_release
        elif have dnf; then
            info "installing with dnf"
            $SUDO dnf install -y -q fastfetch >/dev/null 2>&1 \
                || install_fastfetch_rpm \
                || install_fastfetch_release
        elif have zypper; then
            info "installing with zypper"
            $SUDO zypper --non-interactive install fastfetch >/dev/null 2>&1 \
                || install_fastfetch_rpm \
                || install_fastfetch_release
        elif have apk; then
            info "installing with apk"
            $SUDO apk add --quiet fastfetch >/dev/null 2>&1 || install_fastfetch_release
        elif have xbps-install; then
            info "installing with xbps"
            $SUDO xbps-install -Sy fastfetch >/dev/null 2>&1 || install_fastfetch_release
        elif have eopkg; then
            info "installing with eopkg"
            $SUDO eopkg install -y fastfetch >/dev/null 2>&1 || install_fastfetch_release
        elif have emerge; then
            info "installing with emerge (this takes a while)"
            $SUDO emerge --quiet --ask=n app-misc/fastfetch || install_fastfetch_release
        elif have pkg; then
            info "installing with pkg"
            $SUDO pkg install -y fastfetch >/dev/null 2>&1 || install_fastfetch_release
        elif have brew; then
            info "installing with Homebrew"
            brew install fastfetch >/dev/null || install_fastfetch_release
        elif have nix-env; then
            info "installing with nix"
            nix-env -iA nixpkgs.fastfetch >/dev/null 2>&1 || install_fastfetch_release
        else
            warn "no supported package manager found"
            install_fastfetch_release
        fi
    else
        warn "no root privileges available, installing into your home directory"
        install_fastfetch_release
    fi

    have fastfetch || die "fastfetch installation failed"
    ok "$(fastfetch --version 2>/dev/null | head -n1)"
}

# ------------------------------------------------------------------ font ----

font_dir() {
    if [ "$PLATFORM" = "macos" ]; then
        printf '%s\n' "$HOME/Library/Fonts"
    else
        printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/NerdFonts"
    fi
}

font_already_installed() {
    local dir
    dir="$(font_dir)"

    if have fc-list && fc-list 2>/dev/null | grep -qi "${FONT_NAME} Nerd Font"; then
        return 0
    fi
    if [ -d "$dir" ] && ls "$dir" 2>/dev/null | grep -qi "^${FONT_NAME}NerdFont"; then
        return 0
    fi
    if [ "$PLATFORM" = "macos" ] && ls "$HOME/Library/Fonts" 2>/dev/null | grep -qi "^${FONT_NAME}NerdFont"; then
        return 0
    fi
    return 1
}

# Unpacks $1 into $2, choosing an extractor that exists on this system.
unpack_font_archive() {
    local archive="$1" dest="$2"
    case "$archive" in
        *.tar.xz)
            if tar -xJf "$archive" -C "$dest" 2>/dev/null; then return 0; fi
            if have xz && xz -dc "$archive" 2>/dev/null | tar -xf - -C "$dest" 2>/dev/null; then return 0; fi
            return 1 ;;
        *.zip)
            if have unzip  && unzip -qo "$archive" -d "$dest" 2>/dev/null; then return 0; fi
            if have bsdtar && bsdtar -xf "$archive" -C "$dest" 2>/dev/null; then return 0; fi
            if have python3 && python3 -m zipfile -e "$archive" "$dest" 2>/dev/null; then return 0; fi
            return 1 ;;
    esac
    return 1
}

# copy_fonts <file-list> <dest> <regex|empty>  ->  number of files copied
copy_fonts() {
    local list="$1" dest="$2" filter="$3"
    local copied=0 f base

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        base="$(basename "$f")"
        if [ -n "$filter" ]; then
            printf '%s\n' "$base" | grep -Eq "$filter" || continue
        fi
        cp -f "$f" "${dest}/${base}" || continue
        copied=$((copied + 1))
    done < "$list"

    printf '%s\n' "$copied"
}

install_font() {
    step "Nerd Font — ${FONT_NAME}"

    if font_already_installed; then
        ok "${FONT_NAME} Nerd Font is already installed"
        return
    fi

    local extract="${WORKDIR}/font"
    mkdir -p "$extract"

    # The .tar.xz is a few MB; the .zip is well over a hundred. Prefer the
    # small one and only fall back if this system cannot unpack xz.
    local archive="${WORKDIR}/${FONT_NAME}.tar.xz"
    info "downloading ${FONT_NAME}.tar.xz"
    if ! download "${NF_DL}/${FONT_NAME}.tar.xz" "$archive" 2>/dev/null; then
        warn "no Nerd Font named '${FONT_NAME}' — see https://www.nerdfonts.com/font-downloads"
        FONT_OK=0
        return
    fi

    if ! unpack_font_archive "$archive" "$extract"; then
        warn "cannot unpack .tar.xz here, falling back to the .zip (large download)"
        archive="${WORKDIR}/${FONT_NAME}.zip"
        download "${NF_DL}/${FONT_NAME}.zip" "$archive" \
            || { warn "font download failed"; FONT_OK=0; return; }
        unpack_font_archive "$archive" "$extract" \
            || { warn "could not unpack the font archive"; FONT_OK=0; return; }
    fi

    local dest
    dest="$(font_dir)"
    mkdir -p "$dest"

    local list="${WORKDIR}/fontfiles.txt"
    find "$extract" -type f \( -name '*.ttf' -o -name '*.otf' \) > "$list" 2>/dev/null || true

    # Regular/Bold/Italic/BoldItalic of the standard and Mono variants is what
    # a terminal actually needs; the archives ship ~100 files.
    local filter="^${FONT_NAME}NerdFont(Mono)?-(Regular|Bold|Italic|BoldItalic)\.(ttf|otf)$"
    if [ "$FONT_FULL" -eq 1 ]; then filter=""; fi

    local copied
    copied="$(copy_fonts "$list" "$dest" "$filter")"

    if [ "$copied" -eq 0 ] && [ -n "$filter" ]; then
        # A font that does not follow the usual naming: take everything.
        copied="$(copy_fonts "$list" "$dest" "")"
    fi

    [ "$copied" -gt 0 ] || { warn "no font files found in the archive"; FONT_OK=0; return; }

    if have fc-cache; then
        fc-cache -f "$dest" >/dev/null 2>&1 || fc-cache -f >/dev/null 2>&1 || true
    fi

    ok "installed ${copied} font file(s) to ${dest}"
}

# ---------------------------------------------------------------- config ----

config_dir() {
    # fastfetch itself knows where it looks for config files; the first entry
    # is the preferred one. Fall back to the XDG location if it cannot tell us.
    local dir=""
    if have fastfetch; then
        dir="$(fastfetch --list-config-paths 2>/dev/null | sed -n '1{s/ *(\*)$//;p;}' | sed 's:/*$::')" || dir=""
    fi
    [ -n "$dir" ] || dir="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
    printf '%s\n' "$dir"
}

# Resolves the config that ships next to this script, or downloads it.
source_config() {
    local here=""
    if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
        here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi

    if [ -n "$here" ] && [ -f "${here}/config.jsonc" ]; then
        printf '%s\n' "${here}/config.jsonc"
        return
    fi

    local tmp="${WORKDIR}/config.jsonc"
    download "${RAW_BASE}/config.jsonc" "$tmp" >&2 || die "could not download config.jsonc"
    printf '%s\n' "$tmp"
}

install_config() {
    step "configuration"

    local src dest_dir dest
    src="$(source_config)"
    dest_dir="$(config_dir)"
    dest="${dest_dir}/config.jsonc"

    mkdir -p "$dest_dir"

    if [ -f "$dest" ]; then
        if cmp -s "$src" "$dest"; then
            ok "config.jsonc is already up to date"
            return
        fi
        local backup="${dest}.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$dest" "$backup"
        info "existing config saved as $(basename "$backup")"
    fi

    cp -f "$src" "$dest"
    ok "installed to ${dest}"
}

# ------------------------------------------------------------------ main ----

main() {
    WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t fastfetch-config)"

    printf '\n%s%sfastfetch-config%s  %s%s%s\n\n' \
        "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_DIM" "github.com/${REPO_SLUG}" "$C_RESET"

    if [ "$INSTALL_FASTFETCH" -eq 1 ]; then install_fastfetch; fi
    if [ "$INSTALL_FONT" -eq 1 ]; then install_font; fi
    install_config

    step "done"
    if have fastfetch; then
        printf '\n'
        fastfetch || true
        printf '\n'
    fi
    if [ "$FONT_OK" -eq 1 ]; then
        dim "Set your terminal font to \"${FONT_NAME} Nerd Font\" so the icons render."
    else
        dim "Install a Nerd Font and set it as your terminal font so the icons render."
    fi
    dim "Run 'fastfetch' to print it again."
    printf '\n'
}

main
