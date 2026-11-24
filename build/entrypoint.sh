#!/bin/sh

# 检查 BBR 拥塞控制状态
if grep -q bbr /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null; then
  echo "BBR 拥塞控制已启用"
elif grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
  echo "警告：内核支持 BBR 但未启用。请在 docker run 时加上：--sysctl net.ipv4.tcp_congestion_control=bbr（并在宿主机上设置 net.core.default_qdisc=fq）"
else
  echo "宿主机内核不支持 BBR（请先在宿主机执行 modprobe tcp_bbr）"
fi

# gost 监听器配置。
# 默认保持原有行为，只在 8988 上提供一个内部 HTTP 代理。
# 若要把独立部署的 gost 入口容器合并进本容器，通过环境变量传入监听器，例如：
#   -e GOST_LISTENERS="-L=:8887 -L=ss://chacha20-ietf-poly1305:PASSWORD@:8443 -L=http://:8988"
# gost 运行在本容器的网络命名空间中，其出站流量会走 VPN 默认路由（tun0），无需 -F 转发。
GOST_LISTENERS=${GOST_LISTENERS:-"-L=http://:8988"}

# 保存 VPN 连接前的路由信息
DEFAULT_GW=$(ip route | awk '/^default/{print $3; exit}')
DEFAULT_IF=$(ip route | awk '/^default/{print $5; exit}')
echo "$DEFAULT_GW" > /tmp/saved_gateway
echo "$DEFAULT_IF" > /tmp/saved_iface
# 保存所有非默认路由
ip route | grep -v "^default" > /tmp/saved_routes
echo "VPN 连接前的默认网关：${DEFAULT_GW} via ${DEFAULT_IF}"
echo "VPN 连接前的路由表："
cat /tmp/saved_routes

# 创建一个 vpnc-script 包装脚本，用策略路由修复 Docker 端口映射
cat > /tmp/vpnc-script-wrapper.sh << 'SCRIPT_EOF'
#!/bin/sh

# 先执行默认的 vpnc-script
/usr/share/vpnc-scripts/vpnc-script "$@"

# VPN 连上之后设置策略路由，使从 eth0 进来的报文（Docker 端口映射过来的）
# 其回包走 eth0 而不是 VPN 隧道
if [ "$reason" = "connect" ]; then
  DEFAULT_GW=$(cat /tmp/saved_gateway 2>/dev/null)
  DEFAULT_IF=$(cat /tmp/saved_iface 2>/dev/null)
  echo "正在设置策略路由（网关：${DEFAULT_GW}，网卡：${DEFAULT_IF}）..."

  # 1. 在 eth0 上恢复所有已保存的非默认路由
  while IFS= read -r route_line; do
    [ -z "$route_line" ] && continue
    ip route add $route_line 2>/dev/null || true
    echo "  已恢复：$route_line"
  done < /tmp/saved_routes

  # 2. 建立独立路由表（table 100），指向 VPN 连接前的原始默认网关
  #    这张表里的流量都通过 Docker 的 eth0 网关出去
  if [ -n "$DEFAULT_GW" ] && [ -n "$DEFAULT_IF" ]; then
    ip route add default via "$DEFAULT_GW" dev "$DEFAULT_IF" table 100 2>/dev/null || true

    # 3. 用 ip rule 标记应该走 table 100 的报文：
    #    任何从 eth0 进来的包（Docker 端口映射/宿主机访问）
    #    其回包都应该走 table 100（即回到 eth0）
    ip rule add from all lookup 100 pref 100 2>/dev/null || true

    # 取容器 eth0 的 IP，用于基于源地址的路由
    CONTAINER_IP=$(ip addr show "$DEFAULT_IF" | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    if [ -n "$CONTAINER_IP" ]; then
      # 删掉宽泛的规则，改成基于具体源地址的规则
      ip rule del from all lookup 100 pref 100 2>/dev/null || true
      ip rule add from "$CONTAINER_IP" lookup 100 pref 100 2>/dev/null || true
      echo "  策略路由：来自 ${CONTAINER_IP} 的报文使用 table 100（via ${DEFAULT_GW} dev ${DEFAULT_IF}）"
    fi
  fi

  echo "路由设置完成。当前路由表："
  ip route
  echo "策略规则："
  ip rule
fi
SCRIPT_EOF
chmod +x /tmp/vpnc-script-wrapper.sh

run () {
  # 使用自定义的 vpnc-script 包装脚本启动 openconnect
  SCRIPT_OPT="--script /tmp/vpnc-script-wrapper.sh"

  if [ -z "${OPENCONNECT_PASSWORD}" ]; then
  # 交互式提示输入密码
    openconnect -u "$OPENCONNECT_USER" $SCRIPT_OPT $OPENCONNECT_OPTIONS $OPENCONNECT_URL
  elif [ ! -z "${OPENCONNECT_PASSWORD}" ] && [ ! -z "${OPENCONNECT_MFA_CODE}" ]; then
  # 多因素认证（MFA）
    (echo $OPENCONNECT_PASSWORD; echo $OPENCONNECT_MFA_CODE) | openconnect -u "$OPENCONNECT_USER" $SCRIPT_OPT $OPENCONNECT_OPTIONS --passwd-on-stdin $OPENCONNECT_URL
  elif [ ! -z "${OPENCONNECT_PASSWORD}" ]; then
  # 标准密码认证
    echo $OPENCONNECT_PASSWORD | openconnect -u "$OPENCONNECT_USER" $SCRIPT_OPT $OPENCONNECT_OPTIONS --passwd-on-stdin $OPENCONNECT_URL
  fi
}

# 等 VPN 隧道建立后再对外提供代理，否则流量会悄悄地从
# VPN 连接前的默认路由直连泄漏出去。
wait_for_tun() {
  echo "等待 VPN 隧道建立后再启动 gost..."
  i=0
  while [ "$i" -lt 300 ]; do
    if ip route 2>/dev/null | grep -q 'dev tun0'; then
      echo "VPN 隧道已建立（耗时约 $((i * 2)) 秒）"
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  echo "警告：600 秒后 tun0 仍未起来，仍然启动 gost（流量可能会泄漏！）" >&2
  return 1
}

# openconnect 放到后台运行，这样它的重启循环不会阻塞 gost
(
  until (run); do
    echo "openconnect 已退出，60 秒后重启..." >&2
    sleep 60
  done
) &

wait_for_tun

# 启动 gost 代理
if [ -n "${GOST_LISTENERS}" ]; then
  echo "正在启动 gost：${GOST_LISTENERS}"
  /usr/local/bin/gost ${GOST_LISTENERS} &
fi

# 作为 PID 1 常驻前台并回收子进程
wait

