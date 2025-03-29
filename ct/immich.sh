#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://immich.app

APP="immich"
var_tags="photo;media"
var_cpu="4"
var_ram="4096"
var_disk="12"
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

  if [[ ! -f /opt/immich ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -s https://api.github.com/repos/immich-app/immich/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping $APP"
    systemctl stop immich-web immich-ml
    msg_ok "Stopped $APP"

    msg_info "Updating $APP to v${RELEASE}"
    tmp_file=$(mktemp)
    INSTALL_DIR="/opt/${APP}"
    UPLOAD_DIR="${INSTALL_DIR}/upload"
    SRC_DIR="${INSTALL_DIR}/source"
    APP_DIR="${INSTALL_DIR}/app"
    ML_DIR="${APP_DIR}/machine-learning"
    GEO_DIR="${INSTALL_DIR}/geodata"

    # Here, determine which, if any, custom libraries need to be rebuilt
    # and then run the commands

    cp ${ML_DIR}/start.sh ../opt/ml-start.sh.bak
    rm -rf {${APP_DIR},${SRC_DIR}}
    curl -fsSL "https://github.com/immich-app/immich/archive/refs/tags/v${RELEASE}.zip" -o $tmp_file
    unzip -q $tmp_file
    mv ${APP}-${RELEASE}/ ${SRC_DIR}
    mkdir -p {${APP_DIR},${ML_DIR}}
    cd ${SRC_DIR}/server
    $STD npm ci
    $STD npm run build
    $STD npm prune --omit=dev --omit=optional
    cd ${SRC_DIR}/open-api/typescript-sdk
    $STD npm ci
    $STD npm run build
    cd ${SRC_DIR}/web
    $STD npm ci
    $STD npm run build
    cd ${SRC_DIR}
    cp -a server/{node_modules,dist,bin,resources,package.json,package-lock.json,start*.sh} ${APP_DIR}/
    cp -a web/build ${APP_DIR}/www
    cp LICENSE ${APP_DIR}
    cp /opt/staging/base-images/server/bin/build-lock.json ${APP_DIR}
    cd ${SRC_DIR}/machine-learning
    $STD python3 -m venv ${ML_DIR}/ml-venv
    (
      . ${ML_DIR}/ml-venv/bin/activate
      # this is where there will be a choice of CUDA, OpenVINO or just CPU. For now just doing CPU
      $STD uv sync --extra cpu --active
    )
    cd ${SRC_DIR}
    cp -a machine-learning/{ann,app} ${ML_DIR}
    mv /opt/ml-start.sh.bak ${ML_DIR}/start.sh
    ln -sf ${APP_DIR}/resources ${INSTALL_DIR}
    cd ${APP_DIR}
    grep -Rl /usr/src | xargs -n1 sed -i "s|\/usr/src|$INSTALL_DIR|g"
    sed -i "s|\"/cache\"|\"$INSTALL_DIR/cache\"|g" $ML_DIR/app/config.py
    grep -RlE "'/build'" | xargs -n1 sed -i "s|'/build'|'$APP_DIR'|g"
    $STD npm install --build-from-source sharp
    rm -rf ${APP_DIR}/node_modules/@img/sharp-{libvips*,linuxmusl-x64}
    $STD npm i -g @immich/cli
    ln -s ${UPLOAD_DIR} ${APP_DIR}/upload
    ln -s ${UPLOAD_DIR} ${ML_DIR}/upload
    ln -s ${GEO_DIR} ${APP_DIR}

    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    systemctl start immich-ml immich-web
    msg_ok "Started $APP"

    msg_info "Cleaning Up"
    rm -f $tmp_file
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:2283${CL}"
