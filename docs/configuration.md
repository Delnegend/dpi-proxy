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

## Client setup for Steam

Choose one of the two options below to route Steam traffic through `dpi-proxy` while keeping other applications direct.

### Option 1: Automatic Proxy Configuration (PAC file)

A PAC script selectively directs Steam requests to `dpi-proxy` and sends everything else `DIRECT`. The script is provided in [`steam.pac`](../steam.pac).

#### GNOME
- **GUI:** Open **Settings** → **Network** → **Network Proxy** → select **Automatic** → enter Script URL: `file:///path/to/steam.pac` (or the raw GitHub URL).
- **CLI:**
  ```bash
  gsettings set org.gnome.system.proxy mode 'auto'
  gsettings set org.gnome.system.proxy autoconfig-url 'file:///path/to/steam.pac'
  ```

#### KDE Plasma
- **GUI:** Open **System Settings** → **Network** → **Proxy** → choose **Use proxy configuration script** → enter Script URL: `file:///path/to/steam.pac`.
- **CLI:**
  ```bash
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "ProxyType" 2
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "Proxy Config Script" "file:///path/to/steam.pac"
  qdbus org.kde.kded6 /kded org.kde.kded6.reconfigure
  ```

#### Windows
- **GUI:** Open **Settings** → **Network & internet** → **Proxy** → under **Automatic proxy setup**, turn on **Use setup script** → enter Script address: `file://C:/path/to/steam.pac` (or the raw GitHub URL) → click **Save**.
- **CLI (PowerShell):**
  ```powershell
  Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name AutoConfigURL -Value 'file://C:/path/to/steam.pac'
  ```

---

### Option 2: Manual proxy configuration with domain whitelist

Manually configure the proxy address (`127.0.0.1:18118`) and whitelist Steam domains.

#### Steam domains whitelist

```text
steampowered.com,*.steampowered.com,steamcommunity.com,*.steamcommunity.com,steamgames.com,*.steamgames.com,steamusercontent.com,*.steamusercontent.com,steamcontent.com,*.steamcontent.com,steamstatic.com,*.steamstatic.com,steamserver.net,*.steamserver.net,steam-chat.com,*.steam-chat.com,akamaihd.net,*.akamaihd.net,akamaized.net,*.akamaized.net,valvesoftware.com,*.valvesoftware.com,valve.net,*.valve.net,dota2.com,*.dota2.com,steamdeck.com,*.steamdeck.com,s.team,*.s.team,steam.tv,*.steam.tv
```

> **Important:** Chromium and Steam's web helper require both the apex domain and its wildcard (e.g. `steamcommunity.com,*.steamcommunity.com`). A bare `*.domain.com` wildcard matches subdomains only; requests to the root domain would bypass the proxy and get reset by your ISP.

#### KDE Plasma

KDE Plasma supports inverted bypass (`ReversedException=true`) to proxy **only** matching domains:
- **GUI:** Open **System Settings** → **Network** → **Proxy** → select **Manually specify proxy configuration** → set HTTP/HTTPS to `127.0.0.1` port `18118` → paste the domain whitelist into **Exceptions** → check **Use proxy only for entries in exception list**.
- **CLI:**
  ```bash
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "ProxyType" 1
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "httpProxy" "http://127.0.0.1 18118"
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "httpsProxy" "http://127.0.0.1 18118"
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "ReversedException" "true"
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "NoProxyFor" "steampowered.com,*.steampowered.com,steamcommunity.com,*.steamcommunity.com,steamgames.com,*.steamgames.com,steamusercontent.com,*.steamusercontent.com,steamcontent.com,*.steamcontent.com,steamstatic.com,*.steamstatic.com,steamserver.net,*.steamserver.net,steam-chat.com,*.steam-chat.com,akamaihd.net,*.akamaihd.net,akamaized.net,*.akamaized.net,valvesoftware.com,*.valvesoftware.com,valve.net,*.valve.net,dota2.com,*.dota2.com,steamdeck.com,*.steamdeck.com,s.team,*.s.team,steam.tv,*.steam.tv"
  qdbus org.kde.kded6 /kded org.kde.kded6.reconfigure
  ```

#### GNOME & Windows

GNOME and Windows manual proxy modes bypass matching domains rather than proxying only them. For selective routing, **Option 1 (PAC file)** is recommended. To proxy all system traffic manually:
- **GNOME GUI:** **Settings** → **Network** → **Network Proxy** → **Manual** → set host `127.0.0.1`, port `18118`.
- **GNOME CLI:**
  ```bash
  gsettings set org.gnome.system.proxy mode 'manual'
  gsettings set org.gnome.system.proxy.http host '127.0.0.1'
  gsettings set org.gnome.system.proxy.http port 18118
  gsettings set org.gnome.system.proxy.https host '127.0.0.1'
  gsettings set org.gnome.system.proxy.https port 18118
  ```
- **Windows GUI:** **Settings** → **Network & internet** → **Proxy** → **Manual proxy setup** → set IP `127.0.0.1`, port `18118`.
- **Windows CLI (PowerShell):**
  ```powershell
  Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 1
  Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyServer -Value '127.0.0.1:18118'
  ```

---

### Steam game downloads launcher

Steam's web helper (`steamwebhelper`) uses the desktop environment's proxy automatically. For background game chunk and manifest downloads, launch Steam with proxy environment variables:

```bash
env http_proxy=http://127.0.0.1:18118 https_proxy=http://127.0.0.1:18118 no_proxy=localhost,127.0.0.1,steamloopback.host steam
```

Place these variables in your desktop launcher (`.desktop` file) or wrapper script to ensure game chunk and manifest downloads route through the proxy.
