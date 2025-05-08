#!/bin/bash
# ---------- sdk-gateway build-at-boot ----------
set -euo pipefail

PORT=${gateway_port}               # listener port (8080)
TAG=${sdk_gateway_tag}             # mock-gateway release tag (e.g. v0.1.2)
UPSTREAM=${sdk_server_endpoint}    # sdk-server NLB:9090 (passed from Terraform)

echo "[boot] installing Go tool-chain…"
GO_VER=1.22.4
curl -sL "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz" -o /tmp/go.tgz
tar -C /usr/local -xzf /tmp/go.tgz
export PATH=$PATH:/usr/local/go/bin

# Go needs a writable cache dir when run by cloud-init
export HOME=/root
export GOCACHE=/root/.cache/go
mkdir -p "$GOCACHE"

echo "[boot] fetching mock-gateway tag ${TAG}…"
mkdir -p /opt/sdk
curl -sL "https://github.com/thealonlevi/mock-gateway/archive/refs/tags/${TAG}.tar.gz" \
  | tar -xz -C /opt/sdk --strip-components 1

echo "[boot] building static proxy binary…"
cd /opt/sdk
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -ldflags="-s -w -X main.upstream=${UPSTREAM}" \
  -o /usr/local/bin/mock-gateway ./main.go

echo "[boot] creating systemd unit…"
cat >/etc/systemd/system/sdk-gw.service <<EOF
[Unit]
Description=sdk-gateway → ${UPSTREAM}
After=network.target

[Service]
ExecStart=/usr/local/bin/mock-gateway
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sdk-gw
echo "[boot] sdk-gateway proxy ready on :${PORT} (upstream=${UPSTREAM})"
