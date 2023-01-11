FROM alpine:latest

RUN apk --no-cache add privoxy

CMD /usr/sbin/privoxy --no-daemon /etc/privoxy/config

EXPOSE 8118