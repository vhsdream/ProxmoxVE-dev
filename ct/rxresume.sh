#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://rxresu.me

APP="Reactive-Resume"
var_tags="documents"
var_cpu="2"
var_ram="2048"
var_disk="6"
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

  if [[ ! -f /etc/systemd/system/reactive-resume.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -s https://api.github.com/repos/AmruthPillai/Reactive-Resume/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping $APP"
    systemctl stop reactive-resume
    msg_ok "Stopped $APP"

    msg_info "Updating $APP to v${RELEASE}"
    cp /opt/${APP}/.env /opt/rxresume.env
    cd /tmp
    wget -q "https://github.com/AmruthPillai/Reactive-Resume/archive/refs/tags/v${RELEASE}.zip"
    unzip -q v${RELEASE}.zip
    cp -r ${APP}-${RELEASE}/* /opt/${APP}
    corepack enable
    export PUPPETEER_SKIP_DOWNLOAD="true"
    export NEXT_TELEMETRY_DISABLED=1
    export CI="true"
    $STD pnpm install --frozen-lockfile --prefix /opt/${APP}
    $STD pnpm run build --prefix /opt/${APP}
    $STD pnpm run prisma:generate --prefix /opt/${APP}
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Updating Minio"
    systemctl stop minio
    wget -q https://dl.min.io/server/minio/release/linux-amd64/minio_20250312180418.0.0_amd64.deb -O minio.deb
    $STD dpkg -i minio.deb
    msg_ok "Updated Minio"

    msg_info "Updating Playwright"
    $STD python3 -m pip install playwright --upgrade
    msg_ok "Updated Playwright"

    msg_info "Updating Browserless (Patience)"
    systemctl stop browserless
    TAG=$(curl -s https://api.github.com/repos/browserless/browserless/tags?per_page=1 | grep "name" | awk '{print substr($2, 3, length($2)-4) }')
    wget -q https://github.com/browserless/browserless/archive/refs/tags/v${TAG}.zip
    unzip -q v${TAG}.zip
    cp -r browserless-${TAG}/* /opt/browserless
    cd /opt/browserless
    $STD npm update
    $STD node_modules/playwright-core/cli.js install --with-deps chromium firefox webkit
    $STD node_modules/playwright-core/cli.js install --force chrome msedge
    $STD npm run build
    $STD npm run build:function
    $STD npm prune production
    msg_ok "Updated Browserless"

    msg_info "Starting services"
    systemctl start minio reactive-resume browserless
    msg_ok "Started services"

    msg_info "Cleaning Up"
    rm -f /tmp/minio.deb
    rm -rf /tmp/${APP}-${RELEASE}
    rm -rf /tmp/browserless-${TAG}

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
