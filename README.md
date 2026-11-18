# openconnect + gost

This Docker image contains an [openconnect client](http://www.infradead.org/openconnect/) (version 8.04 with pulse/juniper support) and the [gost](https://github.com/ginuerzh/gost) for http/https connections (default on port 8888) and  socks5 connections (default on port 8889) in a very small [alpine linux](https://www.alpinelinux.org/) image (around 20 MB).

You can find the image on docker hub:
https://hub.docker.com/r/wujiyu115/openconnect-proxy

# Requirements

If you don't want to set the environment variables on the command line
set the environment variables in a `.env` file:

	OPENCONNECT_URL=<Gateway URL>
	OPENCONNECT_USER=<Username>
	OPENCONNECT_PASSWORD=<Password>
	OPENCONNECT_OPTIONS=--authgroup <VPN Group> \
		--servercert <VPN Server Certificate> --protocol=<Protocol> \
		--reconnect-timeout 86400

_Don't use quotes around the values!_

See the [openconnect documentation](https://www.infradead.org/openconnect/manual.html) for available options. 

Either set the password in the `.env` file or leave the variable `OPENCONNECT_PASSWORD` unset, so you get prompted when starting up the container.

Optionally set a multi factor authentication code:

	OPENCONNECT_MFA_CODE=<Multi factor authentication code>

# Run container in foreground

To start the container in foreground run:

	docker run -it --rm --privileged --env-file=.env \
	  -p 8888:8888 -p 8889:8889 wujiyu115/openconnect-proxy:latest

The proxies are listening on ports 8888 (http/https) and 8889 (socks). Either use `--net host` or `-p <local port>:8888 -p <local port>:8889` to make the proxy ports available on the host.

Without using a `.env` file set the environment variables on the command line with the docker run option `-e`:

	docker run … -e OPENCONNECT_URL=vpn.gateway.com/example \
	-e OPENCONNECT_OPTIONS='<Openconnect Options>' \
	-e OPENCONNECT_USER=<Username> …

# Run container in background

To start the container in daemon mode (background) set the `-d` option:

	docker run -d -it --rm …

In daemon mode you can view the stderr log with `docker logs`:

	docker logs `docker ps|grep "wujiyu115/openconnect-proxy"|awk -F' ' '{print $1}'`

# Use container with docker-compose

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


Set the environment variables for _openconnect_ in the `.env` file again (or specify another file) and 
map the configured ports in the container to your local ports if you want to access the VPN 
on the host too when running your containers. Otherwise only the docker containers in the same
network have access to the proxy ports.

# Route traffic through VPN container

Let's say you have a `vpn` container defined as above, then add `network_mode` option to your other containers:

	depends_on:
	  - vpn
	network_mode: "service:vpn"

Keep in mind that `networks`, `extra_hosts`, etc. and `network_mode` are mutually exclusive!

# Configure proxy

The container is connected via _openconnect_ and now you can configure your browser
and other software to use one of the proxies (8888 for http/https or 8889 for socks).

For example FoxyProxy (available for Firefox, Chrome) is a suitable browser extension.

You may also set environment variables:

	export http_proxy="http://127.0.0.1:8888/"
	export https_proxy="http://127.0.0.1:8888/"

composer, git (if you don't use the git+ssh protocol, see below) and others use these.

# ssh through the proxy

You need nc (netcat), corkscrew or something similar to make this work.

Unfortunately some git clients (e.g. Gitkraken) don't use the settings from ssh config
and you can't pull/push from a repository that's reachable (DNS resolution) only through VPN.

## nc (netcat, ncat)

Set a `ProxyCommand` in your `~/.ssh/config` file like

	Host <hostname>
		ProxyCommand            nc -x 127.0.0.1:8889 %h %p

or (depending on your ncat version)

	Host <hostname>
		ProxyCommand            ncat --proxy 127.0.0.1:8889 --proxy-type socks5 %h %p

and your connection will be passed through the proxy.
The above example is for using git with ssh keys.

## corkscrew 

An alternative is _corkscrew_ (e.g. install with `brew install corkscrew` on mac OS)

	Host <hostname>
		ProxyCommand            corkscrew 127.0.0.1 8888 %h %p

# Merge the entry proxy into this container (default)

The container already runs gost next to openconnect, so a separate gost entry
container is not needed. gost started inside this container shares the VPN
network namespace, so its outbound traffic follows the VPN default route - no
`-F` forwarder is required.

Listeners are configured with `GOST_LISTENERS` (space separated, gost v3 syntax).
The default only exposes the internal HTTP proxy on 8988:

	-e GOST_LISTENERS="-L=http://:8988"

To replace a standalone gost entry container (HTTP proxy + shadowsocks + internal
proxy), pass all listeners and publish the matching ports:

	docker run -d --privileged \
	  --sysctl net.ipv4.tcp_congestion_control=bbr \
	  --env-file .env \
	  -e GOST_LISTENERS="-L=:8887 -L=ss://chacha20-ietf-poly1305:PASSWORD@:8443 -L=http://:8988" \
	  -p 8887:8887 -p 8888:8443 -p 8988:8988 \
	  wujiyu115/openconnect-proxy:latest

gost is only started after the tunnel (`tun0`) is up, so no traffic can leak
out directly while openconnect is still connecting.

# Build

You can build the container yourself with

	docker build -f build/Dockerfile -t wujiyu115/openconnect-proxy:custom ./build

