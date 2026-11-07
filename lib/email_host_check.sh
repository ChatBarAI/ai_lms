#!/bin/sh
# Read-only inventory. Never run a mail daemon or print its configuration/arguments.
printf '\nMail server inventory (%s):\n' "${1:-remote host}"
for daemon in postfix exim4 exim sendmail opensmtpd; do
  installed=unknown
  if command -v dpkg-query >/dev/null 2>&1; then
    state=$(dpkg-query -W -f='${Status}' "$daemon" 2>/dev/null)
    case "$state" in *'install ok installed'*) installed=yes ;; *) installed='not found in dpkg' ;; esac
  elif command -v rpm >/dev/null 2>&1; then
    if rpm -q "$daemon" >/dev/null 2>&1; then installed=yes; else installed='not found in rpm'; fi
  fi
  binary=not-found
  if command -v "$daemon" >/dev/null 2>&1 || [ -x "/usr/sbin/$daemon" ]; then
    binary=found
  fi
  # OpenSMTPD ships the smtpd executable.
  if [ "$daemon" = opensmtpd ] && { command -v smtpd >/dev/null 2>&1 || [ -x /usr/sbin/smtpd ]; }; then binary=found; fi
  printf '  %s: package=%s; executable=%s\n' "$daemon" "$installed" "$binary"
done

printf 'Service states (systemd):\n'
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  for unit in postfix postfix@- exim4 exim sendmail opensmtpd smtpd; do
    state=$(systemctl show "$unit.service" --property=LoadState,ActiveState,SubState --no-pager 2>/dev/null)
    if [ -n "$state" ]; then
      printf '  %s.service: %s\n' "$unit" "$(printf '%s' "$state" | tr '\n' ' ')"
    else
      printf '  %s.service: unavailable (permission or service-manager error)\n' "$unit"
    fi
  done
else
  printf '  unavailable (systemd not running or systemctl missing)\n'
fi

printf 'Mail daemon process names (no command arguments):\n'
if processes=$(ps -eo comm= 2>/dev/null); then
  matches=$(printf '%s\n' "$processes" | awk '$1 ~ /^(master|qmgr|pickup|postfix|exim|exim4|sendmail|smtpd)$/ {print "  " $1}')
  if [ -n "$matches" ]; then printf '%s\n' "$matches"; else printf '  none detected\n'; fi
  printf '  Process names alone do not identify a working MTA (master/smtpd may belong to other software).\n'
else
  printf '  unavailable\n'
fi

printf 'Listening TCP sockets on mail ports (25/465/587):\n'
if listeners=$(ss -H -ltn 2>/dev/null); then
  matches=$(printf '%s\n' "$listeners" | awk '$4 ~ /:(25|465|587)$/ {print "  " $4}')
  if [ -n "$matches" ]; then printf '%s\n' "$matches"; else printf '  none detected\n'; fi
else
  printf '  unavailable (ss missing or permission denied)\n'
fi
printf 'Inventory only: package/binary presence and service state do not prove container reachability or relay permission.\n'
printf 'Other mail software or mail servers in separate containers may not be identified. No services or settings changed.\n\n'
