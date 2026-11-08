# Deployment

The executable and container target Linux x86-64.

## Install

Install the executable with Homebrew:

```bash
brew install Delnegend/tap/dpi-proxy
```

## Run as a service

Start it automatically at login:

```bash
brew services start dpi-proxy
```

The service and direct executable launches both listen on `127.0.0.1:18118` by default.

Check the service or read its logs:

```bash
brew services info dpi-proxy
journalctl --user -u sh.brew.dpi-proxy.service -f
```

## Upgrade

Upgrade with `brew upgrade dpi-proxy`, then restart with `brew services restart dpi-proxy`.

## Other deployment options

Alternatively, download the `x86_64-unknown-linux-musl.tar.xz` archive from [GitHub Releases](https://github.com/Delnegend/dpi-proxy/releases/latest), extract it, and run the `dpi-proxy` executable in its top-level directory. The archive also contains the license files.

To run the published container on one trusted host address, substitute the host's LAN address:

```bash
podman run -d --name dpi-proxy --restart unless-stopped \
  -p 192.168.2.10:18118:18118 ghcr.io/delnegend/dpi-proxy:latest
```

The proxy has no authentication; restrict access to trusted clients with a firewall. The TCP connection from a client to this proxy is not encrypted by the proxy. HTTPS destinations retain their end-to-end encryption.

```bash
podman logs dpi-proxy
podman stop dpi-proxy
```

Steam's downloader can use an HTTP proxy via `http_proxy` and `https_proxy` in its launch environment. Client proxy support varies; test Steam sign-in, the Store, and a game update before retiring an existing proxy.
