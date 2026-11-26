#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/install.sh
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/install.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
export HOME="$tmp_dir/home"
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_DESKTOP_DIR
export DPI_PROXY_SYS_APPS_DIR="$tmp_dir/sys-apps"
export DPI_PROXY_FLATPAK_SYS_APPS_DIR="$tmp_dir/flatpak-sys-apps"
export DPI_PROXY_SYS_AUTOSTART="$tmp_dir/sys-autostart/steam.desktop"

mkdir -p "$HOME/.config/autostart" "$DPI_PROXY_SYS_APPS_DIR" "$DPI_PROXY_FLATPAK_SYS_APPS_DIR"
entry="$HOME/.config/autostart/steam.desktop"

cat > "$entry" <<'DESKTOP'
[Desktop Entry]
Name=Steam
Exec=/usr/bin/env

[Desktop Action Library]
Name=Library
Exec=/usr/bin/env
DESKTOP
cp "$entry" "$tmp_dir/original.desktop"

run_entry() {
    local line="$1"
    local command
    command="$(grep '^Exec=' "$entry" | head -n "$line" | tail -n 1)"
    env -i HOME="$HOME" /bin/bash -c "${command#Exec=}"
}

configure_steam_desktop enable >/dev/null
for line in 1 2; do
    environment="$(run_entry "$line")"
    grep -Fxq 'http_proxy=http://127.0.0.1:18118' <<< "$environment"
    grep -Fxq 'https_proxy=http://127.0.0.1:18118' <<< "$environment"
    grep -Fxq 'no_proxy=localhost,127.0.0.1,steamloopback.host' <<< "$environment"
done
cp "$entry" "$tmp_dir/enabled.desktop"
configure_steam_desktop enable >/dev/null
cmp "$entry" "$tmp_dir/enabled.desktop"
configure_steam_desktop disable >/dev/null
cmp "$entry" "$tmp_dir/original.desktop"
if run_entry 1 | grep -qi '_proxy='; then
    echo 'Steam autostart still has proxy settings after disable' >&2
    exit 1
fi

export XDG_CONFIG_HOME="$tmp_dir/config"
mkdir -p "$XDG_CONFIG_HOME/autostart"
entry="$XDG_CONFIG_HOME/autostart/steam.desktop"
cp "$tmp_dir/original.desktop" "$entry"
configure_steam_desktop enable >/dev/null
run_entry 1 | grep -Fxq 'http_proxy=http://127.0.0.1:18118'
configure_steam_desktop disable >/dev/null
cmp "$entry" "$tmp_dir/original.desktop"
rm "$entry"
configure_steam_desktop enable >/dev/null
[ ! -e "$entry" ]

# Test GNOME/Bazzite desktop launcher overrides (DBusActivatable, system autostart, Desktop shortcut)
cat > "$DPI_PROXY_SYS_APPS_DIR/steam.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Steam
Exec=/usr/bin/bazzite-steam %U
DBusActivatable=true

[Desktop Action Store]
Name=Store
Exec=/usr/bin/bazzite-steam steam://store
DESKTOP
mkdir -p "$(dirname "$DPI_PROXY_SYS_AUTOSTART")" "$HOME/Desktop"
cp "$tmp_dir/original.desktop" "$DPI_PROXY_SYS_AUTOSTART"
cp "$tmp_dir/original.desktop" "$HOME/Desktop/steam.desktop"

configure_steam_desktop enable >/dev/null
user_launcher="$HOME/.local/share/applications/steam.desktop"
[ -f "$user_launcher" ]
grep -Fxq 'DBusActivatable=false' "$user_launcher"
[ "$(grep -c '^Exec=env http_proxy=http://127.0.0.1:18118 https_proxy=http://127.0.0.1:18118 no_proxy=localhost,127.0.0.1,steamloopback.host ' "$user_launcher")" -eq 2 ]
[ -f "$entry" ]
grep -q '^Exec=env http_proxy=http://127.0.0.1:18118 ' "$entry"
grep -q '^Exec=env http_proxy=http://127.0.0.1:18118 ' "$HOME/Desktop/steam.desktop"

configure_steam_desktop disable >/dev/null
if grep -q 'http_proxy=http://127.0.0.1:18118' "$user_launcher"; then
    echo 'Steam launcher still has proxy settings after disable' >&2
    exit 1
fi
cmp "$HOME/Desktop/steam.desktop" "$tmp_dir/original.desktop"
cmp "$entry" "$tmp_dir/original.desktop"

# Test desktop detection for GNOME and KDE variants
for variant in "GNOME" "ubuntu:GNOME" "Bazzite-GNOME" "GNOME-Wayland"; do
    rc=0
    XDG_CURRENT_DESKTOP="$variant" DESKTOP_SESSION="" detect_desktop || rc=$?
    [ "$rc" -eq 1 ]
done
for variant in "KDE" "KDE:Plasma"; do
    rc=0
    XDG_CURRENT_DESKTOP="$variant" DESKTOP_SESSION="" detect_desktop || rc=$?
    [ "$rc" -eq 0 ]
done

echo 'Steam launchers, autostart, and desktop detection verified'
