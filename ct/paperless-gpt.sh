#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/icereed/paperless-gpt

APP="Debian"
var_tags="os"
var_cpu="3"
var_ram="2048"
var_disk="5"
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
    if [[ ! -d /opt/paperless-gpt ]]; then
        msg_error "No Paperless-GPT installation found!"
        exit 1
    fi
    RELEASE=$(curl -s https://api.github.com/repos/icereed/paperless-gpt/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
    if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
        msg_info "Stopping Service"
        systemctl stop paperless-gpt
        msg_ok "Service Stopped"

        msg_info "Backing up .env file"
        mkdir -p /opt/paperless-gpt-backup
        [[ -f /opt/paperless-gpt/web-app/.env ]] && cp -f /opt/paperless-gpt/web-app/.env /opt/paperless-gpt-backup/.env
        msg_ok "Backup Created"

        msg_info "Updating Paperless-GPT to ${RELEASE}"
        temp_file=$(mktemp)
        wget -q "https://github.com/icereed/paperless-gpt/archive/refs/tags/v${RELEASE}.tar.gz" -O $temp_file
        tar zxf $temp_file
        rm -rf /opt/paperless-gpt
        mv paperless-gpt-${RELEASE} /opt/paperless-gpt
        cd /opt/paperless-gpt/web-app
        $STD npm install
        $STD npm run build
        cd /opt/paperless-gpt
        go mod download
        export CC=musl-gcc
        CGO_ENABLED=1 go build -tags musl -o /dev/null github.com/mattn/go-sqlite3
        CGO_ENABLED=1 go build -tags musl -o paperless-gpt .
        echo "${RELEASE}" >"/opt/paperless-gpt_version.txt"
        msg_ok "Updated Paperless-GPT to ${RELEASE}"

        msg_info "Restoring .env file"
        [[ -f /opt/paperless-gpt-backup/.env ]] && mv -f /opt/paperless-gpt-backup/.env /opt/paperless-gpt/web-app/.env
        msg_ok "Restored .env file"

        msg_info "Starting Service"
        systemctl start paperless-gpt
        msg_ok "Started Service"

        msg_info "Cleaning Up"
        rm -f $temp_file
        rm -rf /opt/paperless-gpt-backup
        msg_ok "Cleanup Completed"

    else
        msg_ok "No update required. ${APP} is already at ${RELEASE}"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
