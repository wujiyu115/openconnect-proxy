#!/bin/sh

# Start gost proxy
/usr/local/bin/gost -L=http://:8988 &

# Save the full routing table snapshot before VPN overwrites it
route -n | awk 'NR>2 {print $1, $2, $3, $8}' > /tmp/saved_routes
echo "Saved routing table before VPN:"
cat /tmp/saved_routes

# Create a vpnc-script wrapper that dynamically restores pre-VPN routes
cat > /tmp/vpnc-script-wrapper.sh << 'SCRIPT_EOF'
#!/bin/sh

# Run the default vpnc-script first
/usr/share/vpnc-scripts/vpnc-script "$@"

# After VPN connects, restore all original routes that were overwritten
if [ "$reason" = "connect" ]; then
  echo "Restoring pre-VPN routes..."
  while read -r dest gw mask iface; do
    # Skip empty lines
    [ -z "$dest" ] && continue
    # Skip the default route (0.0.0.0) — let VPN handle that
    [ "$dest" = "0.0.0.0" ] && continue
    # Re-add each saved route via its original gateway and interface
    if [ "$gw" = "0.0.0.0" ]; then
      route add -net "$dest" netmask "$mask" dev "$iface" 2>/dev/null || true
    else
      route add -net "$dest" netmask "$mask" gw "$gw" dev "$iface" 2>/dev/null || true
    fi
    echo "  Restored route: $dest/$mask via $gw dev $iface"
  done < /tmp/saved_routes
  echo "Route restoration complete."
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

