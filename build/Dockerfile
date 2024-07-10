# Set gost vars
# Build gost
FROM debian:buster-slim as builder

ENV SPRUCE_TYPE=linux_amd64v3
# Change working dir.
WORKDIR /tmp

# Add gost repo archive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*
    
    
RUN GOST_URL=$(curl -fsSL https://api.github.com/repos/go-gost/gost/releases |jq -r "first(.[]) | .assets[] | select(.name | test(\"${SPRUCE_TYPE}\")) | .browser_download_url") \
    GOST_FILE=${GOST_URL##*/} &&\ 
    wget ${GOST_URL} && \
    tar -zxvf ${GOST_FILE} && \
    chmod +x gost

FROM debian:buster-slim

COPY --from=builder /tmp/gost /usr/local/bin/gost

RUN apt-get update && \    
    apt-get install -y --no-install-recommends \
    openconnect \
    wget \
    curl 

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 8888 8889

ENTRYPOINT ["/entrypoint.sh"]