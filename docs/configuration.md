# Configuration

Set environment variables directly or place a `.env` file in the process's current directory. `dotenv-ng` loads the file if it exists; variables already present in the environment take precedence. Invalid values and malformed `.env` files stop startup.

| Variable | Default | Purpose |
|---|---|---|
| `DPI_PROXY_HOST` | `127.0.0.1` (`0.0.0.0` in the container) | Address to listen on |
| `DPI_PROXY_PORT` | `1080` | TCP port to listen on |
| `DPI_PROXY_SPLIT_SNI` | `true` | Split the initial TLS record after the first byte of the server name |
| `DPI_PROXY_RETRY_ON_RESET` | `true` | Retry once without the split after a reset or timeout, when splitting is enabled |
| `DPI_PROXY_TIMEOUT_SECS` | `3` | Seconds to wait for the first TLS response; fractional values are allowed |

Boolean values are `true` or `false`. The default bypass matches the existing ByeDPI settings `-r 1+s --auto=torst --timeout 3`. Ordinary HTTP requests are forwarded without replaying them. Command-line arguments are not supported.

For a container, pass settings with `-e` or `--env-file`:

```bash
podman run --rm -p 127.0.0.1:1080:1080 \
  -e DPI_PROXY_TIMEOUT_SECS=3 \
  "dpi-proxy:$(just version get)"
```

The proxy does not authenticate clients or encrypt the client-to-proxy connection. Publish it only to a trusted interface and restrict network access. It handles one ordinary HTTP request per connection and closes it after the response; HTTPS `CONNECT` remains a byte stream.
