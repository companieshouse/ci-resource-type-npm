#!/bin/sh
set -eu

# Minimal JFrog CLI shim for local flow testing.
# - Forwards `jf npm ...` calls to npm.

cmd="${1:-}"
state_file="/tmp/jf-shim-state"
npmrc_path="/home/node/.npmrc"

registry_host() {
  # Strip scheme from URL to build npmrc auth key format.
  printf "%s" "$1" | sed -E 's#^https?://##'
}

if [ "$cmd" = "c" ] && [ "${2:-}" = "add" ]; then
  url=""
  user=""
  pass=""

  for arg in "$@"; do
    case "$arg" in
      --url=*)
        url="${arg#--url=}"
        ;;
      --user=*)
        user="${arg#--user=}"
        ;;
      --password=*)
        pass="${arg#--password=}"
        ;;
    esac
  done

  cat > "$state_file" <<EOF
URL=${url}
USER=${user}
PASS=${pass}
EOF
  exit 0
fi

if [ "$cmd" = "npm-config" ]; then
  if [ -f "$state_file" ]; then
    . "${state_file}"
    if [ -n "${URL:-}" ] && [ -n "${USER:-}" ] && [ -n "${PASS:-}" ]; then
      mkdir -p /home/node
      host="$(registry_host "$URL")"
      encoded_pass="$(printf "%s" "$PASS" | base64 | tr -d '\n')"
      cat > "$npmrc_path" <<EOF
//${host}:username=${USER}
//${host}:_password=${encoded_pass}
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
