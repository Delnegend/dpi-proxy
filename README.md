<div align="center">

# dpi-proxy

**An HTTP proxy for Linux and Windows that helps applications reach services blocked by network traffic inspection.**

[![CI](https://img.shields.io/github/actions/workflow/status/Delnegend/dpi-proxy/ci.yml?branch=main)](https://github.com/Delnegend/dpi-proxy/actions) [![Release](https://img.shields.io/github/v/release/Delnegend/dpi-proxy)](https://github.com/Delnegend/dpi-proxy/releases) [![License](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue)](LICENSE-MIT)

</div>

---

## Quick start

### 1. Installation

- **Linux:** Install and start the service with [Homebrew](https://brew.sh/):
  ```bash
  brew install Delnegend/tap/dpi-proxy
  brew services start dpi-proxy
  ```
- **Windows:** Download and run the installer from [GitHub Releases](https://github.com/Delnegend/dpi-proxy/releases/latest). It automatically registers and starts the `DpiProxy` background service.

The proxy listens on `127.0.0.1:18118`. Verify it answers:

```bash
curl --noproxy '' --proxy http://127.0.0.1:18118 https://store.steampowered.com/ -o /dev/null -w '%{http_code}\n'
```

### 2. Configuration

Configure your system or Steam client to route blocked traffic through the proxy. For step-by-step instructions via the automatic PAC script or manual domain whitelist on Windows, KDE Plasma, and GNOME, see [Configuration](docs/configuration.md).
## Highlights

- Connect applications using ordinary HTTP proxy requests or HTTPS tunnels.
- Split outgoing TLS traffic to help connections pass traffic inspection.
- Run locally as a service, standalone executable, or non-root container.

**Security:** The proxy has no authentication. Bind the published port to a trusted interface and use a firewall if other machines need access. Traffic between the client and the proxy is not encrypted by the proxy; HTTPS remains encrypted end to end.

For container usage and release archives, see [Deployment](docs/deployment.md).

## Documentation

- [Configuration](docs/configuration.md)
- [Architecture](docs/architecture.md)
- [Deployment](docs/deployment.md)
- [Development](docs/development.md)

## License

Licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE). Portions derived from [hufrea/byedpi](https://github.com/hufrea/byedpi) retain their original MIT notice.
