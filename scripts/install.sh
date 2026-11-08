#!/usr/bin/env bash
set -euo pipefail

PAC_URL="https://raw.githubusercontent.com/Delnegend/dpi-proxy/refs/heads/main/scripts/steam.pac"
PORT="18118"

# 1. Resolve or install Homebrew
resolve_or_install_brew() {
    local brew_bin=""
    for c in /home/linuxbrew/.linuxbrew/bin/brew /var/home/linuxbrew/.linuxbrew/bin/brew; do
        if [ -x "$c" ]; then brew_bin="$c"; break; fi
    done
    if [ -z "$brew_bin" ] && command -v brew &>/dev/null; then
        brew_bin="$(command -v brew)"
    fi

    if [ -z "$brew_bin" ] || [ ! -x "$brew_bin" ]; then
        echo "Homebrew not detected. Installing Homebrew..."
        export NONINTERACTIVE=1
        export HOMEBREW_NO_AUTO_UPDATE=1
        export HOMEBREW_NO_ANALYTICS=1
        export HOMEBREW_NO_ASK=1

        if ! command -v curl &>/dev/null || ! command -v git &>/dev/null; then
            if command -v apt-get &>/dev/null; then
                sudo apt-get update -qq && sudo apt-get install -y curl git
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y curl git
            elif command -v yum &>/dev/null; then
                sudo yum install -y curl git
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm curl git
            fi
        fi

        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null

        for c in /home/linuxbrew/.linuxbrew/bin/brew /var/home/linuxbrew/.linuxbrew/bin/brew; do
            if [ -x "$c" ]; then brew_bin="$c"; break; fi
        done
        if [ -z "$brew_bin" ] || [ ! -x "$brew_bin" ]; then
            echo "Error: Cannot locate brew after installation." >&2
            exit 1
        fi
    fi

    eval "$("$brew_bin" shellenv)"
    BREW_CMD="$brew_bin"
}

# 2. Ensure dpi-proxy is installed and running
ensure_dpi_proxy_running() {
    if ! "$BREW_CMD" list dpi-proxy &>/dev/null; then
        echo "Installing dpi-proxy via Homebrew..."
        "$BREW_CMD" install Delnegend/tap/dpi-proxy
    else
        echo "dpi-proxy is already installed."
    fi

    local is_active=false
    if command -v systemctl &>/dev/null && systemctl --user is-active sh.brew.dpi-proxy.service &>/dev/null; then
        is_active=true
    fi

    if [ "$is_active" = false ]; then
        echo "Starting dpi-proxy service..."
        "$BREW_CMD" services start dpi-proxy
    else
        echo "dpi-proxy service is running."
    fi
}

# 3. Detect desktop environment (KDE Plasma or GNOME)
detect_desktop() {
    local current="${XDG_CURRENT_DESKTOP:-}"
    local session="${DESKTOP_SESSION:-}"

    local IFS=":"
    read -ra desktops <<< "$current"
    for d in "${desktops[@]}"; do
        case "${d^^}" in
            KDE) return 0 ;;
            GNOME) return 1 ;;
        esac
    done

    case "${session,,}" in
        *plasma*|*kde*) return 0 ;;
        *gnome*|*ubuntu*) return 1 ;;
    esac

    if [[ "${KDE_FULL_SESSION:-}" == "true" ]]; then
        return 0
    fi
    if [[ -n "${GNOME_DESKTOP_SESSION_ID:-}" ]]; then
        return 1
    fi

    if command -v kwriteconfig6 >/dev/null 2>&1 && pgrep -u "$UID" -f "plasmashell|kded6" >/dev/null 2>&1; then
        return 0
    fi
    if command -v gsettings >/dev/null 2>&1 && pgrep -u "$UID" -f "gnome-shell" >/dev/null 2>&1; then
        return 1
    fi

    return 2
}

configure_kde() {
    local kw=""
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kw="kwriteconfig6"
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
        kw="kwriteconfig5"
    else
        echo "Error: Neither kwriteconfig6 nor kwriteconfig5 found." >&2
        exit 1
    fi

    if [[ "${1:-enable}" == "disable" ]]; then
        "$kw" --file kioslaverc --group "Proxy Settings" --key "ProxyType" 0
        qdbus org.kde.kded6 /kded org.kde.kded6.reconfigure 2>/dev/null || \
        qdbus org.kde.kded5 /kded org.kde.kded5.reconfigure 2>/dev/null || true
        echo "KDE Plasma proxy reset to direct connection."
        return 0
    fi

    "$kw" --file kioslaverc --group "Proxy Settings" --key "ProxyType" 2
    "$kw" --file kioslaverc --group "Proxy Settings" --key "Proxy Config Script" "$PAC_URL"
    qdbus org.kde.kded6 /kded org.kde.kded6.reconfigure 2>/dev/null || \
    qdbus org.kde.kded5 /kded org.kde.kded5.reconfigure 2>/dev/null || true

    echo "KDE Plasma configured with steam.pac."
}

configure_gnome() {
    if ! command -v gsettings >/dev/null 2>&1; then
        echo "Error: gsettings tool not found." >&2
        exit 1
    fi

    if [[ "${1:-enable}" == "disable" ]]; then
        gsettings set org.gnome.system.proxy mode 'none'
        gsettings set org.gnome.system.proxy autoconfig-url ''
        echo "GNOME proxy reset to direct connection."
        return 0
    fi

    gsettings set org.gnome.system.proxy mode 'auto'
    gsettings set org.gnome.system.proxy autoconfig-url "$PAC_URL"

    echo "GNOME configured with steam.pac."
}

main() {
    local action="enable"
    if [[ "${1:-}" == "--disable" || "${1:-}" == "--undo" || "${1:-}" == "disable" ]]; then
        action="disable"
    fi

    if [[ "$action" == "disable" ]]; then
        if detect_desktop; then
            configure_kde "disable"
        elif [[ $? -eq 1 ]]; then
            configure_gnome "disable"
        fi
        exit 0
    fi

    echo "==> Setting up dpi-proxy..."
    resolve_or_install_brew
    ensure_dpi_proxy_running

    echo "==> Configuring desktop proxy..."
    if detect_desktop; then
        configure_kde "enable"
    elif [[ $? -eq 1 ]]; then
        configure_gnome "enable"
    else
        echo "Note: Desktop environment is not GNOME or KDE Plasma."
        echo "Proxy service is running on 127.0.0.1:$PORT."
        echo "See docs/configuration.md to configure your desktop or app manually."
        exit 0
    fi

    echo "==> All done! Steam is ready to use."
}

main "$@"
