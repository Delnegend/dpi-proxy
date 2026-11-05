@default:
    just --list

check:
    cargo fmt --check
    cargo clippy --locked --all-targets --all-features -- -D warnings
    cargo test --locked --all-targets --all-features
    cargo build --locked
    python3 tests/smoke.py

version action ver="":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{action}}" in
      get)
        python3 -c "import tomllib; print(tomllib.load(open('Cargo.toml', 'rb'))['package']['version'])"
        ;;
      set)
        [ -n "{{ver}}" ] || { echo "usage: just version set X.Y.Z" >&2; exit 1; }
        sed -i -E '0,/^version = ".*"/s//version = "{{ver}}"/' Cargo.toml
        cargo check
        ;;
      *) echo "usage: just version get|set X.Y.Z" >&2; exit 1 ;;
    esac
