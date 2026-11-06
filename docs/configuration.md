# Configuration

Set environment variables directly or place a `.env` file in the process's current directory. `dotenv-ng` loads the file if it exists; variables already present in the environment take precedence. Invalid values and malformed `.env` files stop startup.

| Variable | Default | Purpose |
|---|---|---|
| `DPI_PROXY_HOST` | `127.0.0.1` (`0.0.0.0` in the container) | Address to listen on |
| `DPI_PROXY_PORT` | `1080` | TCP port to listen on |
| `DPI_PROXY_SPLIT_SNI` | `true` | Split the initial TLS record after the first byte of the server name |
| `DPI_PROXY_RETRY_ON_RESET` | `true` | Retry once after a reset or timeout, preserving the split when enabled |
| `DPI_PROXY_TIMEOUT_SECS` | `6` | Seconds to wait for the first TLS response; fractional values are allowed |

These defaults apply to a direct executable launch. The Homebrew service sets port `18118` and explicitly sets the other variables to their defaults.

Boolean values are `true` or `false`. Ordinary HTTP requests are forwarded without replaying them. Command-line arguments are not supported.

For a container, pass settings with `-e` or `--env-file`:

```bash
podman run --rm -p 127.0.0.1:1080:1080 \
  -e DPI_PROXY_TIMEOUT_SECS=6 \
  ghcr.io/delnegend/dpi-proxy:latest
```

The proxy does not authenticate clients or encrypt the client-to-proxy connection. Publish it only to a trusted interface and restrict network access. It handles one ordinary HTTP request per connection and closes it after the response; HTTPS `CONNECT` remains a byte stream.
