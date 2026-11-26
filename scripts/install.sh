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
            *KDE*|*PLASMA*) return 0 ;;
            *GNOME*) return 1 ;;
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

patch_desktop_file() {
    local file="$1"
    local action="$2"
    local proxy_env="$3"

    [ -f "$file" ] || return 1

    if [[ "$action" == "disable" ]]; then
        if grep -qE '^Exec=env http_proxy=[^ ]* https_proxy=[^ ]* no_proxy=[^ ]* ' "$file"; then
            chmod u+w "$file" 2>/dev/null || true
            sed -i 's|^Exec=env http_proxy=[^ ]* https_proxy=[^ ]* no_proxy=[^ ]* |Exec=|' "$file"
            return 0
        fi
        return 1
    fi

    local changed=false
    if grep -q '^Exec=' "$file" && grep '^Exec=' "$file" | grep -qvF "Exec=$proxy_env "; then
        chmod u+w "$file" 2>/dev/null || true
        sed -i \
            -e 's|^Exec=env http_proxy=[^ ]* https_proxy=[^ ]* no_proxy=[^ ]* |Exec=|' \
            -e "s|^Exec=\(env http_proxy=[^ ]* \)*|Exec=$proxy_env |" \
            "$file"
        changed=true
    fi

    # GNOME ignores Exec= when DBusActivatable=true is set on a launcher.
    if grep -q '^DBusActivatable=true$' "$file"; then
        chmod u+w "$file" 2>/dev/null || true
        sed -i 's|^DBusActivatable=true$|DBusActivatable=false|' "$file"
        changed=true
    fi

    [ "$changed" = true ]
}

configure_steam_desktop() {
    local action="${1:-enable}"
    local proxy_env="env http_proxy=http://127.0.0.1:$PORT https_proxy=http://127.0.0.1:$PORT no_proxy=localhost,127.0.0.1,steamloopback.host"
    local app_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    local sys_apps_dir="${DPI_PROXY_SYS_APPS_DIR:-/usr/share/applications}"
    local flatpak_sys_apps="${DPI_PROXY_FLATPAK_SYS_APPS_DIR:-/var/lib/flatpak/exports/share/applications}"
    local flatpak_user_apps="${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share/applications"
    local sys_apps=(
        "$sys_apps_dir/steam.desktop"
        "$sys_apps_dir/bazzite-steam-bpm.desktop"
        "$sys_apps_dir/steam-native.desktop"
        "$sys_apps_dir/steam-runtime.desktop"
        "$flatpak_sys_apps/com.valvesoftware.Steam.desktop"
        "$flatpak_user_apps/com.valvesoftware.Steam.desktop"
    )

    mkdir -p "$app_dir"

    local handled=""
    for sys_file in "${sys_apps[@]}"; do
        local filename
        filename="$(basename "$sys_file")"
        case " $handled " in
            *" $filename "*) continue ;;
        esac

        local user_file="$app_dir/$filename"

        if [[ "$action" == "disable" ]]; then
            if patch_desktop_file "$user_file" "disable" "$proxy_env"; then
                echo "Removed proxy override from $filename."
            fi
            handled="$handled $filename"
            continue
        fi

        if [ ! -f "$user_file" ]; then
            [ -f "$sys_file" ] || continue
            cp --remove-destination "$sys_file" "$user_file"
            chmod u+w "$user_file" 2>/dev/null || true
        fi

        handled="$handled $filename"

        if patch_desktop_file "$user_file" "enable" "$proxy_env"; then
            echo "Configured launcher proxy override in $filename."
        else
            echo "Launcher $filename is already configured."
        fi
    done

    # Also update a user Desktop shortcut if one exists.
    local desktop_shortcut="${XDG_DESKTOP_DIR:-$HOME/Desktop}/steam.desktop"
    if [ -f "$desktop_shortcut" ]; then
        if [[ "$action" == "disable" ]]; then
            if patch_desktop_file "$desktop_shortcut" "disable" "$proxy_env"; then
                echo "Removed proxy override from Desktop Steam shortcut."
            fi
        elif patch_desktop_file "$desktop_shortcut" "enable" "$proxy_env"; then
            echo "Configured Desktop Steam shortcut proxy override."
        fi
    fi

    # Configure Flatpak Steam sandbox environment if Flatpak Steam is installed.
    if command -v flatpak >/dev/null 2>&1 && flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
        if [[ "$action" == "disable" ]]; then
            flatpak override --user --unset-env=http_proxy --unset-env=https_proxy --unset-env=no_proxy com.valvesoftware.Steam >/dev/null 2>&1 || true
            echo "Removed Flatpak Steam proxy override."
        else
            flatpak override --user \
                --env="http_proxy=http://127.0.0.1:$PORT" \
                --env="https_proxy=http://127.0.0.1:$PORT" \
                --env="no_proxy=localhost,127.0.0.1,steamloopback.host" \
                com.valvesoftware.Steam >/dev/null 2>&1 || true
            echo "Configured Flatpak Steam proxy override."
        fi
    fi

    local autostart_dir="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
    local autostart_file="$autostart_dir/steam.desktop"
    local sys_autostart="${DPI_PROXY_SYS_AUTOSTART:-/etc/xdg/autostart/steam.desktop}"

    if [[ "$action" == "disable" ]]; then
        if [ -f "$autostart_file" ]; then
            if patch_desktop_file "$autostart_file" "disable" "$proxy_env"; then
                echo "Removed proxy override from Steam autostart."
            fi
        fi
    else
        if [ ! -f "$autostart_file" ] && [ -f "$sys_autostart" ]; then
            mkdir -p "$autostart_dir"
            cp --remove-destination "$sys_autostart" "$autostart_file"
            chmod u+w "$autostart_file" 2>/dev/null || true
        fi
        if [ -f "$autostart_file" ]; then
            if patch_desktop_file "$autostart_file" "enable" "$proxy_env"; then
                echo "Configured Steam autostart proxy override."
            fi
        fi
    fi

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
        local desktop_rc=0
        detect_desktop || desktop_rc=$?
        if [[ $desktop_rc -eq 0 ]]; then
            configure_kde "disable"
        elif [[ $desktop_rc -eq 1 ]]; then
            configure_gnome "disable"
        fi
        configure_steam_desktop "disable"
        exit 0
    fi

    echo "==> Setting up dpi-proxy..."
    resolve_or_install_brew
    ensure_dpi_proxy_running

    echo "==> Configuring desktop proxy..."
    local desktop_rc=0
    detect_desktop || desktop_rc=$?
    if [[ $desktop_rc -eq 0 ]]; then
        configure_kde "enable"
    elif [[ $desktop_rc -eq 1 ]]; then
        configure_gnome "enable"
    else
        echo "Note: Desktop environment is not GNOME or KDE Plasma."
        echo "Proxy service is running on 127.0.0.1:$PORT."
        echo "See docs/configuration.md to configure your desktop proxy manually."
    fi

    echo "==> Configuring application launchers..."
    configure_steam_desktop "enable"

    echo "==> All done! dpi-proxy is configured and ready to use."
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main "$@"
fi
