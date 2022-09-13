ARG ALPINE_VERSION=latest

# Set gost vars
# Build gost
FROM alpine:${ALPINE_VERSION} as builder

ENV SPRUCE_TYPE=linux-amd64
# Change working dir.
WORKDIR /tmp

# Add gost repo archive
RUN apk add --no-cache \
    wget \
    curl \
    jq \
    gzip && \
    GOST_URL=$(curl -fsSL https://api.github.com/repos/go-gost/gost/releases |jq -r "first(.[]) | .assets[] | select(.name | test(\"${SPRUCE_TYPE}\")) | .browser_download_url") \
    GOST_FILE=${GOST_URL##*/} \ 
    GOST_FILE_NO_EXT=${GOST_FILE%.*} \
    wget ${GOST_URL} && \
    gzip -d ${GOST_FILE} && \
    mv ${GOST_FILE_NO_EXT} gost && \
    chmod +x gost

FROM alpine:${ALPINE_VERSION}

COPY --from=builder /tmp/gost /usr/local/bin/gost

RUN apk add --no-cache \
    openconnect

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 8888 8889

ENTRYPOINT ["/entrypoint.sh"]