#!/bin/bash
set -euo pipefail

PORT=${gateway_port}

curl -fsSL "${sdk_gateway_download_url}" -o /usr/local/bin/sdk-gw
chmod +x /usr/local/bin/sdk-gw

cat <<SYSTEMD >/etc/systemd/system/sdk-gw.service
[Unit]
Description=sdk-gateway
After=network.target

[Service]
ExecStart=/usr/local/bin/sdk-gw --listen :${PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable --now sdk-gw
