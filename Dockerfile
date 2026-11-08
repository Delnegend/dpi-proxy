FROM rust:1.98.1-trixie AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --locked

FROM debian:trixie-slim
COPY --from=build /src/target/release/dpi-proxy /usr/local/bin/dpi-proxy
USER 10001:10001
ENV DPI_PROXY_HOST=0.0.0.0
EXPOSE 18118
ENTRYPOINT ["/usr/local/bin/dpi-proxy"]
