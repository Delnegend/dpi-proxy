// TLS record splitting is based on ByeDPI (Copyright 2024 hufrea, MIT).
use std::io;
use std::time::Duration;

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::timeout;

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct BypassConfig {
    pub(crate) split_sni: bool,
    pub(crate) retry_on_reset: bool,
    pub(crate) timeout: Option<Duration>,
}

fn word(bytes: &[u8], offset: usize) -> Option<usize> {
    let [a, b] = bytes.get(offset..offset.checked_add(2)?)? else {
        return None;
    };
    Some(usize::from(u16::from_be_bytes([*a, *b])))
}

// The returned offset is immediately after the first byte of the TLS SNI.
fn sni_split(data: &[u8]) -> Option<(usize, usize)> {
    if data.first() != Some(&22) || data.get(1) != Some(&3) || data.get(5) != Some(&1) {
        return None;
    }
    let record_end = 5usize.checked_add(word(data, 3)?)?;
    if record_end > data.len() {
        return None;
    }
    let session_len = usize::from(*data.get(43)?);
    let mut pos = 44usize.checked_add(session_len)?;
    let cipher_len = word(data, pos)?;
    pos = pos.checked_add(2)?.checked_add(cipher_len)?;
    let compression_len = usize::from(*data.get(pos)?);
    pos = pos.checked_add(1)?.checked_add(compression_len)?;
    let extensions_len = word(data, pos)?;
    pos = pos.checked_add(2)?;
    let extensions_end = pos.checked_add(extensions_len)?;
    if extensions_end > record_end {
        return None;
    }
    while pos.checked_add(4)? <= extensions_end {
        let kind = word(data, pos)?;
        let len = word(data, pos.checked_add(2)?)?;
        let body = pos.checked_add(4)?;
        let next = body.checked_add(len)?;
        if next > extensions_end {
            return None;
        }
        if kind == 0 {
            let list_len = word(data, body)?;
            let mut name = body.checked_add(2)?;
            let names_end = name.checked_add(list_len)?;
            if names_end > next {
                return None;
            }
            while name.checked_add(3)? <= names_end {
                let ty = *data.get(name)?;
                let name_len = word(data, name.checked_add(1)?)?;
                name = name.checked_add(3)?;
                let end = name.checked_add(name_len)?;
                if end > names_end {
                    return None;
                }
                if ty == 0 && name_len > 0 {
                    return Some((name.checked_add(1)?, record_end));
                }
                name = end;
            }
            return None;
        }
        pos = next;
    }
    None
}

async fn send_split(
    upstream: &mut TcpStream,
    data: &[u8],
    split: usize,
    end: usize,
) -> io::Result<()> {
    let payload_start = 5usize;
    let first_len = split
        .checked_sub(payload_start)
        .and_then(|n| u16::try_from(n).ok())
        .ok_or_else(|| io::Error::other("invalid TLS split"))?;
    let second_len = end
        .checked_sub(split)
        .and_then(|n| u16::try_from(n).ok())
        .ok_or_else(|| io::Error::other("invalid TLS split"))?;
    let prefix = data
        .get(..3)
        .ok_or_else(|| io::Error::other("invalid TLS header"))?;
    let first = data
        .get(payload_start..split)
        .ok_or_else(|| io::Error::other("invalid TLS record"))?;
    let second = data
        .get(split..end)
        .ok_or_else(|| io::Error::other("invalid TLS record"))?;
    let trailing = data
        .get(end..)
        .ok_or_else(|| io::Error::other("invalid TLS record"))?;
    upstream.write_all(prefix).await?;
    upstream.write_all(&first_len.to_be_bytes()).await?;
    upstream.write_all(first).await?;
    upstream.write_all(prefix).await?;
    upstream.write_all(&second_len.to_be_bytes()).await?;
    upstream.write_all(second).await?;
    upstream.write_all(trailing).await
}

async fn copy<C: AsyncRead + AsyncWrite + Unpin>(
    client: &mut C,
    upstream: &mut TcpStream,
) -> io::Result<()> {
    tokio::io::copy_bidirectional(client, upstream).await?;
    Ok(())
}

