#!/bin/sh

# Start gost proxy
/usr/local/bin/gost -L=http://:8988 &

# Save pre-VPN routing info
DEFAULT_GW=$(ip route | awk '/^default/{print $3; exit}')
DEFAULT_IF=$(ip route | awk '/^default/{print $5; exit}')
echo "$DEFAULT_GW" > /tmp/saved_gateway
echo "$DEFAULT_IF" > /tmp/saved_iface
# Save all non-default routes
ip route | grep -v "^default" > /tmp/saved_routes
echo "Pre-VPN default gateway: ${DEFAULT_GW} via ${DEFAULT_IF}"
echo "Pre-VPN routes:"
cat /tmp/saved_routes

# Create a vpnc-script wrapper that uses policy routing to fix Docker port forwarding
cat > /tmp/vpnc-script-wrapper.sh << 'SCRIPT_EOF'
#!/bin/sh

# Run the default vpnc-script first
/usr/share/vpnc-scripts/vpnc-script "$@"

# After VPN connects, set up policy routing so that packets arriving on eth0
# (from Docker port forwarding) are replied via eth0, not the VPN tunnel
if [ "$reason" = "connect" ]; then
  DEFAULT_GW=$(cat /tmp/saved_gateway 2>/dev/null)
  DEFAULT_IF=$(cat /tmp/saved_iface 2>/dev/null)
  echo "Setting up policy routing (gateway: ${DEFAULT_GW}, iface: ${DEFAULT_IF})..."

  # 1. Restore all saved non-default routes on eth0
  while IFS= read -r route_line; do
    [ -z "$route_line" ] && continue
    ip route add $route_line 2>/dev/null || true
    echo "  Restored: $route_line"
  done < /tmp/saved_routes

  # 2. Set up a separate routing table (table 100) with the original default gateway
  #    This table routes everything via Docker's eth0 gateway
  if [ -n "$DEFAULT_GW" ] && [ -n "$DEFAULT_IF" ]; then
    ip route add default via "$DEFAULT_GW" dev "$DEFAULT_IF" table 100 2>/dev/null || true

    # 3. Use ip rule to mark packets that should use table 100:
    #    Any packet coming IN on eth0 (from Docker port forwarding / host access)
    #    should have its reply routed via table 100 (back through eth0)
    ip rule add from all lookup 100 pref 100 2>/dev/null || true

    # Get the container's eth0 IP and use it for source-based routing
    CONTAINER_IP=$(ip addr show "$DEFAULT_IF" | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    if [ -n "$CONTAINER_IP" ]; then
      # Delete the broad rule and add a specific source-based rule instead
      ip rule del from all lookup 100 pref 100 2>/dev/null || true
      ip rule add from "$CONTAINER_IP" lookup 100 pref 100 2>/dev/null || true
      echo "  Policy route: packets from ${CONTAINER_IP} use table 100 (via ${DEFAULT_GW} dev ${DEFAULT_IF})"
    fi
  fi

  echo "Route setup complete. Current routing table:"
  ip route
  echo "Policy rules:"
  ip rule
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

