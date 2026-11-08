<div align="center">

# dpi-proxy

**An HTTP proxy for Linux and Windows that helps applications reach services blocked by network traffic inspection.**

[![CI](https://img.shields.io/github/actions/workflow/status/Delnegend/dpi-proxy/ci.yml?branch=main)](https://github.com/Delnegend/dpi-proxy/actions) [![Release](https://img.shields.io/github/v/release/Delnegend/dpi-proxy)](https://github.com/Delnegend/dpi-proxy/releases) [![License](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue)](LICENSE-MIT)

</div>

---

## Quick start

### Linux

With [Homebrew](https://brew.sh/):

```bash
brew install Delnegend/tap/dpi-proxy
brew services start dpi-proxy

# Check the proxy can reach the Steam Store.
curl --noproxy '' --proxy http://127.0.0.1:18118 https://store.steampowered.com/ -o /dev/null -w '%{http_code}\n'
```

### Windows

1. Download and install the latest MSI package from [GitHub Releases](https://github.com/Delnegend/dpi-proxy/releases/latest). The installer automatically registers and starts the `DpiProxy` background service.
2. In Windows Search, type **Proxy settings**, select **Set up script** under Automatic proxy setup, and enter:
   ```text
   https://raw.githubusercontent.com/Delnegend/dpi-proxy/refs/heads/main/steam.pac
   ```

The default port is `18118`.
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
