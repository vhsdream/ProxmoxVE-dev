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

msg_info "Configuring apt and installing base dependencies"
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
DPKG_ARCHITECTURE="$(dpkg --print-architecture)"
export DPKG_ARCHITECTURE
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
tmp_dir=$(mktemp -d)
cd $tmp_dir
curl -fsSL https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.17193.4/intel-igc-core_1.0.17193.4_amd64.deb -O
curl -fsSL https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.17193.4/intel-igc-opencl_1.0.17193.4_amd64.deb -O
curl -fsSL https://github.com/intel/compute-runtime/releases/download/24.26.30049.6/intel-opencl-icd_24.26.30049.6_amd64.deb -O
curl -fsSL https://github.com/intel/compute-runtime/releases/download/24.26.30049.6/libigdgmm12_22.3.20_amd64.deb -O
dpkg -i ./*.deb
msg_ok "Base Dependencies Installed"

msg_info "Setting up Postgresql Database"
$STD apt-get install -y postgresql-common
echo "YES" | /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh &>/dev/null
$STD apt-get install -y postgresql-17 postgresql-17-pgvector
DB_NAME="immich"
DB_USER="immich"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c18)
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

# Fix default DB collation issue
# $STD sudo -u postgres psql -c "ALTER DATABASE postgres REFRESH COLLATION VERSION;"
# $STD sudo -u postgres psql -c "ALTER DATABASE $DB_NAME REFRESH COLLATION VERSION;"

msg_info "Compiling Custom Photo-processing Library (extreme patience)"
STAGING_DIR=/opt/staging
BASE_REPO="https://github.com/immich-app/base-images"
BASE_DIR=${STAGING_DIR}/base-images
SOURCE_DIR=${STAGING_DIR}/image-source
# TODO: convert this git clone into a TAG download
$STD git clone -b main ${BASE_REPO} ${BASE_DIR}
mkdir -p ${SOURCE_DIR}

msg_info "Building libjxl"
cd ${STAGING_DIR}
SOURCE=${SOURCE_DIR}/libjxl
JPEGLI_LIBJPEG_LIBRARY_SOVERSION="62"                                                                                    # store in a text file
JPEGLI_LIBJPEG_LIBRARY_VERSION="62.3.0"                                                                                  # store in a text file
: "${LIBJXL_REVISION:=$(jq -cr '.sources[] | select(.name == "libjxl").revision' $BASE_DIR/server/bin/build-lock.json)}" # store in a text file
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
: "${LIBHEIF_REVISION:=$(jq -cr '.sources[] | select(.name == "libheif").revision' $BASE_DIR/server/bin/build-lock.json)}" # store in a text file
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
: "${LIBRAW_REVISION:=$(jq -cr '.sources[] | select(.name == "libraw").revision' $BASE_DIR/server/bin/build-lock.json)}" # store in a text file
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
: "${IMAGEMAGICK_REVISION:=$(jq -cr '.sources[] | select(.name == "imagemagick").revision' $BASE_DIR/server/bin/build-lock.json)}" # store in a text file
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
: "${LIBVIPS_REVISION:=$(jq -cr '.sources[] | select(.name == "libvips").revision' $BASE_DIR/server/bin/build-lock.json)}" # store in a text file
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
tmp_file=$(mktemp)
RELEASE=$(curl -s https://api.github.com/repos/immich-app/immich/releases?per_page=1 | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
curl -fsSL "https://github.com/immich-app/immich/archive/refs/tags/v${RELEASE}.zip" -o $tmp_file
unzip -q $tmp_file
INSTALL_DIR="/opt/${APPLICATION}"
UPLOAD_DIR="${INSTALL_DIR}/upload"
SRC_DIR="${INSTALL_DIR}/source"
APP_DIR="${INSTALL_DIR}/app"
ML_DIR="${APP_DIR}/machine-learning"
GEO_DIR="${INSTALL_DIR}/geodata"
mkdir -p ${INSTALL_DIR}
mv ${APPLICATION}-${RELEASE}/ ${SRC_DIR}
mkdir -p {${APP_DIR},${UPLOAD_DIR},${GEO_DIR},${ML_DIR},${INSTALL_DIR}/cache}

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
cp LICENSE ${APP_DIR}
cp ${BASE_DIR}/server/bin/build-lock.json ${APP_DIR}
msg_ok "Installed Immich webserver"

msg_info "Installing Immich Machine-Learning"
cd ${SRC_DIR}/machine-learning
$STD python3 -m venv ${ML_DIR}/ml-venv
(

  . ${ML_DIR}/ml-venv/bin/activate
  $STD pip3 install uv
  # this is where there will be a choice of CUDA, OpenVINO or just CPU. For now just doing CPU
  $STD uv sync --extra cpu --active
)
cd ${SRC_DIR}
cp -a machine-learning/{ann,start.sh,app} ${ML_DIR}
ln -sf ${APP_DIR}/resources ${INSTALL_DIR}
msg_ok "Immich Machine-Learning Installed"

# Replacing some paths
cd ${APP_DIR}
grep -Rl /usr/src | xargs -n1 sed -i "s|\/usr/src|$INSTALL_DIR|g"
sed -i "s|\"/cache\"|\"$INSTALL_DIR/cache\"|g" $ML_DIR/app/config.py
grep -RlE "'/build'" | xargs -n1 sed -i "s|'/build'|'$APP_DIR'|g"

# Install sharp and CLI
msg_info "Installing Immich CLI"
$STD npm install --build-from-source sharp
rm -rf ${APP_DIR}/node_modules/@img/sharp-{libvips*,linuxmusl-x64}
$STD npm i -g @immich/cli
msg_ok "Installed Immich CLI"

# Setup upload folder
ln -s ${UPLOAD_DIR} ${APP_DIR}/upload
ln -s ${UPLOAD_DIR} ${ML_DIR}/upload

# GeoNames install
msg_info "Installing GeoNames data"
cd ${GEO_DIR}
URL_LIST=(
  https://download.geonames.org/export/dump/admin1CodesASCII.txt
  https://download.geonames.org/export/dump/admin2Codes.txt
  https://download.geonames.org/export/dump/cities500.zip
  https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson
)
echo "${URL_LIST[@]}" | xargs -n1 -P 8 wget -q
unzip -q cities500.zip
date --iso-8601=seconds | tr -d "\n" >geodata-date.txt
cd ${INSTALL_DIR}
ln -s ${GEO_DIR} ${APP_DIR}
msg_ok "Installed GeoNames data"

mkdir -p /var/log/immich
touch /var/log/immich/{web.log,ml.log}
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Installed ${APPLICATION}"

msg_info "Creating env file, scripts & services"
# Immich Web env
cat <<EOF >${INSTALL_DIR}/.env
TZ=$(cat /etc/timezone)
IMMICH_VERSION=release
IMMICH_ENV=production

DB_HOSTNAME=localhost
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}
DB_DATABASE_NAME=${DB_NAME}
DB_VECTOR_EXTENSION=pgvector

REDIS_HOSTNAME=localhost

MACHINE_LEARNING_CACHE_FOLDER=${INSTALL_DIR}/cache
EOF
# Immich Machine-Learning start script
cat <<EOF >${ML_DIR}/start.sh
#!/usr/bin/env bash

cd ${ML_DIR}
. ml-venv/bin/activate

: "\${MACHINE_LEARNING_HOST:=127.0.0.1}"
: "\${MACHINE_LEARNING_PORT:=3003}"
: "\${MACHINE_LEARNING_WORKERS:=1}"
: "\${MACHINE_LEARNING_WORKER_TIMEOUT:=120}"

exec gunicorn app.main:app \
  -k app.config.CustomUvicornWorker \
  -w "\$MACHINE_LEARNING_WORKERS" \
  -b "\$MACHINE_LEARNING_HOST":"\$MACHINE_LEARNING_PORT" \
  -t "\$MACHINE_LEARNING_WORKER_TIMEOUT" \
  --log-config-json log_conf.json \
  --graceful-timeout 0
EOF
# Immich Web Service
cat <<EOF >/etc/systemd/system/${APPLICATION}-web.service
[Unit]
Description=${APPLICATION} Web Service
After=network.target
Requires=redis-server.service
Requires=postgresql.service
Requires=immich-ml.service

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=/usr/bin/node dist/main "\$@"
Restart=on-failure
SyslogIdentifier=immich-web
StandardOutput=append:/var/log/immich/web.log
StandardError=append:/var/log/immich/web.log

[Install]
WantedBy=multi-user.target
EOF
# Immich Machine-Learning Service
cat <<EOF >/etc/systemd/system/${APPLICATION}-ml.service
[Unit]
Description=${APPLICATION} Machine-Learning
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=${ML_DIR}/start.sh
Restart=on-failure
SyslogIdentifier=immich-machine-learning
StandardOutput=append:/var/log/immich/ml.log
StandardError=append:/var/log/immich/ml.log

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ${APPLICATION}-ml.service ${APPLICATION}-web.service
msg_ok "Created env file, scripts and services"

motd_ssh
customize

msg_info "Cleaning up"
rm -f $tmp_file
rm -rf $tmp_dir
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
