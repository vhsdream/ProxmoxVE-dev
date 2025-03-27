#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://immich.app

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Configuring apt and installing base Dependencies"
echo "deb http://deb.debian.org/debian testing main contrib" >/etc/apt/sources.list.d/immich.list
{
  echo "Package: *"
  echo "Pin: release a=testing"
  echo "Pin-Priority: -10"

} >/etc/apt/preferences.d/immich
$STD apt-get update
$STD apt-get install --no-install-recommends -y \
  git \
  redis \
  python3-venv \
  python3-dev \
  unzip \
  gnupg \
  autoconf \
  build-essential \
  cmake \
  jq \
  libbrotli-dev \
  libde265-dev \
  libexif-dev \
  libexpat1-dev \
  libglib2.0-dev \
  libgsf-1-dev \
  libjpeg62-turbo-dev \
  liblcms2-2 \
  librsvg2-dev \
  libspng-dev \
  meson \
  ninja-build \
  pkg-config \
  cpanminus \
  libde265-0 \
  libexif12 \
  libexpat1 \
  libgcc-s1 \
  libglib2.0-0 \
  libgomp1 \
  libgsf-1-114 \
  liblcms2-2 \
  liblqr-1-0 \
  libltdl7 \
  libmimalloc2.0 \
  libopenexr-3-1-30 \
  libopenjp2-7 \
  librsvg2-2 \
  libspng0 \
  mesa-utils \
  mesa-va-drivers \
  mesa-vulkan-drivers \
  tini \
  zlib1g \
  ocl-icd-libopencl1 \
  intel-media-va-driver
$STD apt-get install -y \
  libgdk-pixbuf-2.0-dev librsvg2-dev libtool
curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | gpg --dearmor -o /etc/apt/keyrings/jellyfin.gpg
export DPKG_ARCHITECTURE="$(dpkg --print-architecture)"
cat <<EOF >/etc/apt/sources.list.d/jellyfin.sources
Types: deb
URIs: https://repo.jellyfin.org/debian
Suites: bookworm
Components: main
Architectures: ${DPKG_ARCHITECTURE}
Signed-By: /etc/apt/keyrings/jellyfin.gpg
EOF
$STD apt-get update
$STD apt-get install -y jellyfin-ffmpeg7
ln -s /usr/lib/jellyfin-ffmpeg/ffmpeg /usr/bin/ffmpeg
ln -s /usr/lib/jellyfin-ffmpeg/ffprobe /usr/bin/ffprobe
wget -q https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.17193.4/intel-igc-core_1.0.17193.4_amd64.deb
wget -q https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.17193.4/intel-igc-opencl_1.0.17193.4_amd64.deb
wget -q https://github.com/intel/compute-runtime/releases/download/24.26.30049.6/intel-opencl-icd_24.26.30049.6_amd64.deb
wget -q https://github.com/intel/compute-runtime/releases/download/24.26.30049.6/libigdgmm12_22.3.20_amd64.deb
dpkg -i ./*.deb
msg_ok "Base Dependencies Installed"

msg_info "Setting up Postgresql Database"
$STD apt-get install -y postgresql-common
echo "YES" | /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh &>/dev/null
$STD apt-get install -y postgresql-17 postgresql-17-pgvector
DB_NAME="immich"
DB_USER="immich"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
$STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME to $DB_USER;"
$STD sudo -u postgres psql -c "ALTER USER $DB_USER WITH SUPERUSER;"
{
  echo "${APPLICATION} DB Credentials"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
  echo "Database Name: $DB_NAME"
} >>~/${APPLICATION}.creds
msg_ok "Set up Postgresql Database"

msg_info "Installing NodeJS"
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
$STD apt-get update
$STD apt-get install -y nodejs
msg_ok "Installed NodeJS"

msg_info "Installing Packages from Testing Repo"
export APT_LISTCHANGES_FRONTEND=none
export DEBIAN_FRONTEND=noninteractive
$STD apt-get install -t testing --no-install-recommends -y \
  libio-compress-brotli-perl \
  libwebp7 \
  libwebpdemux2 \
  libwebpmux3 \
  libhwy1t64 \
  libdav1d-dev \
  libhwy-dev \
  libwebp-dev
msg_ok "Packages from Testing Repo Installed"

msg_info "Compiling Custom Photo-processing Library (extreme patience)"
STAGING_DIR=/opt/staging
BASE_REPO="https://github.com/immich-app/base-images"
BASE_DIR=${STAGING_DIR}/base-images
SOURCE_DIR=${STAGING_DIR}/image-source
LD_LIBRARY_PATH=/usr/local/lib
$STD git clone -b main ${BASE_REPO} ${BASE_DIR}
mkdir -p ${SOURCE_DIR}

msg_info "Building libjxl"
cd ${STAGING_DIR}
SOURCE=${SOURCE_DIR}/libjxl
JPEGLI_LIBJPEG_LIBRARY_SOVERSION="62"
JPEGLI_LIBJPEG_LIBRARY_VERSION="62.3.0"
: "${LIBJXL_REVISION:=$(jq -cr '.sources[] | select(.name == "libjxl").revision' $BASE_DIR/server/bin/build-lock.json)}"
$STD git clone https://github.com/libjxl/libjxl.git ${SOURCE}
cd ${SOURCE}
$STD git reset --hard "${LIBJXL_REVISION}"
$STD git submodule update --init --recursive --depth 1 --recommend-shallow
$STD git apply ${BASE_DIR}/server/bin/patches/jpegli-empty-dht-marker.patch
$STD git apply ${BASE_DIR}/server/bin/patches/jpegli-icc-warning.patch
mkdir build
cd build
$STD cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF \
  -DJPEGXL_ENABLE_DOXYGEN=OFF \
  -DJPEGXL_ENABLE_MANPAGES=OFF \
  -DJPEGXL_ENABLE_PLUGIN_GIMP210=OFF \
  -DJPEGXL_ENABLE_BENCHMARK=OFF \
  -DJPEGXL_ENABLE_EXAMPLES=OFF \
  -DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
  -DJPEGXL_FORCE_SYSTEM_HWY=ON \
  -DJPEGXL_ENABLE_JPEGLI=ON \
  -DJPEGXL_ENABLE_JPEGLI_LIBJPEG=ON \
  -DJPEGXL_INSTALL_JPEGLI_LIBJPEG=ON \
  -DJPEGXL_ENABLE_PLUGINS=ON \
  -DJPEGLI_LIBJPEG_LIBRARY_SOVERSION="${JPEGLI_LIBJPEG_LIBRARY_SOVERSION}" \
  -DJPEGLI_LIBJPEG_LIBRARY_VERSION="${JPEGLI_LIBJPEG_LIBRARY_VERSION}" \
  -DLIBJPEG_TURBO_VERSION_NUMBER=2001005 \
  ..
$STD cmake --build . -- -j"$(nproc)"
$STD cmake --install .
$STD ldconfig /usr/local/lib
make clean
cd ${STAGING_DIR}
rm -rf ${SOURCE}/{build,third_party}
msg_ok "Built libjxl"

msg_info "Building libheif"
SOURCE=${SOURCE_DIR}/libheif
: "${LIBHEIF_REVISION:=$(jq -cr '.sources[] | select(.name == "libheif").revision' $BASE_DIR/server/bin/build-lock.json)}"
$STD git clone https://github.com/strukturag/libheif.git ${SOURCE}
cd ${SOURCE}
$STD git reset --hard "${LIBHEIF_REVISION}"
mkdir build
cd build
$STD cmake --preset=release-noplugins \
  -DWITH_DAV1D=ON \
  -DENABLE_PARALLEL_TILE_DECODING=ON \
  -DWITH_LIBSHARPYUV=ON \
  -DWITH_LIBDE265=ON \
  -DWITH_AOM_DECODER=OFF \
  -DWITH_AOM_ENCODER=OFF \
  -DWITH_X265=OFF \
  -DWITH_EXAMPLES=OFF \
  ..
$STD make install
ldconfig /usr/local/lib
make clean
cd ${STAGING_DIR}
rm -rf ${SOURCE}/build
msg_ok "Built libheif"

msg_info "Building libraw"
SOURCE=${SOURCE_DIR}/libraw
: "${LIBRAW_REVISION:=$(jq -cr '.sources[] | select(.name == "libraw").revision' $BASE_DIR/server/bin/build-lock.json)}"
$STD git clone https://github.com/libraw/libraw.git ${SOURCE}
cd ${SOURCE}
$STD git reset --hard "${LIBRAW_REVISION}"
$STD autoreconf --install
$STD ./configure
$STD make -j"$(nproc)"
$STD make install
ldconfig /usr/local/lib
$STD make clean
cd ${STAGING_DIR}
msg_ok "Built libraw"

msg_info "Building ImageMagick"
SOURCE=$SOURCE_DIR/imagemagick
: "${IMAGEMAGICK_REVISION:=$(jq -cr '.sources[] | select(.name == "imagemagick").revision' $BASE_DIR/server/bin/build-lock.json)}"
$STD git clone https://github.com/ImageMagick/ImageMagick.git $SOURCE
cd $SOURCE
$STD git reset --hard "${IMAGEMAGICK_REVISION}"
$STD ./configure --with-modules
$STD make -j"$(nproc)"
$STD make install
ldconfig /usr/local/lib
$STD make clean
cd ${STAGING_DIR}
msg_ok "Built ImageMagick"

msg_info "Building libvips"
SOURCE=$SOURCE_DIR/libvips
: "${LIBVIPS_REVISION:=$(jq -cr '.sources[] | select(.name == "libvips").revision' $BASE_DIR/server/bin/build-lock.json)}"
$STD git clone https://github.com/libvips/libvips.git ${SOURCE}
cd ${SOURCE}
$STD git reset --hard "${LIBVIPS_REVISION}"
$STD meson setup build --buildtype=release --libdir=lib -Dintrospection=disabled -Dtiff=disabled
cd build
$STD ninja install
$STD ldconfig /usr/local/lib
cd ${STAGING_DIR}
rm -rf ${SOURCE}/build
msg_ok "Built libvips"

$STD dpkg -r --force-depends libjpeg62-turbo
msg_ok "Custom Photo-processing Library Compiled"

msg_info "Installing ${APPLICATION} (more patience please)"
cd /tmp
RELEASE=$(curl -s https://api.github.com/repos/immich-app/immich/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
wget -q "https://github.com/immich-app/immich/archive/refs/tags/${RELEASE}.zip"
unzip -q ${RELEASE}.zip
INSTALL_DIR="/opt/${APPLICATION}"
UPLOAD_DIR="${INSTALL_DIR}/upload"
SRC_DIR="${INSTALL_DIR}/source"
APP_DIR="${INSTALL_DIR}/app"
ML_DIR="${APP_DIR}/machine-learning"
GEO_DIR="${INSTALL_DIR}/geodata"
mkdir -p ${INSTALL_DIR}
mv ${APPLICATION}-${RELEASE}/ ${SRC_DIR}
mkdir -p {${APP_DIR},${UPLOAD_DIR},${GEO_DIR},${ML_DIR}}

# Immich webserver install
msg_info "Installing Immich webserver"
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
cp -a LICENSE ${APP_DIR}
cp ${BASE_DIR}/server/bin/build-lock.json ${APP_DIR}
msg_ok "Installed Immich webserver"

msg_info "Installing Immich Machine-Learning"
cd ${SRC_DIR}/machine-learning
$STD python3 -m venv ${ML_DIR}/ml-venv
(

  . ${ML_DIR}/ml-venv/bin/activate
  $STD pip3 install uv

  # this is where there will be a choice of CUDA, OpenVINO or just CPU. For now just doing CPU
  $STD uv sync --extra cpu
  $STD pip3 install "numpy<2" # not sure if needed anymore

)
cd ${SRC_DIR}
cp -a machine-learning/{ann,start.sh,app} ${ML_DIR}
ln -sf ${APP_DIR}/resources ${INSTALL_DIR}
mkdir -p ${INSTALL_DIR}/cache

# Replacing some paths
cd ${APP_DIR}
sed -i "s|\/usr/src|$INSTALL_DIR|g" \
  $(grep -RlI "/usr/src" . --exclude="*.py*" --exclude="*.json")

echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Setup ${APPLICATION}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/${APPLICATION}.service
[Unit]
Description=${APPLICATION} Service
After=network.target

[Service]
ExecStart=[START_COMMAND]
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ${APPLICATION}.service
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -f ${RELEASE}.zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
