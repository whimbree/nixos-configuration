FROM ekidd/rust-musl-builder AS build

RUN git clone https://github.com/nextcloud/notify_push /home/rust/notify_push

WORKDIR /home/rust/notify_push

RUN cargo build --release

FROM scratch

COPY --from=build /home/rust/notify_push/target/x86_64-unknown-linux-musl/release/notify_push /
EXPOSE 7867

CMD ["/notify_push"]