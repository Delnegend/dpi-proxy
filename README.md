# dpi-proxy

An HTTP proxy for Linux x86-64 that helps applications reach services blocked by network traffic inspection.

## Quick start

Requires Podman and `just`.

```bash
# Build the local image.
podman build -t "dpi-proxy:$(just version get)" .

# Expose the proxy only to this machine.
podman run --rm -p 127.0.0.1:1080:1080 "dpi-proxy:$(just version get)"

# In another terminal, test an HTTPS connection through it.
curl --proxy http://127.0.0.1:1080 https://store.steampowered.com/ -o /dev/null -w '%{http_code}\n'
```

- Accepts ordinary HTTP proxy requests and HTTPS `CONNECT` tunnels.
- Applies ByeDPI-style traffic splitting to outbound connections.
- Ships as a non-root container, with the listener limited by the published port.

**Security:** The proxy has no authentication. Bind the published port to a trusted interface and use a firewall if other machines need access. Traffic between the client and the proxy is not encrypted by the proxy; HTTPS remains encrypted end to end.

## Documentation

- [Configuration](docs/configuration.md)
- [Deployment](docs/deployment.md)
- [Development](docs/development.md)

## License

Licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE). Portions derived from [hufrea/byedpi](https://github.com/hufrea/byedpi) retain their original MIT notice.
