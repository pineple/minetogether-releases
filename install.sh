#!/bin/sh
set -eu

if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
  echo "MineTogether Personal Agent requires Linux amd64." >&2
  exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
  echo "Run this installer as the regular user that can run Docker; do not use sudo." >&2
  exit 1
fi
for tool in curl tar sha256sum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required command is missing: $tool" >&2
    exit 1
  fi
done

release_url=https://github.com/pineple/minetogether-releases/releases/latest/download
package=minetogether-agent-linux-amd64.tar.gz
install_tmp=$(mktemp -d "${TMPDIR:-/tmp}/minetogether-agent-install.XXXXXX")
trap 'rm -rf "$install_tmp"' EXIT

curl -fsSL "$release_url/$package" -o "$install_tmp/$package"
curl -fsSL "$release_url/$package.sha256" -o "$install_tmp/$package.sha256"
(cd "$install_tmp" && sha256sum -c "$package.sha256")
tar -xzf "$install_tmp/$package" -C "$install_tmp"
if [ ! -r /dev/tty ]; then
  echo "Run this installer from an interactive terminal." >&2
  exit 1
fi
"$install_tmp/install.sh" "$@" </dev/tty
