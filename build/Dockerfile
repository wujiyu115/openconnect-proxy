# 设置 gost 相关变量
# 构建阶段：编译/下载 gost
FROM debian:bookworm-slim AS builder
ENV SPRUCE_TYPE=linux_amd64.tar
# 切换工作目录
WORKDIR /tmp
# 安装构建所需的软件包
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    curl \
    jq \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 获取最新 gost release 的下载地址并下载 tar 包
RUN GOST_URL=$(curl -kfsSL https://api.github.com/repos/go-gost/gost/releases | jq -r "first(.[]) | .assets[] | select(.name | test(\"${SPRUCE_TYPE}\")) | .browser_download_url") && \
    GOST_FILE=$(basename "${GOST_URL}") && \
    wget --no-check-certificate  "${GOST_URL}" && \
    tar -zxvf "${GOST_FILE}" && \
    chmod +x gost && \
    mv gost /usr/local/bin/gost

FROM debian:bookworm-slim
# 从构建阶段复制 gost 可执行文件
COPY --from=builder /usr/local/bin/gost /usr/local/bin/gost
# 安装运行时所需的软件包
RUN apt-get update && \    
    apt-get install -y --no-install-recommends \
    ca-certificates \
    procps \
    iputils-ping \
    wget \
    curl \
    telnet \
    net-tools \
    iproute2 \
    openconnect \
    ocproxy \
    && rm -rf /var/lib/apt/lists/*
# 复制入口脚本并设置可执行权限
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
# 暴露端口：gost 内部监听端口（可通过 GOST_LISTENERS 覆盖）
EXPOSE 8988 8887 8443
# 设置入口脚本
ENTRYPOINT ["/entrypoint.sh"]
