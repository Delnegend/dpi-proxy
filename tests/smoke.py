import os, socket, ssl, struct, subprocess, tempfile, threading, time

BIN = os.path.abspath(os.environ.get('PROXY_BIN', './target/debug/dpi-proxy'))

def listen():
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 0))
    s.listen(8)
    s.settimeout(10)
    return s, s.getsockname()[1]

def recv_exact(sock, size):
    buf = b''
    while len(buf) < size:
        chunk = sock.recv(size-len(buf))
        if not chunk: raise AssertionError(f'connection closed at {len(buf)}/{size}')
        buf += chunk
    return buf

def recv_header(sock):
    buf = b''
    while not buf.endswith(b'\r\n\r\n'):
        buf += recv_exact(sock, 1)
        if len(buf) > 65536: raise AssertionError('header too large')
    return buf

def origin_http(listener, expected):
    with listener:
        conn, _ = listener.accept()
        with conn:
            conn.settimeout(10)
            headers = recv_header(conn)
            assert headers.startswith(expected[0]), headers
            assert b'\r\nhoSt: ' in headers, headers
            body = recv_exact(conn, len(expected[1]))
            assert body == expected[1], (len(body), len(expected[1]))
            conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK')

def run_case(proxy_port, method, body=b''):
    listener, port = listen()
    origin = threading.Thread(target=origin_http, args=(listener, (method + b' /path?q=1 HTTP/1.1\r\n', body)), daemon=True)
    origin.start()
    with socket.create_connection(('127.0.0.1', proxy_port), timeout=10) as client:
        client.sendall(method + f' http://127.0.0.1:{port}/path?q=1 HTTP/1.1\r\nHost: ignored.example\r\nContent-Length: {len(body)}\r\n\r\n'.encode() + body)
        response = b''
        while True:
            part = client.recv(65536)
            if not part: break
            response += part
        assert b'200 OK' in response and response.endswith(b'OK'), response
    origin.join(10)
    assert not origin.is_alive(), 'origin stuck'

listener, proxy_port = listen()
listener.close()
config_dir = tempfile.TemporaryDirectory()
with open(os.path.join(config_dir.name, '.env'), 'w', encoding='utf-8') as config_file:
    config_file.write('DPI_PROXY_HOST=127.0.0.1\nDPI_PROXY_PORT=1\nDPI_PROXY_SPLIT_SNI=false\nDPI_PROXY_RETRY_ON_RESET=true\nDPI_PROXY_TIMEOUT_SECS=0.2\n')
environment = {key: value for key, value in os.environ.items() if not key.startswith('DPI_PROXY_')}
environment.update(DPI_PROXY_PORT=str(proxy_port), DPI_PROXY_SPLIT_SNI='true')
invalid = subprocess.run([BIN], cwd=config_dir.name, env={**environment, 'DPI_PROXY_PORT': 'not-a-port'}, capture_output=True, timeout=5)
assert invalid.returncode != 0 and b'DPI_PROXY_PORT' in invalid.stderr
invalid_bool = subprocess.run([BIN], cwd=config_dir.name, env={**environment, 'DPI_PROXY_SPLIT_SNI': 'maybe'}, capture_output=True, timeout=5)
assert invalid_bool.returncode != 0 and b'DPI_PROXY_SPLIT_SNI' in invalid_bool.stderr
invalid_arg = subprocess.run([BIN, '--help'], cwd=config_dir.name, env=environment, capture_output=True, timeout=5)
assert invalid_arg.returncode != 0 and b'command-line arguments' in invalid_arg.stderr
with tempfile.TemporaryDirectory() as bad_dir:
    with open(os.path.join(bad_dir, '.env'), 'w', encoding='utf-8') as config_file:
        config_file.write('DPI_PROXY_PORT=\"unterminated\n')
    malformed = subprocess.run([BIN], cwd=bad_dir, env=environment, capture_output=True, timeout=5)
    assert malformed.returncode != 0
