#!/bin/sh
/usr/local/bin/gost -L=http://:8988 & 

run () {
  # Start openconnect
  if [ -z "${OPENCONNECT_PASSWORD}" ]; then
  # Ask for password
    openconnect -u "$OPENCONNECT_USER" $OPENCONNECT_OPTIONS $OPENCONNECT_URL
  elif [ ! -z "${OPENCONNECT_PASSWORD}" ] && [ ! -z "${OPENCONNECT_MFA_CODE}" ]; then
  # Multi factor authentication (MFA)
    (echo $OPENCONNECT_PASSWORD; echo $OPENCONNECT_MFA_CODE) | openconnect -u "$OPENCONNECT_USER" $OPENCONNECT_OPTIONS --passwd-on-stdin $OPENCONNECT_URL
  elif [ ! -z "${OPENCONNECT_PASSWORD}" ]; then
  # Standard authentication
    echo $OPENCONNECT_PASSWORD | openconnect -u "$OPENCONNECT_USER" $OPENCONNECT_OPTIONS --passwd-on-stdin $OPENCONNECT_URL
  fi
}

until (run); do
  echo "openconnect exited. Restarting process in 60 seconds…" >&2
  sleep 60
done

