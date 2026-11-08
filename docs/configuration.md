# Configuration

Set environment variables directly or place a `.env` file in the process's current directory. `dotenv-ng` loads the file if it exists; variables already present in the environment take precedence. Invalid values and malformed `.env` files stop startup.

| Variable | Default | Purpose |
|---|---|---|
| `DPI_PROXY_HOST` | `127.0.0.1` (`0.0.0.0` in the container) | Address to listen on |
| `DPI_PROXY_PORT` | `1080` | TCP port to listen on |
| `DPI_PROXY_SPLIT_SNI` | `true` | Split the initial TLS record after the first byte of the server name |
| `DPI_PROXY_RETRY_ON_RESET` | `true` | Retry once after a reset or timeout, preserving the split when enabled |
| `DPI_PROXY_TIMEOUT_SECS` | `6` | Seconds to wait for the first TLS response; fractional values are allowed |

These defaults apply to a direct executable launch. The Homebrew service sets port `18118` and explicitly sets the other variables to their defaults.

Boolean values are `true` or `false`. Ordinary HTTP requests are forwarded without replaying them. Command-line arguments are not supported.

For a container, pass settings with `-e` or `--env-file`:

```bash
podman run --rm -p 127.0.0.1:1080:1080 \
  -e DPI_PROXY_TIMEOUT_SECS=6 \
  ghcr.io/delnegend/dpi-proxy:latest
```

The proxy does not authenticate clients or encrypt the client-to-proxy connection. Publish it only to a trusted interface and restrict network access. It handles one ordinary HTTP request per connection and closes it after the response; HTTPS `CONNECT` remains a byte stream.

## Desktop environment proxy setup

To route only Steam traffic through `dpi-proxy` while letting other applications connect directly, configure your desktop environment's proxy settings.

### KDE Plasma

KDE Plasma stores proxy settings in `~/.config/kioslaverc`. Setting `ReversedException=true` inverts the bypass list so that the proxy is used **only** for matching domains.

```ini
[Proxy Settings]
ProxyType=1
httpProxy=http://127.0.0.1 18118
httpsProxy=http://127.0.0.1 18118
ReversedException=true
NoProxyFor=steampowered.com,*.steampowered.com,steamcommunity.com,*.steamcommunity.com,steamgames.com,*.steamgames.com,steamusercontent.com,*.steamusercontent.com,steamcontent.com,*.steamcontent.com,steamstatic.com,*.steamstatic.com,steamserver.net,*.steamserver.net,steam-chat.com,*.steam-chat.com,akamaihd.net,*.akamaihd.net,akamaized.net,*.akamaized.net,valvesoftware.com,*.valvesoftware.com,valve.net,*.valve.net,dota2.com,*.dota2.com,steamdeck.com,*.steamdeck.com,s.team,*.s.team,steam.tv,*.steam.tv
```

> **Important:** Chromium and Steam's web helper require both the apex domain and its wildcard (e.g. `steamcommunity.com,*.steamcommunity.com`). A bare `*.domain.com` wildcard matches subdomains only; requests to the root domain would bypass the proxy and get reset by your ISP.

Apply changes without logging out:

```bash
qdbus org.kde.kded6 /kded org.kde.kded6.reconfigure
```

### GNOME

GNOME's manual proxy mode routes all traffic by default and uses `ignore-hosts` for direct bypass. To selectively proxy only Steam domains, use a Proxy Auto-Configuration (PAC) file or set system-wide manual proxy:

```bash
gsettings set org.gnome.system.proxy mode 'manual'
gsettings set org.gnome.system.proxy.http host '127.0.0.1'
gsettings set org.gnome.system.proxy.http port 18118
gsettings set org.gnome.system.proxy.https host '127.0.0.1'
gsettings set org.gnome.system.proxy.https port 18118
```

For selective routing, serve or reference a local PAC file:

```javascript
function FindProxyForURL(url, host) {
    if (dnsDomainIs(host, "steampowered.com") ||
        dnsDomainIs(host, "steamcommunity.com") ||
        dnsDomainIs(host, "steamgames.com") ||
        dnsDomainIs(host, "steamusercontent.com") ||
        dnsDomainIs(host, "steamcontent.com") ||
        dnsDomainIs(host, "steamstatic.com") ||
        dnsDomainIs(host, "steamserver.net") ||
        dnsDomainIs(host, "steam-chat.com") ||
        dnsDomainIs(host, "akamaihd.net") ||
        dnsDomainIs(host, "akamaized.net") ||
        dnsDomainIs(host, "valvesoftware.com") ||
        dnsDomainIs(host, "valve.net") ||
        dnsDomainIs(host, "dota2.com") ||
        dnsDomainIs(host, "steamdeck.com") ||
        dnsDomainIs(host, "s.team") ||
        dnsDomainIs(host, "steam.tv")) {
        return "PROXY 127.0.0.1:18118; DIRECT";
    }
    return "DIRECT";
}
```

Point GNOME to the file:

```bash
gsettings set org.gnome.system.proxy mode 'auto'
gsettings set org.gnome.system.proxy autoconfig-url 'file:///path/to/proxy.pac'
```

### Steam client downloads

Steam's UI and store pages (`steamwebhelper`) use your desktop environment's proxy configuration automatically. However, the background game downloader uses standard environment variables. Launch Steam with:

```bash
env http_proxy=http://127.0.0.1:18118 https_proxy=http://127.0.0.1:18118 no_proxy=localhost,127.0.0.1,steamloopback.host steam
```

Place these variables in your desktop launcher (`.desktop` file) or wrapper script to ensure game chunk and manifest downloads route through the proxy.
