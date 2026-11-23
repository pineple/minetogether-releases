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
  echo "MineTogether Agent requires Linux amd64." >&2
  exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
  echo "Run this installer as the regular user that can run Docker; do not use sudo." >&2
  exit 1
fi
for tool in curl tar sha256sum awk sed install stty; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required command is missing: $tool" >&2
    exit 1
  fi
done
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker must be installed, running, and accessible to $(id -un). Verify with: docker info" >&2
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1 || ! systemctl --user show-environment >/dev/null 2>&1; then
  echo "A running systemd user service manager is required. Log in as this user, then run the installer again." >&2
  exit 1
fi
if [ ! -r /dev/tty ]; then
  echo "Run this installer from an interactive terminal." >&2
  exit 1
fi

release_url=https://github.com/pineple/minetogether-releases/releases/latest/download
package=minetogether-agent-linux-amd64.tar.gz
install_tmp=$(mktemp -d "${TMPDIR:-/tmp}/minetogether-agent-install.XXXXXX")
trap 'rm -rf "$install_tmp"' EXIT HUP INT TERM
curl -fsSL "$release_url/$package" -o "$install_tmp/$package"
curl -fsSL "$release_url/$package.sha256" -o "$install_tmp/$package.sha256"
(cd "$install_tmp" && sha256sum -c "$package.sha256")
tar -xzf "$install_tmp/$package" -C "$install_tmp"
agent_binary="$install_tmp/minetogether-agent"
if [ ! -x "$agent_binary" ] || ! "$agent_binary" version >/dev/null 2>&1; then
  echo "The release package does not contain a runnable Agent binary." >&2
  exit 1
fi

