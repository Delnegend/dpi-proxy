//! Stream exactly one HTTP request body without leaking pipelined requests.
use super::{Body, MAX_HEADER, is_token};
use std::{
    io,
    pin::Pin,
    task::{Context, Poll},
};
use tokio::{
    io::{AsyncRead, AsyncWrite, ReadBuf},
    net::TcpStream,
};

pub(super) struct RequestStream {
    stream: TcpStream,
    input: Vec<u8>,
    offset: usize,
    state: State,
    trailer_bytes: usize,
}

enum State {
    Length(u64),
    Line { trailer: bool, bytes: Vec<u8> },
    Data(u64),
    DataCr,
    DataLf,
    Done,
    Invalid,
}

impl RequestStream {
    pub(super) const fn new(stream: TcpStream, input: Vec<u8>, body: Body) -> Self {
        let state = match body {
            Body::None | Body::Length(0) => State::Done,
            Body::Length(n) => State::Length(n),
            Body::Chunked => State::Line {
                trailer: false,
                bytes: Vec::new(),
            },
        };
        Self {
            stream,
            input,
            offset: 0,
            state,
            trailer_bytes: 0,
        }
    }

    fn line_byte(&mut self, byte: u8) -> bool {
        let State::Line { trailer, bytes } = &mut self.state else {
            return false;
        };
        if *trailer {
            self.trailer_bytes = self.trailer_bytes.saturating_add(1);
            if self.trailer_bytes > MAX_HEADER {
                return false;
            }
        }
        if byte != b'\n' {
            if bytes.len() >= MAX_HEADER || (bytes.last() == Some(&b'\r')) {
                return false;
            }
            bytes.push(byte);
            return true;
        }
        if bytes.pop() != Some(b'\r') {
            return false;
        }
        if *trailer {
            if bytes.is_empty() {
                self.state = State::Done;
                return true;
            }
            let Some(colon) = bytes.iter().position(|&b| b == b':') else {
                return false;
            };
            let Some(name) = bytes.get(..colon) else {
                return false;
            };
            let Some(value) = colon.checked_add(1).and_then(|start| bytes.get(start..)) else {
                return false;
            };
            if name.is_empty()
                || !name.iter().copied().all(is_token)
                || value.iter().any(|&b| (b < 32 && b != b'\t') || b == 127)
                || name.eq_ignore_ascii_case(b"content-length")
                || name.eq_ignore_ascii_case(b"transfer-encoding")
                || name.eq_ignore_ascii_case(b"host")
            {
                return false;
            }
            bytes.clear();
        } else {
            let size_bytes = bytes.split(|&b| b == b';').next().unwrap_or_default();
            if size_bytes.is_empty()
                || !size_bytes.iter().all(u8::is_ascii_hexdigit)
                || bytes.iter().any(|&b| b < 32 || b == 127)
            {
                return false;
            }
            let Ok(text) = std::str::from_utf8(size_bytes) else {
                return false;
            };
            let Ok(size) = u64::from_str_radix(text, 16) else {
                return false;
            };
            self.state = if size == 0 {
                State::Line {
                    trailer: true,
                    bytes: Vec::new(),
                }
            } else {
                State::Data(size)
            };
        }
        true
    }
}

impl AsyncRead for RequestStream {
    #[expect(
        clippy::too_many_lines,
        reason = "Keeps HTTP body framing state transitions together"
    )]
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        output: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = &mut *self;
        let initial_len = output.filled().len();
        loop {
            if output.remaining() == 0 || matches!(this.state, State::Done) {
                return Poll::Ready(Ok(()));
            }
            if matches!(this.state, State::Invalid) {
                return if output.filled().len() > initial_len {
                    Poll::Ready(Ok(()))
                } else {
                    Poll::Ready(Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "invalid HTTP request body",
                    )))
                };
            }
            if this.offset == this.input.len() {
                let mut data = [0u8; 8192];
                let mut read = ReadBuf::new(&mut data);
                match Pin::new(&mut this.stream).poll_read(cx, &mut read) {
                    Poll::Pending => {
                        return if output.filled().len() > initial_len {
                            Poll::Ready(Ok(()))
                        } else {
                            Poll::Pending
                        };
                    }
                    Poll::Ready(Err(e)) => {
                        if output.filled().len() > initial_len {
                            this.state = State::Invalid;
                            return Poll::Ready(Ok(()));
                        }
                        return Poll::Ready(Err(e));
                    }
                    Poll::Ready(Ok(())) if read.filled().is_empty() => {
                        this.state = State::Invalid;
                        continue;
                    }
                    Poll::Ready(Ok(())) => {
                        this.input.clear();
                        this.input.extend_from_slice(read.filled());
                        this.offset = 0;
                    }
                }
            }
            // Data bytes can be copied in bulk; only chunk delimiters need parsing.
            match &mut this.state {
                State::Length(remaining) | State::Data(remaining) => {
                    let Some(input) = this.input.get(this.offset..) else {
                        this.state = State::Invalid;
                        continue;
                    };
                    let amount = input
                        .len()
                        .min(output.remaining())
                        .min(usize::try_from(*remaining).unwrap_or(usize::MAX));
                    let Some(chunk) = input.get(..amount) else {
                        this.state = State::Invalid;
                        continue;
                    };
                    let Some(offset) = this.offset.checked_add(amount) else {
                        this.state = State::Invalid;
                        continue;
                    };
                    let Ok(consumed) = u64::try_from(amount) else {
                        this.state = State::Invalid;
                        continue;
                    };
                    let Some(left) = remaining.checked_sub(consumed) else {
                        this.state = State::Invalid;
                        continue;
                    };
                    output.put_slice(chunk);
                    this.offset = offset;
                    *remaining = left;
                    if *remaining == 0 {
                        this.state = if matches!(this.state, State::Length(_)) {
                            State::Done
                        } else {
                            State::DataCr
                        };
                    }
                }
                State::Line { .. } | State::DataCr | State::DataLf => {
                    let Some(&byte) = this.input.get(this.offset) else {
                        this.state = State::Invalid;
                        continue;
                    };
                    let Some(offset) = this.offset.checked_add(1) else {
                        this.state = State::Invalid;
                        continue;
                    };
                    this.offset = offset;
                    let valid = match this.state {
                        State::Line { .. } => this.line_byte(byte),
                        State::DataCr if byte == b'\r' => {
                            this.state = State::DataLf;
                            true
                        }
                        State::DataLf if byte == b'\n' => {
                            this.state = State::Line {
                                trailer: false,
                                bytes: Vec::new(),
                            };
                            true
                        }
                        _ => false,
                    };
                    if valid {
                        output.put_slice(&[byte]);
                    } else {
                        this.state = State::Invalid;
                    }
                }
                State::Done | State::Invalid => {}
            }
        }
    }
}
impl AsyncWrite for RequestStream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.stream).poll_write(cx, buf)
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.stream).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.stream).poll_shutdown(cx)
    }
}
