#!/bin/bash
# ---------- sdk-server build-at-boot ----------
set -euo pipefail

PORT=${server_port}        # Terraform var → literal number (e.g. 9090)
TAG=${sdk_server_tag}      # Terraform var → Git tag

echo "[boot] installing Go tool-chain…"
GO_VER=1.22.4
curl -sL "https://go.dev/dl/go$${GO_VER}.linux-amd64.tar.gz" -o /tmp/go.tgz
tar -C /usr/local -xzf /tmp/go.tgz
export PATH=$PATH:/usr/local/go/bin

export HOME=/root
export GOCACHE=/root/.cache/go
mkdir -p "$GOCACHE"

echo "[boot] fetching mock-server tag $${TAG}…"
mkdir -p /opt/sdk
curl -sL "https://github.com/thealonlevi/mock-server/archive/refs/tags/$${TAG}.tar.gz" \
  | tar -xz -C /opt/sdk --strip-components 1

echo "[boot] building static binary…"
cd /opt/sdk
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -ldflags="-s -w" -o /usr/local/bin/mock-server ./main.go

echo "[boot] creating systemd unit…"
cat >/etc/systemd/system/sdk-srv.service <<EOF
[Unit]
Description=sdk-server (echo instance-id)
After=network.target

[Service]
ExecStart=/usr/local/bin/mock-server
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sdk-srv
echo "[boot] sdk-server ready on :$${PORT}"
