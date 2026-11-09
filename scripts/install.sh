#!/usr/bin/env bash
set -euo pipefail

PAC_URL="https://raw.githubusercontent.com/Delnegend/dpi-proxy/refs/heads/main/scripts/proxy.pac"
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

        local brew_installer
        brew_installer="$(mktemp -t brew-install.XXXXXX.sh)"
        curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" -o "$brew_installer"
        NONINTERACTIVE=1 /bin/bash "$brew_installer" < /dev/null
        rm -f "$brew_installer"

        for c in /home/linuxbrew/.linuxbrew/bin/brew /var/home/linuxbrew/.linuxbrew/bin/brew; do
            if [ -x "$c" ]; then brew_bin="$c"; break; fi
        done
        if [ -z "$brew_bin" ] || [ ! -x "$brew_bin" ]; then
            echo "Error: Cannot locate brew after installation." >&2
            exit 1
        fi
    fi

    # Ensure brew is available in future interactive shells
    local shellenv_cmd="eval \"\$($brew_bin shellenv)\""
    if [ -f "$HOME/.bashrc" ] && ! grep -q "shellenv" "$HOME/.bashrc"; then
        echo "" >> "$HOME/.bashrc"
        echo "$shellenv_cmd" >> "$HOME/.bashrc"
    elif [ -f "$HOME/.zshrc" ] && ! grep -q "shellenv" "$HOME/.zshrc"; then
        echo "" >> "$HOME/.zshrc"
        echo "$shellenv_cmd" >> "$HOME/.zshrc"
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

    IFS=":" read -ra desktops <<< "$current"
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

    echo "KDE Plasma configured with proxy.pac."
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

    echo "GNOME configured with proxy.pac."
}

configure_steam_desktop() {
    local action="${1:-enable}"
    local proxy_env="env http_proxy=http://127.0.0.1:$PORT https_proxy=http://127.0.0.1:$PORT no_proxy=localhost,127.0.0.1,steamloopback.host"
    local app_dir="$HOME/.local/share/applications"
    local sys_apps=("/usr/share/applications/steam.desktop" "/usr/share/applications/bazzite-steam-bpm.desktop")

    mkdir -p "$app_dir"

    for sys_file in "${sys_apps[@]}"; do
        local filename
        filename="$(basename "$sys_file")"
        local user_file="$app_dir/$filename"

        if [[ "$action" == "disable" ]]; then
            if [ -f "$user_file" ] && grep -q "127.0.0.1:$PORT" "$user_file"; then
                sed -i 's|^Exec=env http_proxy=[^ ]* https_proxy=[^ ]* no_proxy=[^ ]* |Exec=|' "$user_file"
                echo "Removed proxy override from $filename."
            fi
            continue
        fi

        [ -f "$sys_file" ] || continue

        if [ ! -f "$user_file" ]; then
            cp "$sys_file" "$user_file"
        fi

        if ! grep -q "127.0.0.1:$PORT" "$user_file"; then
            sed -i "s|^Exec=\(env http_proxy=[^ ]* \)*|Exec=$proxy_env |" "$user_file"
            echo "Configured Steam launcher override in $filename."
        else
            echo "Steam launcher $filename is already configured."
        fi
    done

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$app_dir" >/dev/null 2>&1 || true
    fi
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
        configure_steam_desktop "disable"
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

    echo "==> Configuring Steam launcher..."
    configure_steam_desktop "enable"

    echo "==> All done! Steam is ready to use."
}

main "$@"
