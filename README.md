<div align="center">

# dpi-proxy

**An HTTP proxy for Linux and Windows that helps bypass ISP Deep Packet Inspection (DPI) blocking.**

[![CI](https://img.shields.io/github/actions/workflow/status/Delnegend/dpi-proxy/ci.yml?branch=main&style=flat-square)](https://github.com/Delnegend/dpi-proxy/actions)
[![Release](https://img.shields.io/github/v/release/Delnegend/dpi-proxy?style=flat-square)](https://github.com/Delnegend/dpi-proxy/releases)
[![License](https://img.shields.io/badge/license-MIT%20%7C%20Apache--2.0-blue?style=flat-square)](LICENSE-MIT)

</div>

---

## Quick Start

### Windows

Download and run the `.msi` installer from [GitHub Releases](https://github.com/Delnegend/dpi-proxy/releases/latest). The installer automatically starts the background service and configures your proxy settings.

### Linux

Run the automated setup script (installs Homebrew if missing, starts the service, and configures your desktop proxy):
```bash
curl -fsSL https://raw.githubusercontent.com/Delnegend/dpi-proxy/refs/heads/main/scripts/install.sh | bash
```

**Verification:** Open any blocked website or service in your browser or application: pages will load on the first try without connection errors.

## Highlights

- Connect applications using ordinary HTTP proxy requests or HTTPS tunnels.
- Split outgoing TLS traffic to help connections pass traffic inspection.
- Run locally as a service, standalone executable, or non-root container.
- Survives network drops with clean connection teardowns and safe retry invariants.

## Documentation

- **[Architecture](docs/architecture.md)**: HTTP proxying, TLS record splitting, and safe retry invariants.
- **[Development](docs/development.md)**: Building from source, running tests, and cargo verification.
- **[Deployment](docs/deployment.md)**: Installation via Homebrew, MSI, release archives, and container setups.

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