// Only a TLS ClientHello can be retried: replaying HTTP requests could repeat a purchase or upload.
#[expect(
    clippy::too_many_lines,
    reason = "Keeps the TLS retry and stream state together"
)]
pub(crate) async fn relay_connected<C: AsyncRead + AsyncWrite + Unpin>(
    mut client: C,
    target: &str,
    initial: &[u8],
    config: &BypassConfig,
    mut upstream: TcpStream,
) -> io::Result<()> {
    if !initial.is_empty() && (!config.split_sni || initial.first() != Some(&22)) {
        upstream.write_all(initial).await?;
        return copy(&mut client, &mut upstream).await;
    }
    let mut request = initial.to_vec();
    let mut client_buffer = [0u8; 4096];
    let mut upstream_buffer = [0u8; 4096];
    if request.is_empty() {
        tokio::select! {
            result = client.read(&mut client_buffer) => {
                let n = result?;
                if n == 0 { upstream.shutdown().await?; return copy(&mut client, &mut upstream).await; }
                request.extend_from_slice(client_buffer.get(..n).ok_or_else(|| io::Error::other("invalid read length"))?);
            }
            result = upstream.read(&mut upstream_buffer) => {
                let n = result?;
                if n == 0 { return Ok(()); }
                client.write_all(upstream_buffer.get(..n).ok_or_else(|| io::Error::other("invalid read length"))?).await?;
                return copy(&mut client, &mut upstream).await;
            }
        }
    }
    if !config.split_sni || request.first() != Some(&22) {
        upstream.write_all(&request).await?;
        return copy(&mut client, &mut upstream).await;
    }
    // TCP can split a ClientHello across reads. Wait for its first complete record.
    loop {
        let needed = if request.len() < 5 {
            5
        } else {
            5usize.saturating_add(word(&request, 3).unwrap_or_default())
        };
        if request.len() >= needed {
            break;
        }
        let n = timeout(Duration::from_secs(30), client.read(&mut client_buffer))
            .await
            .map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "incomplete TLS record"))??;
        if n == 0 {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "incomplete TLS record",
            ));
        }
        request.extend_from_slice(
            client_buffer
                .get(..n)
                .ok_or_else(|| io::Error::other("invalid read length"))?,
        );
    }
    let Some((split, end)) = sni_split(&request) else {
        upstream.write_all(&request).await?;
        return copy(&mut client, &mut upstream).await;
    };
    let mut can_retry = config.retry_on_reset && request.len() == end;
    let sent = send_split(&mut upstream, &request, split, end).await;
    if let Err(error) = sent {
        if !can_retry || !retryable_error(&error) {
            return Err(error);
        }
        upstream = TcpStream::connect(target).await?;
        upstream.write_all(&request).await?;
        can_retry = false;
    }
    let mut client_closed = false;
    loop {
        let read = async {
            tokio::select! {
                result = upstream.read(&mut upstream_buffer) => (true, result),
                result = client.read(&mut client_buffer), if !client_closed => (false, result),
            }
        };
        let event = if let Some(duration) = config.timeout {
            timeout(duration, read).await.unwrap_or_else(|_| {
                (
                    true,
                    Err(io::Error::new(
                        io::ErrorKind::TimedOut,
                        "upstream response timed out",
                    )),
                )
            })
        } else {
            read.await
        };
        match event {
            (true, Ok(n)) if n > 0 => {
                client
                    .write_all(
                        upstream_buffer
                            .get(..n)
                            .ok_or_else(|| io::Error::other("invalid read length"))?,
                    )
                    .await?;
                return copy(&mut client, &mut upstream).await;
            }
            (true, result) => {
                let error = result.err().unwrap_or_else(|| {
                    io::Error::new(
                        io::ErrorKind::ConnectionReset,
                        "upstream closed before response",
                    )
                });
                if !can_retry || !retryable_error(&error) {
                    return Err(error);
                }
                upstream = TcpStream::connect(target).await?;
                upstream.write_all(&request).await?;
                can_retry = false;
            }
            (false, Ok(0)) => {
                client_closed = true;
                upstream.shutdown().await?;
            }
            (false, Ok(n)) => {
                can_retry = false;
                upstream
                    .write_all(
                        client_buffer
                            .get(..n)
                            .ok_or_else(|| io::Error::other("invalid read length"))?,
                    )
                    .await?;
            }
            (false, Err(error)) => return Err(error),
        }
    }
}

fn retryable_error(error: &io::Error) -> bool {
    matches!(
        error.kind(),
        io::ErrorKind::ConnectionReset
            | io::ErrorKind::ConnectionAborted
            | io::ErrorKind::BrokenPipe
            | io::ErrorKind::TimedOut
            | io::ErrorKind::UnexpectedEof
    )
}
