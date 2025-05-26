#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://corecontrol.xyz

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  ca-certificates
msg_ok "Installed Dependencies"

NODE_VERSION="20" install_node_and_modules
PG_VERSION="17" install_postgresql

msg_info "Setting up Postgresql Database"
DB_NAME="core"
DB_USER="coreuser"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8';"
$STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME to $DB_USER;"
$STD sudo -u postgres psql -c "ALTER USER $DB_USER WITH SUPERUSER;"
{
  echo "${APPLICATION} Credentials"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
  echo "Database Name: $DB_NAME"
} >>~/"$APPLICATION".creds
msg_ok "Set up Postgresql Database"

GO_VERSION="1.19" install_go

msg_info "Installing ${APPLICATION}"
RELEASE="$(curl -s https://api.github.com/repos/crocofied/CoreControl/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')"
curl -fsSLO "https://github.com/crocofied/CoreControl/archive/refs/tags/${RELEASE}.zip"
unzip -q "$RELEASE".zip
mv "$APPLICATION"-"$RELEASE"/ /opt/"$APPLICATION"
cd /opt/"$APPLICATION"

cat <<EOF >/opt/"$APPLICATION"/.env
NODE_ENV=production
GOMAXPROCS=1
JWT_SECRET="$(openssl rand -base64 72 | tr -dc 'a-zA-Z0-9')"
DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"
EOF

export NEXT_TELEMETRY_DISABLED=1
$STD npm ci
$STD npx prisma generate
$STD npx prisma migrate deploy
$STD npm run build
$STD npm prune --production

cd ./agent
export CGO_ENABLED=0
export GOOS=linux
$STD go mod download
$STD go build -ldflags="-w -s" -o app ./cmd/agent

echo "$RELEASE" >/opt/"$APPLICATION"_version.txt
msg_ok "Installed ${APPLICATION}"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/"$APPLICATION".service
[Unit]
Description=${APPLICATION} Server
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/${APPLICATION}
EnvironmentFile=/opt/${APPLICATION}/.env
ExecStart=/usr/bin/npm run start
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/cc-agent.service
[Unit]
Description=${APPLICATION} Agent
After=network.target ${APPLICATION}.service

[Service]
Type=simple
WorkingDirectory=/opt/${APPLICATION}/agent
EnvironmentFile=/opt/${APPLICATION}/.env
ExecStart=/opt/${APPLICATION}/agent/app
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now "$APPLICATION".service cc-agent.service
msg_ok "Created env and Services"

motd_ssh
customize

msg_info "Cleaning up"
rm -f ~/"$RELEASE".zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean

msg_ok "Cleaned"
