FROM ghcr.io/caddijp/rust-musl-builder/rust-musl-builder:1.68.0-llvm-cov AS build

RUN git clone https://github.com/nextcloud/notify_push /home/rust/notify_push

WORKDIR /home/rust/notify_push

RUN cargo build --release

FROM scratch

COPY --from=build /home/rust/notify_push/target/x86_64-unknown-linux-musl/release/notify_push /
EXPOSE 7867

CMD ["/notify_push"]