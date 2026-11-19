#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/install.sh
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/install.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
export HOME="$tmp_dir/home"
unset XDG_CONFIG_HOME
mkdir -p "$HOME/.config/autostart"
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

echo 'Steam autostart proxy settings, repeated enable, disable, and custom config verified'