user_home=${HOME:?HOME must be set}
config_base=${XDG_CONFIG_HOME:-"$user_home/.config"}
state_base=${XDG_STATE_HOME:-"$user_home/.local/state"}
case "$config_base:$state_base" in
  /*:/*) ;;
  *) echo "XDG_CONFIG_HOME and XDG_STATE_HOME must be absolute paths." >&2; exit 1 ;;
esac
agent_dir="$state_base/minetogether/agent"
state_dir="$agent_dir/state"
scratch_dir="$agent_dir/scratch"
legacy_state_dir="$state_base/minetogether/personal-agent"
legacy_config="$config_base/minetogether/personal-agent/agent.env"
service_dir="$config_base/systemd/user"
service_name=minetogether-agent.service
service_path="$service_dir/$service_name"
legacy_service_name=minetogether-personal-agent.service
legacy_service_path="$service_dir/$legacy_service_name"
binary_path="$user_home/.local/bin/minetogether-agent"

if systemctl --user is-active --quiet "$service_name"; then
  echo "The Agent service is running. Stop it after all worlds are stopped, then rerun the installer." >&2
  echo "  systemctl --user stop minetogether-agent" >&2
  exit 1
fi
if systemctl --user is-active --quiet "$legacy_service_name"; then
  echo "The previous Agent service is running. Stop it after all worlds are stopped, then rerun the installer." >&2
  echo "  systemctl --user stop minetogether-personal-agent" >&2
  exit 1
fi

legacy_value() {
  [ -f "$legacy_config" ] || return 0
  awk -F= -v name="$1" '$1 == name { sub(/^[^=]*=/, ""); print; exit }' "$legacy_config"
}

umask 077
install -d -m 0700 "$agent_dir" "$service_dir" "$(dirname -- "$binary_path")"
if [ -d "$legacy_state_dir" ]; then
  for entry in state scratch; do
    if [ -e "$legacy_state_dir/$entry" ] && [ ! -e "$agent_dir/$entry" ]; then
      mv "$legacy_state_dir/$entry" "$agent_dir/$entry"
    fi
  done
fi
install -d -m 0700 "$state_dir" "$scratch_dir"

legacy_eula=$(legacy_value MINECRAFT_EULA_ACCEPTED)
if [ ! -f "$state_dir/eula-accepted" ]; then
  if [ "$legacy_eula" = true ]; then
    : > "$state_dir/eula-accepted"
    chmod 0600 "$state_dir/eula-accepted"
  else
    printf '\nMinecraft EULA\nHave you read and accepted it? [y/N]: '
    IFS= read -r eula_consent </dev/tty || exit 1
    case "$eula_consent" in
      y|Y|yes|YES) : > "$state_dir/eula-accepted"; chmod 0600 "$state_dir/eula-accepted" ;;
      *) echo "The Agent was not installed because EULA acceptance is required." >&2; exit 1 ;;
    esac
  fi
fi

api_override=${NODE_AGENT_API_URL:-$(legacy_value NODE_AGENT_API_URL)}
if [ "$api_override" = "https://minetogether.pineple.com/api/internal/node-agent" ]; then
  api_override=
fi
game_host=${MINECRAFT_PUBLIC_HOST:-$(legacy_value MINECRAFT_PUBLIC_HOST)}
if [ "$game_host" = auto ]; then
  game_host=
fi
docker_host=${DOCKER_HOST:-$(legacy_value DOCKER_HOST)}
docker_context=${DOCKER_CONTEXT:-$(legacy_value DOCKER_CONTEXT)}

if [ "$reenroll" -eq 1 ] || { [ ! -f "$state_dir/agent-token" ] && [ ! -f "$state_dir/personal-token" ] && [ ! -f "$state_dir/enrollment-code" ]; }; then
  printf '\nOne-time code from the dashboard: '
  terminal_settings=$(stty -g)
  trap 'stty "$terminal_settings"' EXIT HUP INT TERM
  stty -echo
  IFS= read -r code </dev/tty
  stty "$terminal_settings"
  trap 'rm -rf "$install_tmp"' EXIT HUP INT TERM
  printf '\n'
  case "$code" in ''|*[!a-zA-Z0-9_-]*) echo "Invalid enrollment code." >&2; exit 1 ;; esac
  [ "${#code}" -eq 32 ] || { echo "Invalid enrollment code length." >&2; exit 1; }
  if [ "$reenroll" -eq 1 ]; then
    timestamp=$(date +%s)
    for token in agent-token personal-token; do
      if [ -f "$state_dir/$token" ]; then
        mv "$state_dir/$token" "$state_dir/$token.previous.$timestamp"
      fi
    done
  fi
  printf '%s\n' "$code" > "$state_dir/enrollment-code"
  chmod 0600 "$state_dir/enrollment-code"
fi

unit_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/%/%%/g'
}

install -m 0755 "$agent_binary" "$binary_path"
cat > "$service_path" <<EOF
[Unit]
Description=MineTogether Agent
After=default.target

[Service]
Type=simple
Environment="PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/snap/bin"
Environment="NODE_AGENT_PROVIDER=personal"
Environment="NODE_AGENT_API_TRANSPORT=http"
Environment="XDG_STATE_HOME=$(unit_escape "$state_base")"
Environment="TMPDIR=$(unit_escape "$scratch_dir")"
EOF
for setting in \
  "NODE_AGENT_API_URL:$api_override" \
  "MINECRAFT_PUBLIC_HOST:$game_host" \
  "DOCKER_HOST:$docker_host" \
  "DOCKER_CONTEXT:$docker_context"; do
  name=${setting%%:*}
  value=${setting#*:}
  if [ -n "$value" ]; then
    printf 'Environment="%s=%s"\n' "$name" "$(unit_escape "$value")" >> "$service_path"
  fi
done
cat >> "$service_path" <<EOF
WorkingDirectory=$(unit_escape "$agent_dir")
ExecStart="$(unit_escape "$binary_path")" worker
Restart=on-failure
RestartSec=5
UMask=0077

[Install]
WantedBy=default.target
EOF
chmod 0600 "$service_path"

install -d -m 0700 "$service_dir"
if [ -f "$legacy_service_path" ]; then
  systemctl --user disable "$legacy_service_name" >/dev/null 2>&1 || true
  rm -f "$legacy_service_path"
fi
systemctl --user daemon-reload
systemctl --user enable --now "$service_name"
if ! systemctl --user is-active --quiet "$service_name"; then
  echo "The Agent service did not start. Inspect it with: journalctl --user -u minetogether-agent -n 80" >&2
  exit 1
fi

printf 'Installed and started MineTogether Agent (%s).\n' "$("$binary_path" version)"
printf 'Check the dashboard for the device connection. Logs: journalctl --user -u minetogether-agent -f\n'
