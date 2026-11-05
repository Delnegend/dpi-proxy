# Development

## Prerequisites

Linux x86-64; Rust and Cargo 1.85 or newer with `rustfmt` and Clippy; `just`; Python 3.11 or newer; and Podman or Docker for the optional image build. The image build uses Rust 1.98.1.

## Build and test

```bash
just check
```

`just check` verifies formatting, Clippy and tests without modifying files. The GitHub workflows use the shared [Delnegend/actions](https://github.com/Delnegend/actions) release and scan machinery.
