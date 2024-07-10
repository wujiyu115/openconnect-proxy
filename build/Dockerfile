# Set gost vars
# Build gost
FROM debian:buster-slim as builder
ENV SPRUCE_TYPE=linux_amd64v3
# Change working dir.
WORKDIR /tmp
# Add required packages for building
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Get the latest gost release URL and download the tar file
RUN GOST_URL=$(curl -fsSL https://api.github.com/repos/go-gost/gost/releases | jq -r "first(.[]) | .assets[] | select(.name | test(\"${SPRUCE_TYPE}\")) | .browser_download_url") && \
    GOST_FILE=$(basename "${GOST_URL}") && \
    wget "${GOST_URL}" && \
    tar -zxvf "${GOST_FILE}" && \
    chmod +x gost && \
    mv gost /usr/local/bin/gost

FROM debian:buster-slim
# Copy the gost binary from the builder stage
COPY --from=builder /usr/local/bin/gost /usr/local/bin/gost
# Install required packages
RUN apt-get update && \    
    apt-get install -y --no-install-recommends \
    openconnect \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*
# Copy entrypoint script and set permissions
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
# Expose ports for gost and openconnect
EXPOSE 8888 8889
# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
