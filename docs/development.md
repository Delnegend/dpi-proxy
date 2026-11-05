# Development

## Prerequisites

Linux x86-64, Rust and Cargo, `rustfmt`, Clippy, `just`, Python 3 for local proxy checks, and Podman or Docker for the image. The image build uses Rust 1.98.1.

```bash
just check
podman build -t "dpi-proxy:$(just version get)" .
```

`just check` verifies formatting, Clippy and tests without modifying files. The GitHub workflows use the shared [Delnegend/actions](https://github.com/Delnegend/actions) release and scan machinery.

The Cargo dependency-update workflow requires Cargo 1.100 or newer to enforce the 14-day crate release cooldown. On older Cargo versions it skips automatic updates rather than applying an unenforced cooldown.
