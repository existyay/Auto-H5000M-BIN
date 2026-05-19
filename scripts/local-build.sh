#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="${REPO_URL:-https://github.com/padavanonly/immortalwrt-mt798x-24.10}"
REPO_BRANCH="${REPO_BRANCH:-mt798x-mt799x-6.6-mtwifi}"
CONFIG_URL="${CONFIG_URL:-https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/refs/heads/mt798x-mt799x-6.6-mtwifi/defconfig/mt7987_mt7992.config}"
SOURCE_DIR="${SOURCE_DIR:-immortalwrt}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-artifacts}"
THREADS="${THREADS:-$(nproc 2>/dev/null || echo 2)}"
GOPROXY="${GOPROXY:-https://goproxy.cn,https://proxy.golang.org,direct}"
export GOPROXY

ENABLE_ADGUARDHOME="${ENABLE_ADGUARDHOME:-false}"
ENABLE_OPENCLASH="${ENABLE_OPENCLASH:-false}"
ENABLE_NIKKI="${ENABLE_NIKKI:-true}"
ENABLE_UPNP="${ENABLE_UPNP:-true}"
ENABLE_VLMCSD="${ENABLE_VLMCSD:-true}"
ENABLE_MOSDNS="${ENABLE_MOSDNS:-true}"
ENABLE_DOCKERMAN="${ENABLE_DOCKERMAN:-false}"
ENABLE_QMODEM_NEXT="${ENABLE_QMODEM_NEXT:-true}"
ENABLE_QMODEM="${ENABLE_QMODEM:-false}"
ENABLE_MWAN="${ENABLE_MWAN:-true}"
ENABLE_HOMEPROXY="${ENABLE_HOMEPROXY:-false}"
ENABLE_ADBYBY_PLUS="${ENABLE_ADBYBY_PLUS:-false}"
ENABLE_ORIGINAL_MODEM="${ENABLE_ORIGINAL_MODEM:-false}"

INSTALL_DEPS=false
PREPARE_ONLY=false
CONFIG_ONLY=false
SKIP_TOOLCHAIN=false
SKIP_DOWNLOAD=false
SKIP_FEEDS_UPDATE=false

usage() {
  cat <<'EOF'
Usage: scripts/local-build.sh [options]

Options:
  --install-deps        Install Ubuntu/Debian build dependencies with apt-get.
  --prepare-only        Clone/update source, feeds, patches, and config only.
  --config-only         Stop after make defconfig and package verification.
  --skip-toolchain      Skip explicit make toolchain/install prebuild step.
  --skip-download       Skip make download prefetch step.
  --skip-feeds-update   Skip ./scripts/feeds update -a (use existing checkouts).
  -h, --help            Show this help.

Feature switches are controlled by environment variables, for example:
  ENABLE_MOSDNS=false ENABLE_QMODEM_NEXT=false THREADS=8 scripts/local-build.sh

Default feature switches match the scheduled GitHub Actions build.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-deps) INSTALL_DEPS=true ;;
    --prepare-only) PREPARE_ONLY=true ;;
    --config-only) CONFIG_ONLY=true ;;
    --skip-toolchain) SKIP_TOOLCHAIN=true ;;
    --skip-download) SKIP_DOWNLOAD=true ;;
    --skip-feeds-update) SKIP_FEEDS_UPDATE=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

sanitize_path() {
  local clean_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  [ -d /snap/bin ] && clean_path="$clean_path:/snap/bin"
  export PATH="$clean_path"
}

