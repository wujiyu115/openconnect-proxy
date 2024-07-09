ARG ALPINE_VERSION=latest

# Set gost vars
# Build gost
FROM alpine:${ALPINE_VERSION} as builder

ENV SPRUCE_TYPE=linux_amd64v3
# Change working dir.
WORKDIR /tmp

# Add gost repo archive
RUN apk add --no-cache \
    wget \
    curl \
    jq
    
RUN GOST_URL=$(curl -fsSL https://api.github.com/repos/go-gost/gost/releases |jq -r "first(.[]) | .assets[] | select(.name | test(\"${SPRUCE_TYPE}\")) | .browser_download_url") \
    GOST_FILE=${GOST_URL##*/} &&\ 
    wget ${GOST_URL} && \
    tar -zxvf ${GOST_FILE} && \
    chmod +x gost

FROM alpine:${ALPINE_VERSION}

COPY --from=builder /tmp/gost /usr/local/bin/gost

RUN apk add --no-cache \
    openconnect

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 8888 8889

ENTRYPOINT ["/entrypoint.sh"]