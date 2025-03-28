#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/getmaxun/maxun

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    gpg \
    openssl \
    redis \
    libgbm1 \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libxkbcommon0 \
    libglib2.0-0 \
    libdbus-1-3 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxi6 \
    libxtst6 \
    netcat
msg_ok "Installed Dependencies"

#configure_lxc "Semantic Search requires a dedicated GPU and at least 16GB RAM. Would you like to install it?" 100 "memory" "16000"

msg_info "Setting up Node.js Repository"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
msg_ok "Set up Node.js Repository"

msg_info "Setting up PostgreSQL Repository"
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
echo "deb https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" >/etc/apt/sources.list.d/pgdg.list
$STD apt-get update
$STD apt-get install -y postgresql-17
msg_ok "Set up PostgreSQL Repository"

msg_info "Installing Node.js"
$STD apt-get update
$STD apt-get install -y nodejs
msg_ok "Installed Node.js"

msg_info "Setup Variables"
DB_NAME=maxun_db
DB_USER=maxun_user
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
MINIO_USER=minio_usr
MINIO_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)
JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
msg_ok "Set up Variables"

msg_info "Setup Database"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
    echo "Maxun-Credentials"
    echo "Maxun Database User: $DB_USER"
    echo "Maxun Database Password: $DB_PASS"
    echo "Maxun Database Name: $DB_NAME"
    echo "Maxun JWT Secret: $JWT_SECRET"
    echo "Maxun Encryption Key: $ENCRYPTION_KEY"
} >>~/maxun.creds
msg_ok "Set up Database"

msg_info "Setup MinIO"
cd /tmp
wget -q https://dl.min.io/server/minio/release/linux-amd64/minio
mv minio /usr/local/bin/
chmod +x /usr/local/bin/minio
mkdir -p /data
cat <<EOF >/etc/systemd/system/minio.service
[Unit]
Description=MinIO
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target

[Service]
User=root
EnvironmentFile=-/etc/default/minio
ExecStart=/usr/local/bin/minio server /data
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
{
    echo "__________________"
    echo "MinIO Admin User: $MINIO_USER"
    echo "MinIO Admin Password: $MINIO_PASS"
} >>~/maxun.creds
cat <<EOF >/etc/default/minio
MINIO_ROOT_USER=${MINIO_USER}
MINIO_ROOT_PASSWORD=${MINIO_PASS}
EOF
systemctl enable -q --now minio
msg_ok "Setup MinIO"

msg_info "Installing Maxun (Patience)"
cd /opt
RELEASE=$(curl -s https://api.github.com/repos/getmaxun/maxun/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
wget -q "https://github.com/getmaxun/maxun/archive/refs/tags/v${RELEASE}.zip"
unzip -q v${RELEASE}.zip
mv maxun-${RELEASE} /opt/maxun
cat <<EOF >/opt/maxun/.env
NODE_ENV=development
JWT_SECRET=${JWT_SECRET}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASS}
DB_HOST=localhost
DB_PORT=5432
ENCRYPTION_KEY=${ENCRYPTION_KEY}
MINIO_ENDPOINT=minio
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_ACCESS_KEY=${MINIO_USER}
MINIO_SECRET_KEY=${MINIO_PASS}
REDIS_HOST=127.0.0.1
REDIS_PORT=6379

BACKEND_PORT=8080
FRONTEND_PORT=5173
BACKEND_URL=http://localhost:8080
PUBLIC_URL=http://localhost:5173
VITE_BACKEND_URL=http://localhost:8080
VITE_PUBLIC_URL=http://localhost:5173

MAXUN_TELEMETRY=false
EOF

cd /opt/maxun
$STD npm install --legacy-peer-deps
cd /opt/maxun/maxun-core
$STD npm install --legacy-peer-deps
cd /opt/maxun
$STD npx playwright install --with-deps chromium
$STD npx playwright install-deps
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Installed Maxun"

msg_info "Running DB Migrations"
cd /opt/maxun
node -e "require('./server/src/db/migrate')().then(() => { console.log('Migrations completed'); })"
msg_ok "DB Migrations completed"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/maxun.service
[Unit]
Description=Maxun Service
After=network.target postgresql.service redis.service minio.service

[Service]
WorkingDirectory=/opt/maxun
ExecStart=/usr/bin/npm run server
Restart=always
EnvironmentFile=/opt/maxun/.env

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now maxun
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/v${RELEASE}.zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
