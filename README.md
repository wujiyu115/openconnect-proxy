# openconnect + gost

本镜像基于 [Debian bookworm slim](https://www.debian.org/)，在同一个容器里同时提供：

- [openconnect 客户端](http://www.infradead.org/openconnect/)（来自 Debian 软件源，带 pulse/juniper 协议支持），负责建立 VPN 隧道 `tun0`
- [gost](https://github.com/ginuerzh/gost)（构建时从 GitHub releases 拉取最新的 linux_amd64 版本），负责对外提供代理
- `ocproxy`、`iproute2`、`curl`、`wget`、`net-tools`、`telnet`、`ping`、`procps` 等排障工具

容器启动后默认只暴露内部 HTTP 代理端口 `8988`；需要 8888（http/https）和 8889（socks5）这类对外入口时，
用 `GOST_LISTENERS` 自行声明并映射端口（见下文）。

镜像地址（Docker Hub）：
https://hub.docker.com/r/wujiyu115/openconnect-proxy

## 本仓库相对上游镜像的改动

在上游 `openconnect-proxy` 的基础上，本仓库做了这些增强：

| 改动 | 说明 |
|------|------|
| 基础镜像升级 | `debian:buster-slim`（已 EOL，apt 源 404）→ `debian:bookworm-slim` |
| 策略路由修复 | 安装 `iproute2`，VPN 连上后用 `table 100` + `ip rule` 让容器的**回包走 Docker 网关**，解决「VPN 连上后宿主机通过端口映射访问不到代理」的问题 |
| gost 内置 | 不再需要单独的 gost 入口容器，通过 `GOST_LISTENERS` 配置监听器，gost 与 VPN 共享网络命名空间 |
| BBR 检测 | 启动时检查拥塞控制算法，未启用时给出开启提示 |
| 防流量泄漏 | gost 等到 `tun0` 真正建立后才启动，避免 openconnect 连接过程中流量直连 |
| 自动重连 | openconnect 进程退出后 60 秒自动重启 |

策略路由的完整原理与流量走向，见 [docs/network-topology.md](docs/network-topology.md)。

## 目录结构

```
.
├── README.md                     # 本文档
├── LICENSE                       # GPL-3.0
├── build/
│   ├── Dockerfile                # 两阶段构建：先下载 gost，再组装运行镜像
│   └── entrypoint.sh             # 入口脚本：BBR 检测 / 策略路由 / 启动 openconnect 与 gost
├── docs/
│   └── network-topology.md       # 网络拓扑与端口映射问题原理
└── .github/workflows/
    └── docker-image.yml          # CI：推送 master 或打 tag 时构建并推送到 Docker Hub
```

# 环境要求

如果你不想在命令行里手写环境变量，可以把变量写进 `.env` 文件：

	OPENCONNECT_URL=<网关地址>
	OPENCONNECT_USER=<用户名>
	OPENCONNECT_PASSWORD=<密码>
	OPENCONNECT_OPTIONS=--authgroup <VPN 组> \
		--servercert <VPN 服务器证书> --protocol=<协议> \
		--reconnect-timeout 86400

_变量值不要加引号！_

可用参数请参考 [openconnect 官方文档](https://www.infradead.org/openconnect/manual.html)。

你可以把密码写进 `.env`，也可以不设置 `OPENCONNECT_PASSWORD`，
这样容器启动时会交互式提示你输入密码。

此外还可以选择性地设置多因素认证验证码：

	OPENCONNECT_MFA_CODE=<多因素认证验证码>

## 环境变量一览

| 变量 | 是否必需 | 说明 |
|------|----------|------|
| `OPENCONNECT_URL` | 是 | VPN 网关地址，如 `vpn.example.com/group` |
| `OPENCONNECT_USER` | 是 | VPN 用户名 |
| `OPENCONNECT_PASSWORD` | 否 | VPN 密码；不设置则容器启动时交互式提示输入（需 `docker run -it`） |
| `OPENCONNECT_MFA_CODE` | 否 | 多因素认证验证码，需与 `OPENCONNECT_PASSWORD` 同时设置才生效 |
| `OPENCONNECT_OPTIONS` | 否 | 透传给 openconnect 的额外参数，如 `--authgroup`、`--servercert`、`--protocol`、`--reconnect-timeout 86400` |
| `GOST_LISTENERS` | 否 | gost 监听器（空格分隔，gost v3 语法），默认 `-L=http://:8988`；设为空则不启动 gost |

## 运行前提

- 宿主机内核需要 `tun` 模块：`lsmod | grep tun`，没有就 `modprobe tun`
- 容器需要创建隧道和改路由的权限，建议 `--privileged`；最小权限组合为
  `--cap-add NET_ADMIN --device /dev/net/tun`
- 如果要通过端口映射从宿主机/局域网访问代理，请确认容器使用桥接网络而不是 `--net host`（`--net host` 下无需映射端口）

# 前台运行容器

以前台方式启动容器（默认只开了内部 HTTP 代理 8988）：

	docker run -it --rm --privileged --env-file=.env \
	  -p 8988:8988 wujiyu115/openconnect-proxy:latest

如果想额外对外提供 http/https 代理 8888 和 socks5 代理 8889，把监听器一起传进去并映射端口：

	docker run -it --rm --privileged --env-file=.env \
	  -e GOST_LISTENERS="-L=http://:8888 -L=socks5://:8889 -L=http://:8988" \
	  -p 8888:8888 -p 8889:8889 -p 8988:8988 \
	  wujiyu115/openconnect-proxy:latest

代理分别监听 8888（http/https）和 8889（socks）。要让宿主机能访问这些代理端口，
可以使用 `--net host`，或者用 `-p <本地端口>:<容器端口>` 做端口映射。

如果不使用 `.env` 文件，也可以在 `docker run` 时用 `-e` 直接传环境变量：

	docker run … -e OPENCONNECT_URL=vpn.gateway.com/example \
	-e OPENCONNECT_OPTIONS='<Openconnect 参数>' \
	-e OPENCONNECT_USER=<用户名> …

# 后台运行容器

加上 `-d` 参数即以守护进程模式（后台）启动：

	docker run -d -it --rm …

后台模式下可以用 `docker logs` 查看 stderr 日志：

	docker logs `docker ps|grep "wujiyu115/openconnect-proxy"|awk -F' ' '{print $1}'`

# 配合 docker-compose 使用

	vpn:
	  container_name: openconnect_vpn
	  image: wujiyu115/openconnect-proxy:latest
	  privileged: true
	  env_file:
	    - .env
	  environment:
	    - GOST_LISTENERS=-L=http://:8888 -L=socks5://:8889 -L=http://:8988
	  ports:
	    - 8888:8888
	    - 8889:8889
	    - 8988:8988
	  networks:
	    - mynetwork

同样把 _openconnect_ 需要的环境变量写进 `.env` 文件（也可以指定别的文件）。
`GOST_LISTENERS` 里声明的监听端口必须与 `ports` 里的映射一一对应，
否则容器里没有服务监听，映射自然也不通。

如果你希望宿主机能访问 VPN，就把容器里配置的端口映射到宿主机端口；
否则只有同一 docker 网络内的容器才能访问这些代理端口。
`privileged: true` 已包含 `NET_ADMIN`，如果你想收紧权限，可以去掉 `privileged`、
只保留 `cap_add: [NET_ADMIN]` 并为服务补上 `devices: [/dev/net/tun]`。

# 让流量走 VPN 容器

假设你已经按上面的方式定义了 `vpn` 容器，那么给其他容器加上 `network_mode` 选项即可：

	depends_on:
	  - vpn
	network_mode: "service:vpn"

注意：`networks`、`extra_hosts` 等配置与 `network_mode` 是互斥的，不能同时使用！

# 配置代理

容器通过 _openconnect_ 连上 VPN 之后，你就可以把浏览器或其他软件配置为使用其中一个代理
（8888 是 http/https，8889 是 socks）。注意这两个端口需要你像上面那样
通过 `GOST_LISTENERS` 显式开启；没开的话只有默认的 8988（HTTP）可用。

例如 FoxyProxy 就是一个合适的浏览器插件（Firefox、Chrome 都有）。

你也可以设置环境变量：

	export http_proxy="http://127.0.0.1:8888/"
	export https_proxy="http://127.0.0.1:8888/"

composer、git（如果你不用 git+ssh 协议，见下文）等工具都会读取这些变量。

# 通过代理使用 ssh

你需要 nc（netcat）、corkscrew 或类似的工具才能实现。

遗憾的是某些 git 客户端（例如 Gitkraken）不会读取 ssh config 里的配置，
导致你无法从那些只能通过 VPN 访问（仅 DNS 可达）的仓库拉取/推送代码。

## nc（netcat、ncat）

在 `~/.ssh/config` 中设置 `ProxyCommand`：

	Host <主机名>
		ProxyCommand            nc -x 127.0.0.1:8889 %h %p

或者（取决于你的 ncat 版本）：

	Host <主机名>
		ProxyCommand            ncat --proxy 127.0.0.1:8889 --proxy-type socks5 %h %p

这样连接就会走代理。上面的例子适用于使用 ssh key 的 git。

## corkscrew

另一种选择是 _corkscrew_（例如在 macOS 上用 `brew install corkscrew` 安装）：

	Host <主机名>
		ProxyCommand            corkscrew 127.0.0.1 8888 %h %p

# 把入口代理合并进本容器（默认行为）

容器已经在 openconnect 旁边运行了 gost，因此不再需要单独的 gost 入口容器。
本容器内启动的 gost 与 VPN 共享同一个网络命名空间，出站流量会跟随 VPN 默认路由，
无需再用 `-F` 转发。

监听器通过 `GOST_LISTENERS` 配置（空格分隔，gost v3 语法）。
默认只暴露内部的 HTTP 代理 8988：

	-e GOST_LISTENERS="-L=http://:8988"

如果要替代原来独立的 gost 入口容器（HTTP 代理 + shadowsocks + 内部代理），
把全部监听器都传进去，并发布对应的端口：

	docker run -d --privileged \
	  --sysctl net.ipv4.tcp_congestion_control=bbr \
	  --env-file .env \
	  -e GOST_LISTENERS="-L=:8887 -L=ss://chacha20-ietf-poly1305:PASSWORD@:8443 -L=http://:8988" \
	  -p 8887:8887 -p 8888:8443 -p 8988:8988 \
	  wujiyu115/openconnect-proxy:latest

上面例子中 `-p 8888:8443` 表示宿主机的 8888 端口转发到容器里的 8443（shadowsocks）监听端口，
可按自己的端口规划调整；`ss://` 后面的密码请换成你自己的强密码。

gost 只有在隧道（`tun0`）建立之后才会启动，因此 openconnect 连接过程中不会有流量直连泄漏。

# BBR 拥塞控制（推荐）

容器启动时会检测内核的拥塞控制算法，并打印以下三种提示之一：

- `BBR 拥塞控制已启用`：无需处理
- `警告：内核支持 BBR 但未启用…`：按下面的命令开启即可
- `宿主机内核不支持 BBR…`：先在宿主机 `modprobe tcp_bbr`，并把 `tcp_bbr` 写入 `/etc/modules-load.d/`

启用方式（先在宿主机设置默认队列算法，再给容器传 sysctl）：

	sudo sysctl -w net.core.default_qdisc=fq
	sudo sysctl -w net.ipv4.tcp_congestion_control=bbr

	docker run -d --privileged \
	  --sysctl net.ipv4.tcp_congestion_control=bbr \
	  --env-file .env wujiyu115/openconnect-proxy:latest

注意：`net.core.default_qdisc` 是宿主机级别的参数，不能从容器内设置；
容器里只需要 `net.ipv4.tcp_congestion_control=bbr`。想永久生效把两行写进
`/etc/sysctl.d/99-bbr.conf`。

# 验证与排障

## 确认隧道和代理是否正常

	docker exec -it <容器名> ip route | grep tun0     # 看到 tun0 的默认路由说明 VPN 已连上
	docker exec -it <容器名> ip rule                  # 查看策略规则（应有 from <容器 IP> lookup 100）
	docker exec -it <容器名> ip route show table 100  # 回包专用路由表
	docker exec -it <容器名> sh                       # 进容器后用 curl / nc 手动测连通性

在宿主机或局域网机器上验证代理是否可用（以 8988 为例）：

	curl -x http://192.168.31.139:8988 https://ifconfig.me   # 应返回 VPN 出口 IP
	curl --socks5 127.0.0.1:8889 https://ifconfig.me         # socks5 入口（如果开了）

## 查看日志

	docker logs -f <容器名>

日志里的关键行：`VPN 连接前的默认网关`、`策略路由：...`、`VPN 隧道已建立`、`正在启动 gost`，
以及异常时的 `openconnect 已退出，60 秒后重启...`。

## 常见问题

| 现象 | 排查方向 |
|------|----------|
| 宿主机/局域网访问端口映射不通，容器内 `curl 127.0.0.1:8988` 却正常 | 这就是策略路由要解决的问题；确认 `ip rule` 里有 `from <容器 IP> lookup 100`，且 `ip route show table 100` 有默认路由 |
| `docker logs` 里一直是 `Waiting for VPN tunnel...` | VPN 没连上：检查网关地址、账号密码、`--servercert`/`--authgroup` 等 `OPENCONNECT_OPTIONS`，以及宿主机 `tun` 模块是否加载 |
| 容器启动后立刻退出 | 设置了 `OPENCONNECT_PASSWORD` 为空又没加 `-it`，导致 openconnect 无法交互式输入密码 |
| 映射了 8888/8889 但还是不通 | 默认只监听 8988，需要在 `GOST_LISTENERS` 里显式声明 8888/8889 并重启容器 |
| 能连代理但不能解析域名 | 隧道 DNS 未下发；可在 `OPENCONNECT_OPTIONS` 里加 `--set-dns`/`--script` 相关参数，或手动在容器 `/etc/resolv.conf` 指向 VPN DNS |
| openconnect 反复退出重启 | 看日志里的 openconnect 报错（证书、鉴权组、双因素过期等），容器会每 60 秒重试一次 |

# 构建与发布

## 本地构建

	docker build -f build/Dockerfile -t wujiyu115/openconnect-proxy:custom ./build

构建时会从 GitHub releases API 拉取最新 gost（`linux_amd64`）。如果构建环境需要走代理，
可以加上 `--build-arg` 或配置 docker daemon 的代理；修改 `SPRUCE_TYPE` 可切换平台。

## CI 自动发布

`.github/workflows/docker-image.yml` 会在以下时机构建并推送到 Docker Hub：

- 向 `master` 分支 push
- 打任何 `*` tag

需要在仓库 Settings → Secrets 里配置：

| Secret | 用途 |
|--------|------|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名（同时用作镜像命名空间） |
| `DOCKERHUB_TOKEN` | Docker Hub 访问令牌 |

# 安全注意事项

- `.env` 已被 `.gitignore` 忽略，不要把账号密码提交到仓库
- `--privileged` 权限很大；如果不需要修改宿主网络，优先用 `--cap-add NET_ADMIN --device /dev/net/tun`
- 代理端口没有鉴权，不要直接暴露到公网；对外使用请配合防火墙或反向代理加认证
- shadowsocks 监听器的密码请在 `GOST_LISTENERS` 里使用强密码，并避免写进会公开的 compose 文件

# 许可证

本项目使用 GPL-3.0，详见 [LICENSE](LICENSE)。
