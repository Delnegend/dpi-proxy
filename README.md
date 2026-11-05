# dpi-proxy

An HTTP proxy for Linux x86-64 that helps applications reach services blocked by network traffic inspection.

## Quick start

On Linux x86-64 with [Homebrew](https://brew.sh/):

```bash
brew install Delnegend/tap/dpi-proxy
dpi-proxy

# In another terminal, test an HTTPS connection through it.
curl --proxy http://127.0.0.1:1080 https://store.steampowered.com/ -o /dev/null -w '%{http_code}\n'
```

- Accepts ordinary HTTP proxy requests and HTTPS `CONNECT` tunnels.
- Applies ByeDPI-style traffic splitting to outbound connections.
- Runs as a standalone executable or non-root container.

**Security:** The proxy has no authentication. Bind the published port to a trusted interface and use a firewall if other machines need access. Traffic between the client and the proxy is not encrypted by the proxy; HTTPS remains encrypted end to end.

For container usage and release archives, see [Deployment](docs/deployment.md).

## Documentation

- [Configuration](docs/configuration.md)
- [Deployment](docs/deployment.md)
- [Development](docs/development.md)

## License

Licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE). Portions derived from [hufrea/byedpi](https://github.com/hufrea/byedpi) retain their original MIT notice.
