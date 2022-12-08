FROM lscr.io/linuxserver/nextcloud:latest

ADD repositories /etc/apk
RUN apk --update upgrade
RUN apk add --no-cache --upgrade php8-pdlib