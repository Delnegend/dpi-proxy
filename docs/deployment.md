# Deployment

The executable and container target Linux x86-64.

Install the executable with Homebrew:

```bash
brew install Delnegend/tap/dpi-proxy
dpi-proxy
```

Alternatively, download the `x86_64-unknown-linux-musl.tar.xz` archive from [GitHub Releases](https://github.com/Delnegend/dpi-proxy/releases/latest), extract it, and run the `dpi-proxy` executable in its top-level directory. The archive also contains the license files.

To run the published container on one trusted host address, substitute the host's LAN address:

```bash
podman run -d --name dpi-proxy --restart unless-stopped \
  -p 192.168.2.10:1080:1080 ghcr.io/delnegend/dpi-proxy:latest
```

Use an unused host port if ByeDPI is already using port 1080. The proxy has no authentication; restrict access to trusted clients with a firewall. The TCP connection from a client to this proxy is not encrypted by the proxy. HTTPS destinations retain their end-to-end encryption.

```bash
podman logs dpi-proxy
podman stop dpi-proxy
```

Steam's downloader can use an HTTP proxy via `http_proxy` and `https_proxy` in its launch environment. Client proxy support varies; test Steam sign-in, the Store, and a game update before retiring an existing proxy.
