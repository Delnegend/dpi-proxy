//! HTTP/1.x forward proxy and CONNECT endpoint.
//!
//! Forward requests are deliberately limited to one per connection. This keeps
//! proxy-form requests from leaking into an origin connection on a pipeline.

use std::{io, sync::Arc, time::Duration};

use http::uri::{Authority, Uri};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    sync::Semaphore,
    time::timeout,
};

use crate::bypass::{self, BypassConfig};

#[path = "proxy_body.rs"]
mod proxy_body;
use proxy_body::RequestStream;

const MAX_HEADER: usize = 64 * 1024;
const MAX_CONNECTIONS: usize = 512;
const IO_TIMEOUT: Duration = Duration::from_secs(30);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

/// Serve clients until the listener fails. Each connection runs independently.
pub(crate) async fn serve(listener: TcpListener, config: Arc<BypassConfig>) -> io::Result<()> {
    let slots = Arc::new(Semaphore::new(MAX_CONNECTIONS));
    loop {
        let permit = slots
            .clone()
            .acquire_owned()
            .await
            .map_err(|_| io::Error::other("proxy stopped"))?;
        let (stream, _) = listener.accept().await?;
        let _ = stream.set_nodelay(true);
        let config = config.clone();
        tokio::spawn(async move {
            let _permit = permit;
            if let Err(error) = handle(stream, &config).await {
                eprintln!("proxy connection: {error}");
            }
        });
    }
}

struct Request {
    method: String,
    target: String,
    headers: Vec<(String, Vec<u8>)>,
    body: Body,
    expect_continue: bool,
}

#[derive(Clone, Copy)]
enum Body {
    None,
    Length(u64),
    Chunked,
}

struct HttpError {
    status: u16,
    reason: &'static str,
}
impl HttpError {
    const fn bad() -> Self {
        Self {
            status: 400,
            reason: "Bad Request",
        }
    }
    const fn large() -> Self {
        Self {
            status: 413,
            reason: "Content Too Large",
        }
    }
    const fn timeout() -> Self {
        Self {
            status: 408,
            reason: "Request Timeout",
        }
    }
}

async fn response(stream: &mut TcpStream, status: u16, reason: &str) -> io::Result<()> {
    stream
        .write_all(
            format!("HTTP/1.1 {status} {reason}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
                .as_bytes(),
        )
        .await
}

async fn handle(mut stream: TcpStream, config: &BypassConfig) -> io::Result<()> {
    let mut buffered = Vec::with_capacity(4096);
    let header_end = loop {
        if let Some(end) = find_end(&buffered) {
            break end;
        }
        if buffered.len() >= MAX_HEADER {
            return response(&mut stream, 431, "Request Header Fields Too Large").await;
        }
        match read_more(&mut stream, &mut buffered, MAX_HEADER).await {
            Ok(0) if buffered.is_empty() => return Ok(()),
            Ok(0) => return response(&mut stream, 400, "Bad Request").await,
            Ok(_) => {}
            Err(error) => return response(&mut stream, error.status, error.reason).await,
        }
    };
    let Some(header) = buffered.get(..header_end) else {
        return response(&mut stream, 400, "Bad Request").await;
    };
    let request = match parse_request(header) {
        Ok(req) => req,
        Err(error) => return response(&mut stream, error.status, error.reason).await,
    };
    if request.method == "CONNECT" {
        if !matches!(request.body, Body::None | Body::Length(0)) || request.expect_continue {
            return response(&mut stream, 400, "Bad Request").await;
        }
        let target = match authority_target(&request.target, None) {
            Ok(target) => target,
            Err(error) => return response(&mut stream, error.status, error.reason).await,
        };
        let upstream = match timeout(CONNECT_TIMEOUT, bypass::connect(&target)).await {
            Ok(Ok(upstream)) => upstream,
            Ok(Err(_)) => return response(&mut stream, 502, "Bad Gateway").await,
            Err(_) => return response(&mut stream, 504, "Gateway Timeout").await,
        };
        stream
            .write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            .await?;
        let Some(initial) = buffered.get(header_end..) else {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "invalid header boundary",
            ));
        };
        return bypass::relay_connected(stream, &target, initial, config, upstream).await;
    }

    let (target, path, host) = match forward_target(&request) {
        Ok(parts) => parts,
        Err(error) => return response(&mut stream, error.status, error.reason).await,
    };
    let initial = match forward_headers(&request, &path, &host) {
        Ok(headers) => headers,
        Err(error) => return response(&mut stream, error.status, error.reason).await,
    };
    let upstream = match timeout(CONNECT_TIMEOUT, bypass::connect(&target)).await {
        Ok(Ok(upstream)) => upstream,
        Ok(Err(_)) => return response(&mut stream, 502, "Bad Gateway").await,
        Err(_) => return response(&mut stream, 504, "Gateway Timeout").await,
    };
    if request.expect_continue {
        stream.write_all(b"HTTP/1.1 100 Continue\r\n\r\n").await?;
    }
    let client = RequestStream::new(stream, buffered.split_off(header_end), request.body);
    bypass::relay_connected(client, &target, &initial, config, upstream).await
}

