<div align="center">

# dpi-proxy

**An HTTP proxy for Linux x86-64 that helps applications reach services blocked by network traffic inspection.**

[![CI](https://img.shields.io/github/actions/workflow/status/Delnegend/dpi-proxy/ci.yml?branch=main)](https://github.com/Delnegend/dpi-proxy/actions) [![Release](https://img.shields.io/github/v/release/Delnegend/dpi-proxy)](https://github.com/Delnegend/dpi-proxy/releases) [![License](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue)](LICENSE-MIT)

</div>

---

## Quick start

On Linux x86-64 with [Homebrew](https://brew.sh/) and a systemd user session:

```bash
brew install Delnegend/tap/dpi-proxy
brew services start dpi-proxy

# Check the proxy can reach the Steam Store.
curl --noproxy '' --proxy http://127.0.0.1:18118 https://store.steampowered.com/ -o /dev/null -w '%{http_code}\n'
```

The service starts at login and listens only on this machine. Set your application's HTTP and HTTPS proxy to `http://127.0.0.1:18118`. Check or stop it with:

```bash
brew services info dpi-proxy
brew services stop dpi-proxy
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
