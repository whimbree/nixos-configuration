FROM serjs/go-socks5-proxy as builder

FROM alpine:3.14
RUN apk add --no-cache curl
COPY --from=builder /socks5 /
ENTRYPOINT ["/socks5"]