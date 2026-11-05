#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if (( EUID != 0 )); then
  exec sudo -- "$0" "$@"
fi

if ! id ubuntu >/dev/null 2>&1; then
  echo 'The expected ubuntu account does not exist.' >&2
  exit 1
fi
if [[ ! -x /home/ubuntu/.local/bin/cosign ]]; then
  echo 'Install Cosign at /home/ubuntu/.local/bin/cosign before enabling the pull timer.' >&2
  exit 1
fi

install -d -o ubuntu -g ubuntu -m 0775 /home/ubuntu/mac_shared
install -d -o root -g root -m 0755 /etc/kiyan-os /usr/local/libexec
install -o root -g root -m 0644 "$repo_root/cosign.pub" /etc/kiyan-os/cosign.pub
install -o root -g root -m 0755 "$repo_root/deploy/scripts/pull-latest-release.py" /usr/local/libexec/kiyan-release-pull.py
install -o root -g root -m 0644 "$repo_root/deploy/systemd/kiyan-release-pull.service" /etc/systemd/system/kiyan-release-pull.service
install -o root -g root -m 0644 "$repo_root/deploy/systemd/kiyan-release-pull.timer" /etc/systemd/system/kiyan-release-pull.timer

systemctl daemon-reload
systemctl enable --now kiyan-release-pull.timer
systemctl start kiyan-release-pull.service
systemctl --no-pager --full status kiyan-release-pull.timer
