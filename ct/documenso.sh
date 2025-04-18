#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source:

APP="Documenso"
var_tags="${var_tags:-document}"
var_disk="${var_disk:-12}"
var_cpu="${var_cpu:-6}"
var_ram="${var_ram:-6144}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/documenso ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    RELEASE=$(curl -s https://api.github.com/repos/documenso/documenso/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
    if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --msgbox --title "SET RESOURCES" "Please set the resources in your ${APP} LXC to ${var_cpu}vCPU and ${var_ram}RAM for the build process before continuing" 10 75
        msg_info "Stopping ${APP}"
        systemctl stop documenso
        msg_ok "${APP} Stopped"

        msg_info "Updating ${APP} to ${RELEASE}"
        cp /opt/documenso/.env /opt/
        rm -R /opt/documenso
        curl -fsSL "https://github.com/documenso/documenso/archive/refs/tags/v${RELEASE}.zip" -o v${RELEASE}.zip
        unzip -q v${RELEASE}.zip
        mv documenso-${RELEASE} /opt/documenso
        cd /opt/documenso
        mv /opt/.env /opt/documenso/.env
        npm install &>/dev/null
        npm run build:web &>/dev/null
        npm run prisma:migrate-deploy &>/dev/null
        echo "${RELEASE}" >/opt/${APP}_version.txt
        msg_ok "Updated ${APP}"

        msg_info "Starting ${APP}"
        systemctl start documenso
        msg_ok "Started ${APP}"

        msg_info "Cleaning Up"
        rm -rf v${RELEASE}.zip
        msg_ok "Cleaned"
        msg_ok "Updated Successfully"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
