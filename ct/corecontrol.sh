#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://corecontrol.xyz

APP="CoreControl"
var_tags="uptime;monitoring"
var_cpu="2"
var_ram="2048"
var_disk="4"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/CoreControl ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Crawling the new version and checking whether an update is required
  RELEASE="$(curl -s https://api.github.com/repos/crocofied/CoreControl/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')"
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping $APP"
    systemctl stop CoreControl cc-agent
    msg_ok "Stopped $APP"

    msg_info "Backing up configuration"
    cp /opt/"$APP"/.env /opt/cc.env
    msg_ok "Backup Created"

    msg_info "Updating $APP to v${RELEASE}"
    rm -r /opt/"$APP"
    cd /tmp
    curl -fsSLO "https://github.com/crocofied/CoreControl/archive/refs/tags/${RELEASE}.zip"
    unzip -q "$RELEASE".zip
    mv "$APP"-"$RELEASE"/ /opt/"$APP"
    cd /opt/"$APP"
    $STD npm ci
    $STD npx prisma generate
    $STD npx prisma migrate deploy
    $STD npm run build
    $STD npm prune --production

    cd ./agent
    export CGO_ENABLED=0
    export GOOS=linux
    $STD go mod download
    $STD go build -ldflags="-w -s" -o app cmd/agent
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    systemctl start CoreControl cc-agent
    msg_ok "Started $APP"

    msg_info "Cleaning Up"
    rm -f /tmp/"$RELEASE".zip
    msg_ok "Cleanup Completed"

    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
