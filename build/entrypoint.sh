#!/bin/sh

# Start gost proxy
/usr/local/bin/gost -L=http://:8988 &

# Save pre-VPN routing info: full route table + default gateway + interface
route -n | awk 'NR>2 {print $1, $2, $3, $8}' > /tmp/saved_routes
DEFAULT_GW=$(route -n | awk '/^0\.0\.0\.0/{print $2; exit}')
DEFAULT_IF=$(route -n | awk '/^0\.0\.0\.0/{print $8; exit}')
echo "$DEFAULT_GW" > /tmp/saved_gateway
echo "$DEFAULT_IF" > /tmp/saved_iface
echo "Pre-VPN default gateway: ${DEFAULT_GW} via ${DEFAULT_IF}"
echo "Pre-VPN routing table:"
cat /tmp/saved_routes

# Create a vpnc-script wrapper that dynamically restores routes after VPN connects
cat > /tmp/vpnc-script-wrapper.sh << 'SCRIPT_EOF'
#!/bin/sh

# Run the default vpnc-script first
/usr/share/vpnc-scripts/vpnc-script "$@"

# After VPN connects, restore original routes so Docker port forwarding works
if [ "$reason" = "connect" ]; then
  DEFAULT_GW=$(cat /tmp/saved_gateway 2>/dev/null)
  DEFAULT_IF=$(cat /tmp/saved_iface 2>/dev/null)
  echo "Restoring pre-VPN routes (gateway: ${DEFAULT_GW}, iface: ${DEFAULT_IF})..."

  # 1. Restore all saved non-default routes
  while read -r dest gw mask iface; do
    [ -z "$dest" ] && continue
    [ "$dest" = "0.0.0.0" ] && continue
    if [ "$gw" = "0.0.0.0" ]; then
      route add -net "$dest" netmask "$mask" dev "$iface" 2>/dev/null || true
    else
      route add -net "$dest" netmask "$mask" gw "$gw" dev "$iface" 2>/dev/null || true
    fi
    echo "  Restored: $dest/$mask via $gw dev $iface"
  done < /tmp/saved_routes

  # 2. Add route for the Docker host's subnet via original gateway
  #    This ensures reply packets to the host (e.g. 192.168.31.139) go back
  #    through eth0 instead of the VPN tunnel
  if [ -n "$DEFAULT_GW" ] && [ -n "$DEFAULT_IF" ]; then
    # Detect the host's subnet from the gateway IP (assume /16 for broad coverage)
    HOST_SUBNET=$(echo "$DEFAULT_GW" | awk -F. '{print $1"."$2".0.0"}')
    route add -net "$HOST_SUBNET" netmask 255.255.0.0 gw "$DEFAULT_GW" dev "$DEFAULT_IF" 2>/dev/null || true
    echo "  Added host subnet route: ${HOST_SUBNET}/255.255.0.0 via ${DEFAULT_GW} dev ${DEFAULT_IF}"
  fi

  echo "Route restoration complete. Current routing table:"
  route -n
fi
SCRIPT_EOF
chmod +x /tmp/vpnc-script-wrapper.sh

run () {
  # Start openconnect with custom vpnc-script wrapper
  SCRIPT_OPT="--script /tmp/vpnc-script-wrapper.sh"

  if [ -z "${OPENCONNECT_PASSWORD}" ]; then
  # Ask for password
    openconnect -u "$OPENCONNECT_USER" $SCRIPT_OPT $OPENCONNECT_OPTIONS $OPENCONNECT_URL
  elif [ ! -z "${OPENCONNECT_PASSWORD}" ] && [ ! -z "${OPENCONNECT_MFA_CODE}" ]; then
  # Multi factor authentication (MFA)
    (echo $OPENCONNECT_PASSWORD; echo $OPENCONNECT_MFA_CODE) | openconnect -u "$OPENCONNECT_USER" $SCRIPT_OPT $OPENCONNECT_OPTIONS --passwd-on-stdin $OPENCONNECT_URL
  elif [ ! -z "${OPENCONNECT_PASSWORD}" ]; then
  # Standard authentication
    echo $OPENCONNECT_PASSWORD | openconnect -u "$OPENCONNECT_USER" $SCRIPT_OPT $OPENCONNECT_OPTIONS --passwd-on-stdin $OPENCONNECT_URL
  fi
}

until (run); do
  echo "openconnect exited. Restarting process in 60 seconds…" >&2
  sleep 60
done