fn find_end(bytes: &[u8]) -> Option<usize> {
    bytes
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .and_then(|p| p.checked_add(4))
}

async fn read_more(
    stream: &mut TcpStream,
    buf: &mut Vec<u8>,
    limit: usize,
) -> Result<usize, HttpError> {
    if buf.len() >= limit {
        return Err(HttpError::large());
    }
    let mut tmp = [0u8; 8192];
    let amount = tmp.len().min(limit.saturating_sub(buf.len()));
    let read_buf = tmp.get_mut(..amount).ok_or_else(HttpError::bad)?;
    let n = match timeout(IO_TIMEOUT, stream.read(read_buf)).await {
        Ok(Ok(n)) => n,
        Ok(Err(_)) => return Err(HttpError::bad()),
        Err(_) => return Err(HttpError::timeout()),
    };
    buf.extend_from_slice(tmp.get(..n).ok_or_else(HttpError::bad)?);
    Ok(n)
}

fn parse_request(bytes: &[u8]) -> Result<Request, HttpError> {
    let mut fields = [httparse::EMPTY_HEADER; 128];
    let mut parsed = httparse::Request::new(&mut fields);
    if !matches!(parsed.parse(bytes), Ok(httparse::Status::Complete(n)) if n == bytes.len()) {
        return Err(HttpError::bad());
    }
    let method = parsed.method.ok_or_else(HttpError::bad)?.to_owned();
    let target = parsed.path.ok_or_else(HttpError::bad)?.to_owned();
    if !matches!(parsed.version, Some(0 | 1)) {
        return Err(HttpError::bad());
    }
    let mut headers = Vec::with_capacity(parsed.headers.len());
    let mut length = None;
    let mut transfer = false;
    let mut host_seen = false;
    let mut expect_continue = false;
    for field in parsed.headers.iter() {
        let name = field.name.to_ascii_lowercase();
        let value = trim_ows(field.value);
        if value.iter().any(|&b| (b < 32 && b != b'\t') || b == 127) {
            return Err(HttpError::bad());
        }
        match name.as_str() {
            "host" => {
                if host_seen || value.is_empty() {
                    return Err(HttpError::bad());
                }
                host_seen = true;
            }
            "content-length" => {
                if length.is_some() || value.is_empty() || !value.iter().all(u8::is_ascii_digit) {
                    return Err(HttpError::bad());
                }
                let text = std::str::from_utf8(value).map_err(|_| HttpError::bad())?;
                let n: u64 = text.parse().map_err(|_| HttpError::bad())?;
                length = Some(n);
            }
            "transfer-encoding" => {
                if transfer || !value.eq_ignore_ascii_case(b"chunked") {
                    return Err(HttpError::bad());
                }
                transfer = true;
            }
            "expect" => {
                if expect_continue || !value.eq_ignore_ascii_case(b"100-continue") {
                    return Err(HttpError {
                        status: 417,
                        reason: "Expectation Failed",
                    });
                }
                expect_continue = true;
            }
            _ => {}
        }
        headers.push((name, value.to_vec()));
    }
    if transfer && length.is_some() {
        return Err(HttpError::bad());
    }
    if parsed.version == Some(1) && !host_seen {
        return Err(HttpError::bad());
    }
    Ok(Request {
        method,
        target,
        headers,
        body: if transfer {
            Body::Chunked
        } else if let Some(n) = length {
            Body::Length(n)
        } else {
            Body::None
        },
        expect_continue,
    })
}

