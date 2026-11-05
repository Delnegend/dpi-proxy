# Deployment

The container targets Linux x86-64. Build it from this checkout with `podman build -t "dpi-proxy:$(just version get)" .`. The release workflow publishes `ghcr.io/delnegend/dpi-proxy` after the repository and releases exist.

To expose it on one trusted host address, substitute the host's LAN address:

```bash
podman run -d --name dpi-proxy --restart unless-stopped \
  -p 192.168.2.10:1080:1080 "dpi-proxy:$(just version get)"
```

Use an unused host port if ByeDPI is already using port 1080. The proxy has no authentication; restrict access to trusted clients with a firewall. The TCP connection from a client to this proxy is not encrypted by the proxy. HTTPS destinations retain their end-to-end encryption.

```bash
podman logs dpi-proxy
podman stop dpi-proxy
```

Steam's downloader can use an HTTP proxy via `http_proxy` and `https_proxy` in its launch environment. Client proxy support varies; test Steam sign-in, the Store, and a game update before retiring an existing proxy.
