#!/bin/sh
set -eu

reenroll=0
if [ "$#" -gt 1 ]; then
  echo "Usage: install.sh [--re-enroll]" >&2
  exit 2
fi
case "${1:-}" in
  "") ;;
  --re-enroll) reenroll=1 ;;
  *) echo "Usage: install.sh [--re-enroll]" >&2; exit 2 ;;
esac

if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
  echo "MineTogether Personal Agent requires Linux amd64." >&2
  exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
  echo "Run this installer as the regular user that can run Docker; do not use sudo." >&2
  exit 1
fi
for tool in curl tar sha256sum awk grep sed cut install stty; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required command is missing: $tool" >&2
    exit 1
  fi
done
if ! docker info >/dev/null 2>&1; then
  echo "Docker must be installed, running, and accessible to $(id -un). Verify with: docker info" >&2
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1 || ! systemctl --user show-environment >/dev/null 2>&1; then
  echo "A running systemd user service manager is required. Log in as this user, then run the installer again." >&2
  exit 1
fi
if systemctl --user is-active --quiet minetogether-personal-agent.service; then
  echo "The Agent service is running. Stop it after all worlds are stopped, then rerun the installer." >&2
  echo "  systemctl --user stop minetogether-personal-agent" >&2
  exit 1
fi
if [ ! -r /dev/tty ]; then
  echo "Run this installer from an interactive terminal." >&2
  exit 1
fi

release_url=https://github.com/pineple/minetogether-releases/releases/latest/download
package=minetogether-agent-linux-amd64.tar.gz
install_tmp=$(mktemp -d "${TMPDIR:-/tmp}/minetogether-agent-install.XXXXXX")
trap 'rm -rf "$install_tmp"' EXIT
curl -fsSL "$release_url/$package" -o "$install_tmp/$package"
curl -fsSL "$release_url/$package.sha256" -o "$install_tmp/$package.sha256"
(cd "$install_tmp" && sha256sum -c "$package.sha256")
tar -xzf "$install_tmp/$package" -C "$install_tmp"
if [ ! -x "$install_tmp/minetogether-agent" ] || [ ! -x "$install_tmp/install.sh" ]; then
  echo "The release package is missing the Agent binary or installer." >&2
  exit 1
fi
if ! "$install_tmp/minetogether-agent" version >/dev/null 2>&1; then
  echo "The packaged Agent binary could not run on this host." >&2
  exit 1
fi

