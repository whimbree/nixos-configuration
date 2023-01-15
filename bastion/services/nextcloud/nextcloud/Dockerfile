FROM lscr.io/linuxserver/nextcloud:latest

RUN echo -e "http://dl-cdn.alpinelinux.org/alpine/edge/main\nhttp://dl-cdn.alpinelinux.org/alpine/edge/community\nhttp://dl-cdn.alpinelinux.org/alpine/edge/testing" > /etc/apk/repositories
RUN apk --update upgrade
RUN apk add --no-cache --upgrade php8-pdlib