const fn trim_ows(mut value: &[u8]) -> &[u8] {
    while let Some((&first, rest)) = value.split_first() {
        if first != b' ' && first != b'\t' {
            break;
        }
        value = rest;
    }
    while let Some((&last, rest)) = value.split_last() {
        if last != b' ' && last != b'\t' {
            break;
        }
        value = rest;
    }
    value
}

fn authority_target(value: &str, default_port: Option<u16>) -> Result<String, HttpError> {
    let authority: Authority = value.parse().map_err(|_| HttpError::bad())?;
    if authority.host().is_empty() || value.contains('@') {
        return Err(HttpError::bad());
    }
    let port = match authority.port_u16() {
        Some(port) if port != 0 => port,
        None if !value.ends_with(':')
            && (value.starts_with('[') && value.ends_with(']') || !value.contains(':')) =>
        {
            default_port.ok_or_else(HttpError::bad)?
        }
        _ => return Err(HttpError::bad()),
    };
    Ok(format!("{}:{port}", authority.host()))
}

fn forward_target(request: &Request) -> Result<(String, String, String), HttpError> {
    let uri: Uri = request.target.parse().map_err(|_| HttpError::bad())?;
    let (authority, path) = if let Some(scheme) = uri.scheme_str() {
        if !scheme.eq_ignore_ascii_case("http") {
            return Err(HttpError::bad());
        }
        let authority = uri
            .authority()
            .ok_or_else(HttpError::bad)?
            .as_str()
            .to_owned();
        let path = uri
            .path_and_query()
            .map(http::uri::PathAndQuery::as_str)
            .filter(|p| !p.is_empty())
            .unwrap_or("/")
            .to_owned();
        (
            authority,
            if path.starts_with('?') {
                format!("/{path}")
            } else {
                path
            },
        )
    } else {
        if !(request.target.starts_with('/')
            || request.method == "OPTIONS" && request.target == "*")
        {
            return Err(HttpError::bad());
        }
        let host = request
            .headers
            .iter()
            .find(|(name, _)| name == "host")
            .ok_or_else(HttpError::bad)?;
        (
            std::str::from_utf8(&host.1)
                .map_err(|_| HttpError::bad())?
                .to_owned(),
            request.target.clone(),
        )
    };
    let target = authority_target(&authority, Some(80))?;
    Ok((target, path, authority))
}

fn forward_headers(req: &Request, path: &str, host: &str) -> Result<Vec<u8>, HttpError> {
    let mut hop = vec![
        "connection".to_string(),
        "proxy-connection".to_string(),
        "proxy-authorization".to_string(),
        "proxy-authenticate".to_string(),
        "keep-alive".to_string(),
        "te".to_string(),
        "upgrade".to_string(),
        "expect".to_string(),
        "host".to_string(),
    ];
    for (name, value) in &req.headers {
        if name == "connection" || name == "proxy-connection" {
            let value = std::str::from_utf8(value).map_err(|_| HttpError::bad())?;
            for part in value.split(',') {
                let token = part.trim();
                if token.is_empty() || !token.bytes().all(is_token) {
                    return Err(HttpError::bad());
                }
                let token = token.to_ascii_lowercase();
                if token == "content-length" || token == "transfer-encoding" || token == "host" {
                    return Err(HttpError::bad());
                }
                hop.push(token);
            }
        }
    }
    let mut out = format!("{} {} HTTP/1.1\r\nHost: {}\r\n", req.method, path, host).into_bytes();
    for (name, value) in &req.headers {
        if !hop.contains(name) {
            out.extend_from_slice(name.as_bytes());
            out.extend_from_slice(b": ");
            out.extend_from_slice(value);
            out.extend_from_slice(b"\r\n");
        }
    }
    out.extend_from_slice(b"Connection: close\r\n\r\n");
    Ok(out)
}

fn is_token(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b"!#$%&'*+-.^_`|~".contains(&b)
}
