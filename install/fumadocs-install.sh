#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    gnupg \
    ca-certificates
msg_ok "Installed Dependencies"

msg_info "Installing Node.js"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
$STD apt-get update
$STD apt-get install -y nodejs
$STD npm install -g bun
msg_ok "Installed Node.js"

msg_info "Installing Fumadocs"
temp_file=$(mktemp)
RELEASE=$(curl -s https://api.github.com/repos/fuma-nama/fumadocs/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
export NODE_OPTIONS="--max-old-space-size=2048"
wget -q https://github.com/fuma-nama/fumadocs/archive/refs/tags/${RELEASE}.tar.gz -O $temp_file
tar zxf $temp_file
mv fumadocs-* "${PWD}/fumadocs"
cd /opt/fumadocs
$STD bun install
bun create fumadocs-app
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Installed Fumadocs"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/fumadocs.service
[Unit]
Description=Fumadocs Documentation Server
After=network.target

[Service]
WorkingDirectory=/opt/fumadocs
ExecStart=/usr/bin/bun run dev
Restart=always

[Install]
WantedBy=multi-user.target
msg_ok "Created Service"
EOF

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
