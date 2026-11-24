# openconnect + gost

本镜像在一个极小的 [alpine linux](https://www.alpinelinux.org/) 镜像（约 20 MB）里同时包含
[openconnect 客户端](http://www.infradead.org/openconnect/)（8.04 版本，带 pulse/juniper 支持）以及
[gost](https://github.com/ginuerzh/gost)，提供 http/https 代理（默认端口 8888）和
socks5 代理（默认端口 8889）。

镜像地址（Docker Hub）：
https://hub.docker.com/r/wujiyu115/openconnect-proxy

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

# 前台运行容器

以前台方式启动容器：

	docker run -it --rm --privileged --env-file=.env \
	  -p 8888:8888 -p 8889:8889 wujiyu115/openconnect-proxy:latest

代理分别监听 8888（http/https）和 8889（socks）。要让宿主机能访问这些代理端口，
可以使用 `--net host`，或者用 `-p <本地端口>:8888 -p <本地端口>:8889` 做端口映射。

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
	  ports:
	    - 8888:8888
	    - 8889:8889
	  cap_add:
	    - NET_ADMIN
	  networks:
	    - mynetwork

同样把 _openconnect_ 需要的环境变量写进 `.env` 文件（也可以指定别的文件）。
如果你希望宿主机能访问 VPN，就把容器里配置的端口映射到宿主机端口；
否则只有同一 docker 网络内的容器才能访问这些代理端口。

# 让流量走 VPN 容器

假设你已经按上面的方式定义了 `vpn` 容器，那么给其他容器加上 `network_mode` 选项即可：

	depends_on:
	  - vpn
	network_mode: "service:vpn"

注意：`networks`、`extra_hosts` 等配置与 `network_mode` 是互斥的，不能同时使用！

# 配置代理

容器通过 _openconnect_ 连上 VPN 之后，你就可以把浏览器或其他软件配置为使用其中一个代理
（8888 是 http/https，8889 是 socks）。

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

gost 只有在隧道（`tun0`）建立之后才会启动，因此 openconnect 连接过程中不会有流量直连泄漏。

# 构建

你也可以自己构建镜像：

	docker build -f build/Dockerfile -t wujiyu115/openconnect-proxy:custom ./build