is_true() {
  [ "${1:-false}" = "true" ] || [ "${1:-false}" = "1" ] || [ "${1:-false}" = "yes" ]
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

install_deps() {
  log "Installing Ubuntu/Debian dependencies"
  command -v apt-get >/dev/null 2>&1 || die "--install-deps currently supports apt-get based systems only"
  sudo apt-get update
  sudo apt-get install -y build-essential git ccache python3 python3-pip \
    libncurses5-dev libssl-dev libgmp3-dev libmbedtls-dev rustc cargo \
    golang-go autoconf automake libtool patch make gcc g++ gawk gettext \
    unzip file wget curl rsync zstd
}

check_environment() {
  log "Checking local build environment"
  sanitize_path
  for cmd in git curl make sed awk grep find tar xargs; do
    require_cmd "$cmd"
  done

  if [ "$(uname -s)" != "Linux" ]; then
    die "OpenWrt builds require Linux. Run this script in WSL2 or a Linux host."
  fi

  local avail_gb
  avail_gb="$(df -BG "$ROOT_DIR" | awk 'NR==2 {gsub(/G/, "", $4); print $4}')"
  echo "Available disk at workspace: ${avail_gb:-unknown}GB"
  if [ -n "${avail_gb:-}" ] && [ "$avail_gb" -lt 20 ]; then
    echo "WARNING: OpenWrt builds are large; at least 20GB free space is recommended."
  fi
}

show_features() {
  log "Feature switches"
  cat <<EOF
AdGuardHome=${ENABLE_ADGUARDHOME}
OpenClash=${ENABLE_OPENCLASH}
Nikki=${ENABLE_NIKKI}
UPnP=${ENABLE_UPNP}
VLMCSd=${ENABLE_VLMCSD}
MosDNS=${ENABLE_MOSDNS}
DockerMan=${ENABLE_DOCKERMAN}
QModem Next=${ENABLE_QMODEM_NEXT}
QModem=${ENABLE_QMODEM}
MWAN=${ENABLE_MWAN}
HomeProxy=${ENABLE_HOMEPROXY}
Adbyby Plus=${ENABLE_ADBYBY_PLUS}
Original Modem=${ENABLE_ORIGINAL_MODEM}
EOF
}

prepare_source() {
  log "Preparing ImmortalWrt source"
  cd "$ROOT_DIR"

  if [ ! -d "$SOURCE_DIR/.git" ]; then
    rm -rf "$SOURCE_DIR"
    git clone -b "$REPO_BRANCH" --single-branch --depth=1 "$REPO_URL" "$SOURCE_DIR"
  else
    cd "$SOURCE_DIR"
    local current_branch
    current_branch="$(git branch --show-current)"
    if [ "$current_branch" != "$REPO_BRANCH" ]; then
      cd "$ROOT_DIR"
      rm -rf "$SOURCE_DIR"
      git clone -b "$REPO_BRANCH" --single-branch --depth=1 "$REPO_URL" "$SOURCE_DIR"
    else
      if git fetch origin "$REPO_BRANCH"; then
        git reset --hard FETCH_HEAD
        git clean -fd
      else
        log "WARNING: git fetch failed; using existing $SOURCE_DIR checkout"
      fi
      cd "$ROOT_DIR"
    fi
  fi
}

prepare_feeds() {
  log "Preparing feeds"
  cd "$ROOT_DIR/$SOURCE_DIR"

  cp "$ROOT_DIR/feeds.conf.default" ./feeds.conf.default

  if ! is_true "$ENABLE_NIKKI"; then
    sed -i '/src-git nikki/d; /nikki/d' feeds.conf.default
  fi

  if ! is_true "$ENABLE_QMODEM_NEXT" && ! is_true "$ENABLE_QMODEM"; then
    sed -i '/qmodem/d' feeds.conf.default
  fi

  rm -rf tmp/.config* tmp/.packageinfo tmp/.targetinfo tmp/info tmp/.feeds* 2>/dev/null || true
  ! is_true "$ENABLE_NIKKI" && rm -rf feeds/nikki* package/feeds/nikki 2>/dev/null || true
  ! is_true "$ENABLE_QMODEM_NEXT" && ! is_true "$ENABLE_QMODEM" && rm -rf feeds/qmodem* package/feeds/qmodem 2>/dev/null || true

  if is_true "$SKIP_FEEDS_UPDATE"; then
    log "Skipping ./scripts/feeds update -a (per --skip-feeds-update)"
  else
    ./scripts/feeds update -a || true
  fi
  if is_true "$ENABLE_MOSDNS" || is_true "$ENABLE_NIKKI"; then
    install_golang_feed
  fi
  ./scripts/feeds install -a -f || true
}

fix_qmi_driver() {
  local source_file="$1"
  [ -f "$source_file" ] || return 0
  sed -i 's/u64_stats_fetch_begin_irq/u64_stats_fetch_begin/g' "$source_file"
  sed -i 's/u64_stats_fetch_retry_irq/u64_stats_fetch_retry/g' "$source_file"
  if grep -q 'memcpy.*qmap_net->dev_addr.*real_dev->dev_addr' "$source_file"; then
    sed -i 's/memcpy[[:space:]]*(qmap_net->dev_addr,[[:space:]]*real_dev->dev_addr,[[:space:]]*ETH_ALEN);/eth_hw_addr_set(qmap_net, real_dev->dev_addr);/g' "$source_file"
  fi
  if grep -q 'memcpy.*->dev_addr' "$source_file"; then
    sed -i 's/memcpy[[:space:]]*(\([^,]*\)->dev_addr,[[:space:]]*\([^,]*\),[[:space:]]*ETH_ALEN);/dev_addr_set(\1, \2);/g' "$source_file" 2>/dev/null || true
  fi
}

patch_v2dat_go124() {
  local patch_dir="package/mosdns/v2dat/patches"
  [ -d "$patch_dir" ] || return 0
  local patch_files
  patch_files="$(grep -RIl 'go 1\.25\.0\|go 1\.24\|golang.org/x/sys v0\.42\.0' "$patch_dir" || true)"
  if [ -n "$patch_files" ]; then
    printf '%s\n' "$patch_files" | xargs sed -i \
      -e 's/go 1\.25\.0/go 1.24.0/g' \
      -e 's/^+go 1\.24$/+go 1.24.0\n+\n+toolchain go1.24.13/g' \
      -e 's/^@@ -1,8 +1,9 @@$/@@ -1,8 +1,11 @@/g' \
      -e 's|golang.org/x/sys v0\.42\.0 // indirect|golang.org/x/sys v0.37.0 // indirect|g' \
      -e 's|golang.org/x/sys v0\.42\.0 h1:omrd2nAlyT5ESRdCLYdm3+fMfNFE/+Rf4bDIQImRJeo=|golang.org/x/sys v0.37.0 h1:fdNQudmxPjkdUTPnLn5mdQv7Zwvbvpaxqs831goi9kQ=|g' \
      -e 's|golang.org/x/sys v0\.42\.0/go.mod h1:4GL1E5IUh+htKOUEOaiffhrAeqysfVGipDYzABqnCmw=|golang.org/x/sys v0.37.0/go.mod h1:OgkHotnGiDImocRcuBABYBEXf8A9a87e/uXjp9XT3ks=|g'
  fi
  rm -f "$patch_dir/999-fix-go-version-for-go124.patch"
  rm -rf build_dir/target-*/v2dat-* 2>/dev/null || true
}

patch_mtwifi_apcli_bssid_budget() {
  local patch_file="$ROOT_DIR/patches/mtwifi-apcli-active-only.patch"
  [ -f "$patch_file" ] || return 0

  if patch -p1 --forward --dry-run < "$patch_file" >/dev/null 2>&1; then
    patch -p1 < "$patch_file"
  elif patch -p1 --reverse --dry-run < "$patch_file" >/dev/null 2>&1; then
    log "MTK WiFi APCLI active-only patch already applied"
  else
    die "Unable to apply MTK WiFi APCLI active-only patch"
  fi
}

install_golang_feed() {
  local golang_dir="feeds/packages/lang/golang"
  if [ -f "$golang_dir/golang/Makefile" ] && [ -f "$golang_dir/golang-package.mk" ]; then
    rm -rf package/feeds/packages/golang
    mkdir -p package/feeds/packages
    ln -s ../../../feeds/packages/lang/golang/golang package/feeds/packages/golang
    return 0
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  if git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 24.x "$tmp_dir"; then
    rm -rf "$golang_dir"
    mv "$tmp_dir" "$golang_dir"
  else
    rm -rf "$tmp_dir"
  fi

  [ -f "$golang_dir/golang/Makefile" ] && [ -f "$golang_dir/golang-package.mk" ] || die "packages_lang_golang repository layout changed"

  rm -rf package/feeds/packages/golang
  mkdir -p package/feeds/packages
  ln -s ../../../feeds/packages/lang/golang/golang package/feeds/packages/golang
}

apply_package_fixes() {
  log "Applying package fixes"
  cd "$ROOT_DIR/$SOURCE_DIR"

  patch_mtwifi_apcli_bssid_budget

  local ebtables_makefile="package/network/utils/ebtables/Makefile"
  if [ -f "$ebtables_makefile" ] && grep -qE 'git(://|s://git\.)netfilter\.org/ebtables' "$ebtables_makefile"; then
    log "Patching ebtables Makefile to use GitHub mirror"
    sed -i 's|https://git.netfilter.org/ebtables|https://github.com/netfilter/ebtables.git|g' "$ebtables_makefile"
    sed -i 's|git://git.netfilter.org/ebtables|https://github.com/netfilter/ebtables.git|g' "$ebtables_makefile"
    sed -i 's|^PKG_MIRROR_HASH:=.*|PKG_MIRROR_HASH:=skip|g' "$ebtables_makefile"
  fi

  fix_qmi_driver "package/mtk/applications/5g-modem/fibocom_QMI_WWAN/qmi_wwan_f.c"
  fix_qmi_driver "package/mtk/applications/5g-modem/fibocom_QMI_WWAN/src/qmi_wwan_f.c"
  fix_qmi_driver "package/mtk/applications/5g-modem/quectel_QMI_WWAN/qmi_wwan_q.c"
  fix_qmi_driver "package/mtk/applications/5g-modem/quectel_QMI_WWAN/src/qmi_wwan_q.c"
  fix_qmi_driver "package/mtk/applications/5g-modem/simcom_QMI_WWAN/qmi_wwan_s.c"
  fix_qmi_driver "package/mtk/applications/5g-modem/simcom_QMI_WWAN/src/qmi_wwan_s.c"

  if [ -d "feeds/qmodem" ]; then
    while IFS= read -r driver_file; do
      fix_qmi_driver "$driver_file"
    done < <(find feeds/qmodem -name '*.c' -type f -print0 2>/dev/null | xargs -0 grep -l 'u64_stats_fetch_begin_irq\|memcpy.*dev_addr' 2>/dev/null || true)
  fi

  if is_true "$ENABLE_ADGUARDHOME"; then
    [ ! -d "package/luci-app-adguardhome" ] && git clone --depth=1 https://github.com/kongfl888/luci-app-adguardhome.git package/luci-app-adguardhome
    local agh_script="package/luci-app-adguardhome/root/usr/share/AdGuardHome/links.sh"
    [ -f "$agh_script" ] && sed -i 's|mv /usr/bin/AdGuardHome/AdGuardHome|rm -rf /usr/bin/AdGuardHome 2>/dev/null; mkdir -p /usr/bin/AdGuardHome; mv /tmp/AdGuardHomeupdate/AdGuardHome_linux_*/AdGuardHome|g' "$agh_script" || true
  fi

  if is_true "$ENABLE_ADBYBY_PLUS"; then
    if [ ! -d "package/luci-app-adbyby-plus" ]; then
      rm -rf /tmp/adbyby-plus-lite
      git clone --depth=1 --recurse-submodules https://github.com/kongfl888/luci-app-adbyby-plus-lite.git /tmp/adbyby-plus-lite
      [ -d "/tmp/adbyby-plus-lite/luci-app-adbyby-plus" ] || die "Adbyby Plus Lite repository layout changed"
      cp -r /tmp/adbyby-plus-lite/luci-app-adbyby-plus package/luci-app-adbyby-plus
      rm -rf /tmp/adbyby-plus-lite
    fi
  fi

  if is_true "$ENABLE_MOSDNS"; then
    install_golang_feed
    rm -rf feeds/packages/net/v2ray-geodata
    [ ! -d "package/mosdns" ] && git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
    patch_v2dat_go124
    [ ! -d "package/v2ray-geodata" ] && git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
  fi

  rm -rf package/feeds/packages/{exim,onionshare-cli,python-zope-event,python-zope-interface,python-gevent,python-twisted} 2>/dev/null || true

  if is_true "$ENABLE_VLMCSD"; then
    ./scripts/feeds install -f vlmcsd || true
    ./scripts/feeds install -f luci-app-vlmcsd || true
  fi

  if is_true "$ENABLE_NIKKI"; then
    rm -rf feeds/nikki/mihomo-alpha package/feeds/nikki/mihomo-alpha 2>/dev/null || true
    [ -f "feeds/nikki/mihomo-meta/Makefile" ] && sed -i '/^[[:space:]]*CONFLICTS:=mihomo-alpha/d' "feeds/nikki/mihomo-meta/Makefile" || true
    [ -f "package/feeds/nikki/mihomo-meta/Makefile" ] && sed -i '/^[[:space:]]*CONFLICTS:=mihomo-alpha/d' "package/feeds/nikki/mihomo-meta/Makefile" || true
    rm -rf tmp/.config* tmp/.packageinfo tmp/info/.packageinfo* 2>/dev/null || true
  fi

  if [ -d "package/feeds/qmodem" ]; then
    rm -rf package/feeds/qmodem/ndisc6 2>/dev/null || true
    find . -path '*qmodem*Makefile' -exec sed -i 's/+\?kmod-mhi-wwan//g' {} \; 2>/dev/null || true
  fi

  [ -f "package/mtk/drivers/mt_hwifi/Makefile" ] && sed -i 's/+kmod-mt_wifi_osal//g' "package/mtk/drivers/mt_hwifi/Makefile" || true
}

config_enable() {
  local symbol="$1"
  ./scripts/config --file .config -e "$symbol" 2>/dev/null || {
    sed -i "/^CONFIG_${symbol}=/d; /^# CONFIG_${symbol} is not set/d" .config
    echo "CONFIG_${symbol}=y" >> .config
  }
}

config_disable() {
  local symbol="$1"
  ./scripts/config --file .config -d "$symbol" 2>/dev/null || {
    sed -i "/^CONFIG_${symbol}=/d; /^# CONFIG_${symbol} is not set/d" .config
    echo "# CONFIG_${symbol} is not set" >> .config
  }
}

configure_build() {
  log "Configuring build"
  cd "$ROOT_DIR/$SOURCE_DIR"

  if is_true "$ENABLE_QMODEM_NEXT" && is_true "$ENABLE_QMODEM"; then
    die "ENABLE_QMODEM_NEXT and ENABLE_QMODEM cannot both be true"
  fi
  if is_true "$ENABLE_ORIGINAL_MODEM" && { is_true "$ENABLE_QMODEM_NEXT" || is_true "$ENABLE_QMODEM"; }; then
    die "ENABLE_ORIGINAL_MODEM conflicts with QModem options"
  fi

  curl -fsSL "$CONFIG_URL" -o base.config || {
    [ -f "defconfig/mt7987_mt7992.config" ] && cp defconfig/mt7987_mt7992.config base.config
  }
  [ -f base.config ] || die "Unable to fetch or locate base config"

  cp base.config .config
  [ -f "$ROOT_DIR/h5000m.extra.config" ] && cat "$ROOT_DIR/h5000m.extra.config" >> .config

  local disabled_pkgs=("luci-app-sms-tool-lite" "luci-app-3ginfo-lite")

  if is_true "$ENABLE_NIKKI"; then
    cat >> .config <<'EOF'
CONFIG_PACKAGE_nikki=y
CONFIG_PACKAGE_luci-app-nikki=y
CONFIG_PACKAGE_luci-i18n-nikki-zh-cn=y
# CONFIG_PACKAGE_mihomo-alpha is not set
CONFIG_PACKAGE_mihomo-meta=y
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_yq=y
CONFIG_PACKAGE_firewall4=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_kmod-inet-diag=y
CONFIG_PACKAGE_kmod-nft-socket=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
CONFIG_PACKAGE_kmod-tun=y
EOF
  else
    disabled_pkgs+=("nikki" "luci-app-nikki" "luci-i18n-nikki-zh-cn" "luci-i18n-nikki-en")
  fi

  is_true "$ENABLE_ADGUARDHOME" && { echo "CONFIG_PACKAGE_luci-app-adguardhome=y" >> .config; echo "CONFIG_PACKAGE_luci-i18n-adguardhome-zh-cn=y" >> .config; } || disabled_pkgs+=("luci-app-adguardhome" "luci-i18n-adguardhome-zh-cn")
  is_true "$ENABLE_OPENCLASH" && echo "CONFIG_PACKAGE_luci-app-openclash=y" >> .config || disabled_pkgs+=("luci-app-openclash")
  is_true "$ENABLE_UPNP" && echo "CONFIG_PACKAGE_luci-app-upnp=y" >> .config || disabled_pkgs+=("luci-app-upnp")
  is_true "$ENABLE_VLMCSD" && { echo "CONFIG_PACKAGE_luci-app-vlmcsd=y" >> .config; echo "CONFIG_PACKAGE_vlmcsd=y" >> .config; } || disabled_pkgs+=("luci-app-vlmcsd" "vlmcsd")
  is_true "$ENABLE_MOSDNS" && echo "CONFIG_PACKAGE_luci-app-mosdns=y" >> .config || disabled_pkgs+=("luci-app-mosdns")
  is_true "$ENABLE_MWAN" && echo "CONFIG_PACKAGE_luci-app-mwan3=y" >> .config || disabled_pkgs+=("luci-app-mwan3")
  is_true "$ENABLE_HOMEPROXY" && echo "CONFIG_PACKAGE_luci-app-homeproxy=y" >> .config || disabled_pkgs+=("luci-app-homeproxy")
  is_true "$ENABLE_ADBYBY_PLUS" && { echo "CONFIG_PACKAGE_luci-app-adbyby-plus=y" >> .config; echo "CONFIG_PACKAGE_luci-i18n-adbyby-plus-zh-cn=y" >> .config; echo "CONFIG_PACKAGE_ipset=y" >> .config; } || disabled_pkgs+=("luci-app-adbyby-plus" "luci-i18n-adbyby-plus-zh-cn")

  if is_true "$ENABLE_DOCKERMAN"; then
    cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_luci-lib-docker=y
CONFIG_PACKAGE_docker=y
CONFIG_PACKAGE_dockerd=y
CONFIG_PACKAGE_containerd=y
CONFIG_PACKAGE_runc=y
EOF
  else
    disabled_pkgs+=("luci-app-dockerman" "luci-lib-docker")
  fi

  if is_true "$ENABLE_ORIGINAL_MODEM"; then
    echo "CONFIG_PACKAGE_luci-app-modem=y" >> .config
    echo "CONFIG_PACKAGE_modem=y" >> .config
    echo "CONFIG_PACKAGE_luci-i18n-modem-zh-cn=y" >> .config
  else
    disabled_pkgs+=("luci-app-modem" "modem" "luci-i18n-modem-zh-cn" "luci-i18n-modem-en")
  fi

  if is_true "$ENABLE_QMODEM_NEXT"; then
    echo "CONFIG_PACKAGE_luci-app-qmodem-next=y" >> .config
  elif is_true "$ENABLE_QMODEM"; then
    cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-app-qmodem=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_qmodem=y
CONFIG_PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan=y
# CONFIG_PACKAGE_luci-app-qmodem_INCLUDE_generic-qmi-wwan is not set
CONFIG_PACKAGE_luci-app-qmodem_INCLUDE_ndisc6=y
# CONFIG_PACKAGE_luci-app-qmodem_INCLUDE_rdisc6 is not set
# CONFIG_PACKAGE_luci-app-qmodem_INCLUDE_no_ndisc_rdisc6 is not set
CONFIG_PACKAGE_ndisc6=y
CONFIG_PACKAGE_luci-app-qmodem_USE_TOM_CUSTOMIZED_QUECTEL_CM=y
# CONFIG_PACKAGE_luci-app-qmodem_USING_QWRT_QUECTEL_CM_5G is not set
# CONFIG_PACKAGE_luci-app-qmodem_USING_NORMAL_QUECTEL_CM is not set
CONFIG_PACKAGE_quectel-CM-5G-M=y
CONFIG_PACKAGE_sms-tool_q=y
CONFIG_PACKAGE_ubus-at-daemon=y
CONFIG_PACKAGE_tom_modem=y
CONFIG_PACKAGE_kmod-qmi_wwan_q=y
CONFIG_PACKAGE_kmod-qmi_wwan_f=y
CONFIG_PACKAGE_kmod-qmi_wwan_s=y
CONFIG_PACKAGE_mwan3=y
CONFIG_PACKAGE_luci-app-mwan3=y
CONFIG_PACKAGE_mtkhqos_util=y
EOF
  else
    disabled_pkgs+=("luci-app-qmodem-next" "luci-app-qmodem")
  fi

  local all_disabled=("luci-app-wrtbwmon" "luci-app-rclone" "rclone" "rclone-ng" "rclone-webui-react" "${disabled_pkgs[@]}")
  local pkg
  for pkg in "${all_disabled[@]}"; do
    sed -i "/^CONFIG_PACKAGE_${pkg}=/d" .config
    echo "# CONFIG_PACKAGE_${pkg} is not set" >> .config
  done

  if is_true "$ENABLE_NIKKI"; then
    config_disable PACKAGE_mihomo-alpha
    config_enable PACKAGE_mihomo-meta
    config_enable PACKAGE_nikki
    config_enable PACKAGE_luci-app-nikki
    config_enable PACKAGE_luci-i18n-nikki-zh-cn
  fi

  if is_true "$ENABLE_VLMCSD"; then
    config_enable PACKAGE_vlmcsd
    config_enable PACKAGE_luci-app-vlmcsd
  fi

  make defconfig

  if is_true "$ENABLE_VLMCSD" && ! grep -q '^CONFIG_PACKAGE_luci-app-vlmcsd=y$' .config; then
    ./scripts/feeds install -f vlmcsd || true
    ./scripts/feeds install -f luci-app-vlmcsd || true
    config_enable PACKAGE_vlmcsd
    config_enable PACKAGE_luci-app-vlmcsd
    make defconfig
  fi

  verify_enabled_pkg "Nikki" "luci-app-nikki" "$ENABLE_NIKKI"
  verify_enabled_pkg "UPnP" "luci-app-upnp" "$ENABLE_UPNP"
  verify_enabled_pkg "VLMCSd" "luci-app-vlmcsd" "$ENABLE_VLMCSD"
  verify_enabled_pkg "MosDNS" "luci-app-mosdns" "$ENABLE_MOSDNS"
  verify_enabled_pkg "DockerMan" "luci-app-dockerman" "$ENABLE_DOCKERMAN"
  verify_enabled_pkg "QModem Next" "luci-app-qmodem-next" "$ENABLE_QMODEM_NEXT"
  verify_enabled_pkg "MWAN" "luci-app-mwan3" "$ENABLE_MWAN"
  verify_enabled_pkg "HomeProxy" "luci-app-homeproxy" "$ENABLE_HOMEPROXY"
  verify_enabled_pkg "Adbyby Plus" "luci-app-adbyby-plus" "$ENABLE_ADBYBY_PLUS"
}

verify_enabled_pkg() {
  local feature_name="$1"
  local config_name="$2"
  local enabled="$3"
  if is_true "$enabled" && ! grep -q "^CONFIG_PACKAGE_${config_name}=y$" .config; then
    echo "${feature_name} requested but CONFIG_PACKAGE_${config_name}=y is not active after defconfig" >&2
    grep -n "PACKAGE_${config_name}" .config || true
    exit 1
  fi
}

prefetch_and_toolchain() {
  cd "$ROOT_DIR/$SOURCE_DIR"
  if ! is_true "$SKIP_DOWNLOAD"; then
    log "Downloading package sources"
    find dl -size -1024c -delete 2>/dev/null || true
    for attempt in 1 2 3; do
      make download -j"$THREADS" && break
      find dl -size -1024c -delete 2>/dev/null || true
      [ "$attempt" -eq 3 ] && echo "WARNING: make download did not complete cleanly"
    done
  fi

  if ! is_true "$SKIP_TOOLCHAIN"; then
    log "Prebuilding toolchain if needed"
    [ -d "staging_dir" ] && [ -n "$(ls -A staging_dir 2>/dev/null)" ] && echo "Toolchain/cache directories already exist" || make toolchain/install -j"$THREADS" || true
  fi
}

clean_v2dat_go_mod_cache() {
  rm -rf \
    dl/go-mod-cache/github.com/edsrzf/mmap-go@v1.2.0 \
    dl/go-mod-cache/github.com/inconshreveable/mousetrap@v1.1.0 \
    dl/go-mod-cache/github.com/spf13/cobra@v1.10.2 \
    dl/go-mod-cache/github.com/spf13/pflag@v1.0.10 \
    dl/go-mod-cache/go.uber.org/multierr@v1.11.0 \
    dl/go-mod-cache/go.uber.org/zap@v1.27.1 \
    dl/go-mod-cache/golang.org/x/sys@v0.37.0 \
    dl/go-mod-cache/google.golang.org/protobuf@v1.36.11 2>/dev/null || true
}

clean_go_mod_cache() {
  rm -rf dl/go-mod-cache tmp/go-build 2>/dev/null || true
}

precompile_v2dat() {
  is_true "$ENABLE_MOSDNS" || return 0
  [ -d "package/mosdns/v2dat" ] || return 0
  log "Precompiling MosDNS v2dat with a clean Go module cache"
  clean_v2dat_go_mod_cache
  make package/mosdns/v2dat/clean V=s || true
  make package/mosdns/v2dat/compile V=s
}

compile_firmware() {
  log "Compiling firmware with ${THREADS} threads"
  cd "$ROOT_DIR/$SOURCE_DIR"
  sanitize_path
  export PATH="/usr/lib/ccache:$PATH"

  log "Cleaning Go module cache before Go package builds"
  clean_go_mod_cache
  precompile_v2dat

  local start_time end_time duration
  start_time="$(date +%s)"
  if make -j"$THREADS" IGNORE_ERRORS=n; then
    end_time="$(date +%s)"
    duration=$((end_time - start_time))
    echo "Build succeeded in ${duration}s"
  else
    echo "Parallel build failed; running focused diagnostics before single-thread retry"
    if is_true "$ENABLE_MOSDNS"; then
      grep -RIn 'go 1\.' package/mosdns/v2dat/patches || true
      clean_v2dat_go_mod_cache
      make package/mosdns/v2dat/clean V=s || true
      if ! make package/mosdns/v2dat/compile V=s; then
        find build_dir -path '*v2dat*/go.mod' -exec sh -c 'echo "--- $1"; sed -n "1,40p" "$1"' _ {} \; || true
        die "MosDNS v2dat failed to compile"
      fi
    fi
    make -j1 V=s
  fi
}

collect_artifacts() {
  log "Collecting firmware artifacts"
  cd "$ROOT_DIR"
  rm -rf "$ARTIFACTS_DIR"
  mkdir -p "$ARTIFACTS_DIR"

  find "$SOURCE_DIR/bin/targets" -type f \( -name '*.bin' -o -name '*.img.gz' \) -exec cp -f {} "$ARTIFACTS_DIR/" \;
  if [ -z "$(ls -A "$ARTIFACTS_DIR" 2>/dev/null)" ]; then
    die "No firmware artifacts found under $SOURCE_DIR/bin/targets"
  fi

  {
    echo "ImmortalWrt H5000M local build"
    echo "Build time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Source: $REPO_URL ($REPO_BRANCH)"
    echo
    echo "Artifacts:"
    (cd "$ARTIFACTS_DIR" && ls -lh | sed 's/^/  /')
  } > "$ARTIFACTS_DIR/MANIFEST.txt"

  tar -czf artifacts.tar.gz "$ARTIFACTS_DIR"
  ls -lh "$ARTIFACTS_DIR"
  echo "Artifacts archive: $ROOT_DIR/artifacts.tar.gz"
}

main() {
  cd "$ROOT_DIR"
  is_true "$INSTALL_DEPS" && install_deps
  check_environment
  show_features
  prepare_source
  prepare_feeds
  apply_package_fixes
  configure_build
  is_true "$PREPARE_ONLY" && { log "Prepare-only requested; stopping before downloads/build"; exit 0; }
  is_true "$CONFIG_ONLY" && { log "Config-only requested; stopping before downloads/build"; exit 0; }
  prefetch_and_toolchain
  compile_firmware
  collect_artifacts
}

main "$@"