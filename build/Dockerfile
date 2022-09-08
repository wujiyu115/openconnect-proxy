ARG ALPINE_VERSION=latest

# Set gost vars
ARG GOST_FILE=gost-linux-amd64-2.11.4
ARG GOST_URL=https://github.com/ginuerzh/gost/releases/download/v2.11.4/${GOST_FILE}.gz
# Build gost
FROM alpine:${ALPINE_VERSION} as builder

ARG GOST_URL
ARG GOST_FILE

ENV GOST_URL=${GOST_URL}\
    GOST_FILE=${GOST_FILE}

# Change working dir.
WORKDIR /tmp

# Add gost repo archive
RUN apk add --no-cache \
    wget \
    gzip && \
    wget ${GOST_URL} && \
    gzip -d ${GOST_FILE}.gz && \
    mv ${GOST_FILE} gost && \
    chmod +x gost

FROM alpine:${ALPINE_VERSION}

COPY --from=builder /tmp/gost /usr/local/bin/gost

RUN apk add --no-cache \
    openconnect

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 8888 8889

ENTRYPOINT ["/entrypoint.sh"]