print('Invalid environment, malformed dotenv, and command-line arguments rejected')
proc = subprocess.Popen([BIN], cwd=config_dir.name, env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
try:
    for _ in range(100):
        try:
            conn = socket.create_connection(('127.0.0.1', proxy_port), timeout=.1)
            conn.close()
            break
        except OSError:
            if proc.poll() is not None: raise RuntimeError(proc.stderr.read().decode())
            time.sleep(.05)
    else: raise RuntimeError('proxy did not listen')
    run_case(proxy_port, b'GET')
    print('HTTP GET passed')
    run_case(proxy_port, b'POST', b'a' * (1024*1024))
    print('HTTP 1 MiB POST passed')
    with socket.create_connection(('127.0.0.1', proxy_port), timeout=10) as client:
        client.sendall(b'POST http://example.com/ HTTP/1.1\r\nHost: example.com\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n')
        assert b' 400 ' in recv_header(client)
    print('Ambiguous HTTP framing rejected')


    target, target_port = listen()
    captured = []
    def read_tls():
        with target:
            peer, _ = target.accept()
            with peer:
                peer.settimeout(10)
                h1 = recv_exact(peer, 5)
                b1 = recv_exact(peer, int.from_bytes(h1[3:5], 'big'))
                h2 = recv_exact(peer, 5)
                b2 = recv_exact(peer, int.from_bytes(h2[3:5], 'big'))
                captured.append((h1, b1, h2, b2))
    thread = threading.Thread(target=read_tls, daemon=True)
    thread.start()
    with socket.create_connection(('127.0.0.1', proxy_port), timeout=10) as client:
        client.sendall(f'CONNECT 127.0.0.1:{target_port} HTTP/1.1\r\nHost: 127.0.0.1:{target_port}\r\n\r\n'.encode())
        assert b'200 ' in recv_header(client)
        context = ssl.create_default_context()
        incoming, outgoing = ssl.MemoryBIO(), ssl.MemoryBIO()
        tls = context.wrap_bio(incoming, outgoing, server_hostname='example.com')
        try: tls.do_handshake()
        except ssl.SSLWantReadError: pass
        client.sendall(outgoing.read())
        thread.join(10)
    assert captured, 'origin did not receive two TLS records'
    h1, b1, h2, b2 = captured[0]
    assert h1[0] == 22 and h2[0] == 22 and b'example.com' in b1 + b2
    assert b1.endswith(b'e') and b2.startswith(b'xample.com'), (b1[-20:], b2[:20])
    print(f'HTTPS CONNECT ClientHello split passed ({len(b1)} + {len(b2)} bytes)')

    # A reset or timeout before the first reply retries without splitting.
    for failure in ('reset', 'timeout'):
        retry_target, retry_port = listen()
        retry_connections = []
        def fail_then_reply():
            with retry_target:
                first, _ = retry_target.accept()
                with first:
                    first.settimeout(10)
                    retry_connections.append(recv_exact(first, 5))
                    if failure == 'reset':
                        first.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
                        first.close()
                    second, _ = retry_target.accept()
                    with second:
                        second.settimeout(10)
                        h = recv_exact(second, 5)
                        retry_connections.append(h)
                        recv_exact(second, int.from_bytes(h[3:5], 'big'))
                        second.sendall(b'RETRY-OK')
        retry_thread = threading.Thread(target=fail_then_reply, daemon=True)
        retry_thread.start()
        with socket.create_connection(('127.0.0.1', proxy_port), timeout=10) as client:
            client.sendall(f'CONNECT 127.0.0.1:{retry_port} HTTP/1.1\r\nHost: 127.0.0.1:{retry_port}\r\n\r\n'.encode())
            assert b'200 ' in recv_header(client)
            incoming, outgoing = ssl.MemoryBIO(), ssl.MemoryBIO()
            tls = ssl.create_default_context().wrap_bio(incoming, outgoing, server_hostname='example.com')
            try: tls.do_handshake()
            except ssl.SSLWantReadError: pass
            started = time.monotonic()
            client.sendall(outgoing.read())
            assert recv_exact(client, 8) == b'RETRY-OK'
            if failure == 'timeout':
                assert time.monotonic() - started < 2.5, 'dotenv timeout was not used'
        retry_thread.join(10)
        assert len(retry_connections) == 2 and not retry_thread.is_alive()
        assert int.from_bytes(retry_connections[1][3:5], 'big') > int.from_bytes(retry_connections[0][3:5], 'big')
        print(f'{failure} triggers one retry without splitting')
finally:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        raise AssertionError('proxy did not stop on SIGTERM')
    assert proc.returncode == 0, f'proxy exited with {proc.returncode}'
    config_dir.cleanup()

# Verify both switches by observing what reaches the upstream server.
for split, retry in ((False, True), (True, False)):
    reservation, port = listen()
    reservation.close()
    with tempfile.TemporaryDirectory() as empty_dir:
        settings = {key: value for key, value in os.environ.items() if not key.startswith('DPI_PROXY_')}
        settings.update(DPI_PROXY_HOST='127.0.0.1', DPI_PROXY_PORT=str(port),
                        DPI_PROXY_SPLIT_SNI=str(split).lower(),
                        DPI_PROXY_RETRY_ON_RESET=str(retry).lower(),
                        DPI_PROXY_TIMEOUT_SECS='0.2')
        process = subprocess.Popen([BIN], cwd=empty_dir, env=settings, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                try:
                    ready = socket.create_connection(('127.0.0.1', port), timeout=.1)
                    ready.close()
                    break
                except OSError:
                    if process.poll() is not None: raise RuntimeError(process.stderr.read().decode())
                    time.sleep(.05)
            else: raise RuntimeError('proxy did not listen')
            target, target_port = listen()
            with target, socket.create_connection(('127.0.0.1', port), timeout=5) as client:
                client.sendall(f'CONNECT 127.0.0.1:{target_port} HTTP/1.1\r\nHost: 127.0.0.1:{target_port}\r\n\r\n'.encode())
                assert b'200 ' in recv_header(client)
                peer, _ = target.accept()
                with peer:
                    peer.settimeout(5)
                    incoming, outgoing = ssl.MemoryBIO(), ssl.MemoryBIO()
                    tls = ssl.create_default_context().wrap_bio(incoming, outgoing, server_hostname='example.com')
                    try: tls.do_handshake()
                    except ssl.SSLWantReadError: pass
                    hello = outgoing.read()
                    client.sendall(hello)
                    header = recv_exact(peer, 5)
                    payload = recv_exact(peer, int.from_bytes(header[3:5], 'big'))
                    if split:
                        assert payload.endswith(b'e'), 'split setting was not applied'
                    else:
                        assert header + payload == hello, 'disabled split changed the ClientHello'
                    peer.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
                target.settimeout(0.6)
                try:
                    unexpected, _ = target.accept()
                except socket.timeout:
                    pass
                else:
                    unexpected.close()
                    raise AssertionError('proxy retried with splitting or retries disabled')
        finally:
            process.terminate()
            process.wait(timeout=5)
            assert process.returncode == 0
print('Environment switches disable splitting and retries')
