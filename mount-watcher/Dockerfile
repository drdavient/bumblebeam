FROM alpine:3.20

RUN apk add --no-cache curl util-linux

COPY mount-rebooter.sh /usr/local/bin/mount-rebooter.sh

RUN chmod +x /usr/local/bin/mount-rebooter.sh

ENTRYPOINT ["/usr/local/bin/mount-rebooter.sh"]
