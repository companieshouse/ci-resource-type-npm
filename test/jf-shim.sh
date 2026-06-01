#!/bin/sh
set -eu

# Minimal JFrog CLI shim for local flow testing.
# - Accepts config commands used by this resource.
# - Forwards `jf npm ...` calls to npm.

cmd="${1:-}"
state_file="/tmp/jf-shim-state"
npmrc_path="/home/node/.npmrc"

get_flag_value() {
  flag="$1"
  shift
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "$flag" ]; then
      shift
      printf "%s" "${1:-}"
      return 0
    fi
    shift
  done
  return 1
}

registry_host() {
  # Strip scheme from URL to build npmrc auth key format.
  printf "%s" "$1" | sed -E 's#^https?://##'
}

if [ "$cmd" = "c" ] && [ "${2:-}" = "add" ]; then
  url="$(get_flag_value --url "$@" || true)"
  user="$(get_flag_value --user "$@" || true)"
  pass="$(get_flag_value --password "$@" || true)"
  cat > "$state_file" <<EOF
URL=${url}
USER=${user}
PASS=${pass}
EOF
  exit 0
fi

if [ "$cmd" = "npm-config" ]; then
  if [ -f "$state_file" ]; then
    # shellcheck disable=SC1090
    . "$state_file"
    if [ -n "${URL:-}" ] && [ -n "${USER:-}" ] && [ -n "${PASS:-}" ]; then
      mkdir -p /home/node
      host="$(registry_host "$URL")"
      encoded_pass="$(printf "%s" "$PASS" | base64 | tr -d '\n')"
      cat > "$npmrc_path" <<EOF
//${host}:username=${USER}
//${host}:_password=${encoded_pass}
//${host}:email=test@example.com
registry=${URL}
EOF
    fi
  fi
  exit 0
fi

if [ "$cmd" = "npm" ]; then
  shift
  NPM_CONFIG_USERCONFIG="$npmrc_path" exec npm "$@"
fi

echo "jf-shim: unsupported command: $*" >&2
exit 1
