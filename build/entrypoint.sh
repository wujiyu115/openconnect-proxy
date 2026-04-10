#!/bin/sh

# Start gost proxy
/usr/local/bin/gost -L=http://:8988 &

# Save the default gateway before VPN overwrites routing table
DEFAULT_GW=$(route -n | awk '/^0\.0\.0\.0/{print $2; exit}')
echo "Default gateway before VPN: ${DEFAULT_GW}"

# Create a vpnc-script wrapper that restores routes for Docker network after VPN connects
cat > /tmp/vpnc-script-wrapper.sh << 'SCRIPT_EOF'
#!/bin/sh

# Run the default vpnc-script first
/usr/share/vpnc-scripts/vpnc-script "$@"

# After VPN connects, add route back for Docker bridge network
if [ "$reason" = "connect" ]; then
  # Read saved gateway
  DEFAULT_GW=$(cat /tmp/saved_gateway 2>/dev/null)
  if [ -n "$DEFAULT_GW" ]; then
    echo "Restoring Docker network routes via gateway ${DEFAULT_GW}"
    # Route Docker bridge network (172.17.0.0/16) through original gateway
    route add -net 172.17.0.0 netmask 255.255.0.0 gw "$DEFAULT_GW" 2>/dev/null || true
    # Route common LAN subnets through original gateway so host can reach container
    route add -net 192.168.0.0 netmask 255.255.0.0 gw "$DEFAULT_GW" 2>/dev/null || true
    route add -net 10.0.0.0 netmask 255.0.0.0 gw "$DEFAULT_GW" 2>/dev/null || true
  fi
fi
SCRIPT_EOF
chmod +x /tmp/vpnc-script-wrapper.sh

# Save gateway for the wrapper script to use
echo "$DEFAULT_GW" > /tmp/saved_gateway

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

