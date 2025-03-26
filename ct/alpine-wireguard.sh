#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.wireguard.com/

APP="Alpine-Wireguard"
var_tags="alpine;vpn"
var_cpu="1"
var_ram="256"
var_disk="1"
var_os="alpine"
var_version="3.21"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors


function update_script() {
  UPD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SUPPORT" --radiolist --cancel-button Exit-Script "Spacebar = Select" 11 58 1 \
    "1" "Check for Alpine Updates" ON \
    3>&1 1>&2 2>&3)

  header_info
  if [ "$UPD" == "1" ]; then
    apk update && apk upgrade
    exit
  fi
}
function update_script() {
    msg_info "Updating Alpine Packages"
    apk update && apk upgrade
    msg_ok "Updated Alpine Packages"

    msg_info "Updating WireGuard"
    apk upgrade wireguard-tools
    msg_ok "Updated WireGuard"
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} WGDashboard Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:10086${CL}"