user_home=${HOME:?HOME must be set}
config_base=${XDG_CONFIG_HOME:-"$user_home/.config"}
state_base=${XDG_STATE_HOME:-"$user_home/.local/state"}
case "$config_base:$state_base" in
  /*:/*) ;;
  *) echo "XDG_CONFIG_HOME and XDG_STATE_HOME must be absolute paths." >&2; exit 1 ;;
esac
config_dir="$config_base/minetogether/personal-agent"
config_path="$config_dir/agent.env"

config_value() {
  [ -f "$config_path" ] || return 0
  awk -F= -v name="$1" '$1 == name { sub(/^[^=]*=/, ""); print; exit }' "$config_path"
}

is_private_ipv4() {
  printf '%s\n' "$1" | awk -F. '
    NF != 4 { exit 1 }
    {
      for (i = 1; i <= 4; i++) {
        if ($i !~ /^[0-9]+$/ || $i + 0 > 255) exit 1
      }
      if ($1 + 0 == 10 || ($1 + 0 == 192 && $2 + 0 == 168) ||
          ($1 + 0 == 172 && $2 + 0 >= 16 && $2 + 0 <= 31)) exit 0
      exit 1
    }
  '
}

validate_api_url() {
  candidate_url=$1
  if ! printf '%s\n' "$candidate_url" | grep -Eq '^https?://[^[:space:]?#]+/api/internal/node-agent/?$'; then
    echo "Node Agent API URL must end in /api/internal/node-agent, without spaces or query parameters." >&2
    return 1
  fi
  case "$candidate_url" in
    https://*) return 0 ;;
    http://*)
      authority=$(printf '%s\n' "$candidate_url" | sed -e 's#^http://##' -e 's#/.*##')
      case "$authority" in
        localhost:*|localhost|127.0.0.1:*|127.0.0.1|\[::1\]:*|\[::1\]) return 0 ;;
      esac
      api_host=$(printf '%s\n' "$authority" | cut -d: -f1)
      if is_private_ipv4 "$api_host"; then
        return 0
      fi
      echo "HTTP is allowed only for localhost or a private IPv4 API address. Use HTTPS for a public API." >&2
      return 1
      ;;
  esac
}

existing_api_url=$(config_value NODE_AGENT_API_URL)
existing_game_host=$(config_value MINECRAFT_PUBLIC_HOST)
existing_eula=$(config_value MINECRAFT_EULA_ACCEPTED)
existing_docker_host=$(config_value DOCKER_HOST)
existing_docker_context=$(config_value DOCKER_CONTEXT)

api_url=${NODE_AGENT_API_URL:-$existing_api_url}
api_url=${api_url:-https://minetogether.pineple.com/api/internal/node-agent}
if ! validate_api_url "$api_url"; then
  exit 1
fi
case "$api_url" in
  https://*) minetogether_env=production ;;
  http://*) minetogether_env=local ;;
esac
if [ -n "${NODE_AGENT_API_URL:-}" ]; then
  printf '\nNode Agent API override: %s\n' "$api_url"
else
  printf '\nNode Agent API: %s\n' "$api_url"
fi

if [ -n "${MINECRAFT_PUBLIC_HOST:-}" ]; then
  game_host=$MINECRAFT_PUBLIC_HOST
elif [ -n "$existing_game_host" ]; then
  game_host=$existing_game_host
else
  printf '\nMinecraft address players will use\n  Default: auto\n  Input: ' >&2
  IFS= read -r game_host </dev/tty || exit 1
  game_host=${game_host:-auto}
fi
case "$game_host" in
  ''|*[!a-zA-Z0-9._:-]*)
    echo "Use an IP address, hostname, or auto." >&2
    exit 1
    ;;
esac

if [ "$existing_eula" = true ]; then
  eula_accepted=true
else
  printf '\nMinecraft EULA\nHave you read and accepted it?\n  Input [y/N]: ' >&2
  IFS= read -r eula_consent </dev/tty || exit 1
  case "$eula_consent" in
    y|Y|yes|YES) eula_accepted=true ;;
    *) echo "The Agent was not installed because EULA acceptance is required." >&2; exit 1 ;;
  esac
fi

docker_host=${DOCKER_HOST:-$existing_docker_host}
docker_context=${DOCKER_CONTEXT:-$existing_docker_context}
umask 077
install -d -m 0700 "$config_dir"
config_tmp="$config_path.tmp.$$"
{
  if [ -f "$config_path" ]; then
    grep -Ev '^[[:space:]]*(MINETOGETHER_ENV|NODE_AGENT_API_URL|MINECRAFT_PUBLIC_HOST|MINECRAFT_EULA_ACCEPTED|DOCKER_HOST|DOCKER_CONTEXT)=' "$config_path" || true
  fi
  printf 'MINETOGETHER_ENV=%s\n' "$minetogether_env"
  printf 'NODE_AGENT_API_URL=%s\n' "$api_url"
  printf 'MINECRAFT_PUBLIC_HOST=%s\n' "$game_host"
  printf 'MINECRAFT_EULA_ACCEPTED=%s\n' "$eula_accepted"
  [ -z "$docker_host" ] || printf 'DOCKER_HOST=%s\n' "$docker_host"
  [ -z "$docker_context" ] || printf 'DOCKER_CONTEXT=%s\n' "$docker_context"
} > "$config_tmp"
chmod 0600 "$config_tmp"
mv "$config_tmp" "$config_path"
printf 'Saved Agent settings to %s\n' "$config_path"

"$install_tmp/install.sh" "$@" </dev/tty
