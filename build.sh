#!/bin/bash
# 麒麟V10(aarch64/glibc2.31) webkit2gtk-4.1 编译
# 在 GitHub Actions ubuntu-*-arm 跑手的 focal 容器内原生执行
set -ex
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
echo "deb http://ports.ubuntu.com/ubuntu-ports focal main universe" > /etc/apt/sources.list
echo "deb http://ports.ubuntu.com/ubuntu-ports focal-updates main universe" >> /etc/apt/sources.list
apt-get update -qq
apt-get install -y --no-install-recommends \
  build-essential cmake ninja-build python3 pkg-config gperf bison flex ruby ruby-dev gettext \
  curl ca-certificates python3-setuptools python3-pip \
  libgtk-3-dev libglib2.0-dev libharfbuzz-dev libfreetype6-dev libfontconfig1-dev \
  libxml2-dev libxslt1-dev libsqlite3-dev libjpeg-turbo8-dev libpng-dev \
  libwebp-dev libtasn1-6-dev libxkbcommon-dev libgnutls28-dev \
  libgcrypt20-dev libgpg-error-dev libwoff-dev libatspi2.0-dev \
  libxt-dev libxtst-dev libxcomposite-dev libxdamage-dev \
  liblcms2-dev uuid-dev libexpat1-dev unifdef libwpe-dev libwpebackend-fdo-dev meson libpsl-dev libnghttp2-dev

pip3 install -q "meson==0.63.3" "cmake==3.28.3"
hash -r; cmake --version | head -1
hash -r; meson --version

export PKG_CONFIG_PATH=/usr/local/lib/aarch64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:${PKG_CONFIG_PATH:-}
echo /usr/local/lib/aarch64-linux-gnu > /etc/ld.so.conf.d/usrlocal.conf
ldconfig

OUT="${GITHUB_WORKSPACE:-/tmp}/out"; mkdir -p /src "$OUT" && cd /src
curl -sfLO https://download.gnome.org/sources/glib/2.72/glib-2.72.4.tar.xz
curl -sfLO https://download.gnome.org/sources/glib-networking/2.72/glib-networking-2.72.0.tar.xz
curl -sfLO https://download.gnome.org/sources/libsoup/3.0/libsoup-3.0.8.tar.xz
curl -sfLO https://www.webkitgtk.org/releases/webkitgtk-2.40.2.tar.xz

# glib 2.72.4
if ! pkg-config --atleast-version=2.69.1 glib-2.0; then
  tar -xf glib-2.72.4.tar.xz && cd glib-2.72.4
  meson setup _build --buildtype=release -Dgtk_doc=false -Dman=false
  ninja -C _build install && ldconfig && cd /src
fi
# glib-networking
if ! pkg-config --atleast-version=2.72 glib-networking-2.0 2>/dev/null; then
  tar -xf glib-networking-2.72.0.tar.xz && cd glib-networking-2.72.0
  rm -rf _build && meson setup _build --buildtype=release -Dgnutls=enabled -Dopenssl=disabled -Dlibproxy=disabled
  ninja -C _build install && ldconfig && cd /src
fi
# libsoup3
if [ ! -e /usr/local/lib/aarch64-linux-gnu/libsoup-3.0.so.0 ]; then
  tar -xf libsoup-3.0.8.tar.xz && cd libsoup-3.0.8
  rm -rf _build && meson setup _build --buildtype=release -Dgssapi=disabled -Dvapi=disabled -Dgtk_doc=false -Dtests=false -Dintrospection=disabled
  ninja -C _build install && ldconfig && cd /src
fi
# webkit 4.1
tar -xf webkitgtk-2.40.2.tar.xz && cd webkitgtk-2.40.2
mkdir -p _build && cd _build
cmake -G Ninja -DCMAKE_BUILD_TYPE=release -DPORT=GTK -DUSE_SOUP2=OFF \
  -DENABLE_VIDEO=OFF -DENABLE_WEB_AUDIO=OFF -DENABLE_GAMEPAD=OFF \
  -DENABLE_ENCRYPTED_MEDIA=OFF -DENABLE_SPELLCHECK=OFF \
  -DENABLE_INTROSPECTION=OFF -DENABLE_DOCUMENTATION=OFF \
  -DENABLE_BUBBLEWRAP_SANDBOX=OFF -DENABLE_DEVELOPER_MODE=OFF \
  -DENABLE_MINIBROWSER=OFF -DENABLE_API_TESTS=OFF -DENABLE_JOURNALD_LOG=OFF \
  -DUSE_GSTREAMER=OFF -DUSE_WPE_RENDERER=OFF -DUSE_LIBSECRET=OFF \
  -DUSE_LIBNOTIFY=OFF -DUSE_LIBHYPHEN=OFF -DUSE_OPENJPEG=OFF \
  -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_INSTALL_LIBDIR=lib ..
ninja -j"$(nproc)"
ninja install && ldconfig
pkg-config --modversion webkit2gtk-4.1

# 打包成果：自编全家桶 + 运行库闭包
tar -cJf "$OUT/usrlocal.tar.xz" --exclude='usr/local/share' -C / usr/local
mkdir -p "$OUT/runtime-libs"
WEBKIT_SO=$(find /usr/local -name 'libwebkit2gtk-4.1.so.0' | head -1)
echo "webkit so: $WEBKIT_SO"
[ -n "$WEBKIT_SO" ] || { echo "找不到 libwebkit2gtk-4.1.so.0"; exit 1; }
for libpath in $(ldd "$WEBKIT_SO" /usr/local/lib/aarch64-linux-gnu/libsoup-3.0.so.0 2>/dev/null | awk '/=> \//{print $3}'); do
  base=$(basename $libpath)
  case "$base" in
    libc.so*|ld-linux*|libm.so*|libpthread*|libdl*|librt*|libresolv*) continue;;
  esac
  cp -Ln $libpath "$OUT/runtime-libs/" 2>/dev/null || true
done
cp -a /usr/local/lib/*.so* /usr/local/lib/aarch64-linux-gnu/*.so* "$OUT/runtime-libs/" 2>/dev/null || true 2>/dev/null || true
mkdir -p "$OUT/gio-modules" && cp -a /usr/local/lib/aarch64-linux-gnu/gio/modules/*.so "$OUT/gio-modules/" 2>/dev/null || true
tar -cJf "$OUT/runtime-libs.tar.xz" -C "$OUT" runtime-libs gio-modules
ls -lh "$OUT/"
echo "BUILD_DONE"
