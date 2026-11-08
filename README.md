<div align="center">

# dpi-proxy

**An HTTP proxy for Linux and Windows that helps Steam and other applications bypass network traffic inspection.**

[![CI](https://img.shields.io/github/actions/workflow/status/Delnegend/dpi-proxy/ci.yml?branch=main)](https://github.com/Delnegend/dpi-proxy/actions) [![Release](https://img.shields.io/github/v/release/Delnegend/dpi-proxy)](https://github.com/Delnegend/dpi-proxy/releases) [![License](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue)](LICENSE-MIT)

</div>

---

## Quick start

### Windows

Download and run the `.msi` installer from [GitHub Releases](https://github.com/Delnegend/dpi-proxy/releases/latest). **That's it!** The installer automatically starts the background service and configures your proxy settings.

### Linux

Run the automated setup script (installs Homebrew if missing, starts the service, and configures your desktop proxy):
  ```bash
  curl -fsSL https://raw.githubusercontent.com/Delnegend/dpi-proxy/refs/heads/main/scripts/install.sh | bash
  ```

**Verification:** Open Steam and click **Store** or **Community**: pages will load on the first try without connection errors.

## Manual & Advanced options (Optional)

**No further setup is needed if you follow the automated installation steps above.**

If you prefer manual installation via Homebrew on Linux:

```bash
brew install Delnegend/tap/dpi-proxy
brew services start dpi-proxy
```

For manual desktop proxy settings, custom domain whitelists, or container setups, see [Configuration](docs/configuration.md).

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
