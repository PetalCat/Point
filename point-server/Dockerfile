FROM rust:1.88-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock* ./
COPY src/ src/
COPY migrations/ migrations/
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/target/release/point-server .
COPY migrations/ migrations/
VOLUME /data
EXPOSE 8080
ENV DATABASE_URL=sqlite:/data/point.db?mode=rwc
ENV LISTEN=0.0.0.0:8080
ENV DOMAIN=point.petalcat.dev
ENV OPEN_REGISTRATION=true
CMD ["./point-server"]
