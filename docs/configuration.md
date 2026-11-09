# Configuration

## Client setup

Configure your system to use `proxy.pac`. The script routes internet traffic through `dpi-proxy` on port `18118` while bypassing local CIDR ranges, localhost, and Tailscale directly.

PAC script URL:
`https://raw.githubusercontent.com/Delnegend/dpi-proxy/refs/heads/main/scripts/proxy.pac`

### Windows

The MSI installer configures the PAC script automatically during installation.

#### Automatic PAC script
- **GUI:** In Windows Search, type **Proxy settings** and open it. Under **Automatic proxy setup**, turn on **Use setup script**, paste the PAC URL into **Script address**, and click **Save**.
- **CLI (PowerShell):**
  ```powershell
  Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name AutoConfigURL -Value 'https://raw.githubusercontent.com/Delnegend/dpi-proxy/refs/heads/main/scripts/proxy.pac'
  ```

#### Manual system proxy
Windows Search → **Proxy settings** → under **Manual proxy setup**, click **Set up** → turn on **Use a proxy server**, enter IP `127.0.0.1` and Port `18118`, and click **Save**.

---

### KDE Plasma

#### Automatic PAC script (Recommended)
- **GUI:** **System Settings** → **Network** → **Proxy** → select **Use proxy configuration script** → enter the PAC URL → click **Apply**.
- **CLI:**
  ```bash
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "ProxyType" 2
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "Proxy Config Script" "https://raw.githubusercontent.com/Delnegend/dpi-proxy/refs/heads/main/scripts/proxy.pac"
  qdbus org.kde.kded6 /kded org.kde.kded6.reconfigure
  ```

#### Inverted domain whitelist
Proxy *only* Steam domains using KDE's inverted bypass:
- **GUI:** **System Settings** → **Network** → **Proxy** → select **Manually specify proxy configuration** → set `127.0.0.1:18118` → paste the [Steam domains](#steam-domains-whitelist) into **Exceptions** → check **Use proxy only for entries in exception list**.
- **CLI:**
  ```bash
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "ProxyType" 1
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "httpProxy" "http://127.0.0.1 18118"
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "httpsProxy" "http://127.0.0.1 18118"
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "ReversedException" "true"
  kwriteconfig6 --file kioslaverc --group "Proxy Settings" --key "NoProxyFor" "<domain-whitelist>"
  qdbus org.kde.kded6 /kded org.kde.kded6.reconfigure
  ```

---

### GNOME

#### Automatic PAC script (Recommended)
- **GUI:** **Settings** → **Network** → **Network Proxy** → select **Automatic** → enter the PAC URL.
- **CLI:**
  ```bash
  gsettings set org.gnome.system.proxy mode 'auto'
  gsettings set org.gnome.system.proxy autoconfig-url 'https://raw.githubusercontent.com/Delnegend/dpi-proxy/refs/heads/main/scripts/proxy.pac'
  ```

#### Manual system proxy
- **GUI:** **Settings** → **Network** → **Network Proxy** → **Manual** → set host `127.0.0.1`, port `18118`.
- **CLI:**
  ```bash
  gsettings set org.gnome.system.proxy mode 'manual'
  gsettings set org.gnome.system.proxy.http host '127.0.0.1'
  gsettings set org.gnome.system.proxy.http port 18118
  gsettings set org.gnome.system.proxy.https host '127.0.0.1'
  gsettings set org.gnome.system.proxy.https port 18118
  ```

---

### Steam domains whitelist

Both apex domains and wildcards (`domain.com,*.domain.com`) are required so root domain requests do not bypass the proxy:

```text
steampowered.com,*.steampowered.com,steamcommunity.com,*.steamcommunity.com,steamgames.com,*.steamgames.com,steamusercontent.com,*.steamusercontent.com,steamcontent.com,*.steamcontent.com,steamstatic.com,*.steamstatic.com,steamserver.net,*.steamserver.net,steam-chat.com,*.steam-chat.com,akamaihd.net,*.akamaihd.net,akamaized.net,*.akamaized.net,valvesoftware.com,*.valvesoftware.com,valve.net,*.valve.net,dota2.com,*.dota2.com,steamdeck.com,*.steamdeck.com,s.team,*.s.team,steam.tv,*.steam.tv
```

### Linux game download launcher

Steam's UI and store pages (`steamwebhelper`) use desktop environment proxy settings automatically. On Linux, the background game downloader uses standard environment variables:

```bash
env http_proxy=http://127.0.0.1:18118 https_proxy=http://127.0.0.1:18118 no_proxy=localhost,127.0.0.1,steamloopback.host steam
```

## DPI Proxy configuration

Set environment variables directly or place a `.env` file in the process's current directory. `dotenv-ng` loads the file if it exists; variables already present in the environment take precedence. Invalid values and malformed `.env` files stop startup.

| Variable | Default | Purpose |
|---|---|---|
| `DPI_PROXY_HOST` | `127.0.0.1` (`0.0.0.0` in the container) | Address to listen on |
| `DPI_PROXY_PORT` | `18118` | TCP port to listen on |
| `DPI_PROXY_SPLIT_SNI` | `true` | Split the initial TLS record after the first byte of the server name |
| `DPI_PROXY_RETRY_ON_RESET` | `true` | Retry once after a reset or timeout, preserving the split when enabled |
| `DPI_PROXY_TIMEOUT_SECS` | `6` | Seconds to wait for the first TLS response; fractional values are allowed |

These defaults apply to direct executable launches, containers, and the Homebrew service.

Boolean values are `true` or `false`. Ordinary HTTP requests are forwarded without replaying them. Command-line arguments are not supported.

For a container, pass settings with `-e` or `--env-file`:

```bash
podman run --rm -p 127.0.0.1:18118:18118 \
  -e DPI_PROXY_TIMEOUT_SECS=6 \
  ghcr.io/delnegend/dpi-proxy:latest
```

The proxy does not authenticate clients or encrypt the client-to-proxy connection. Publish it only to a trusted interface and restrict network access. It handles one ordinary HTTP request per connection and closes it after the response; HTTPS `CONNECT` remains a byte stream.