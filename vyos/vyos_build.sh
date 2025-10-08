#!/usr/bin/env bash
# vyos_build.sh
# ------------------------------------------------------------
# VyOS の ISO を自動でダウンロード→展開→rootfs.tar 化→
# Docker イメージ化（FROM scratch + /sbin/init）まで一気通貫で実行。
#
# 使い方（例）:
#   chmod +x vyos_build.sh
#   ./vyos_build.sh \
#     --version 2025.10.01-0021 \
#     --channel rolling \
#     --arch amd64 \
#     --tag vyos:rolling-2025.10.01 \
#     --workdir ~/vyos
#
# 既に ISO を持っている場合:
#   ./vyos_build.sh --iso ~/vyos/vyos-2025.10.01-0021-rolling-generic-amd64.iso --tag vyos:rolling-2025.10.01
#
# 依存コマンド: curl, sha256sum, unsquashfs(squashfs-tools), tar, docker
#   ※ bsdtar(推奨) or 7z があれば ISO から live/filesystem.squashfs をマウント無しで抽出可能
#   ※ どれも無ければ最後の手段として sudo mount -o loop でマウントして抽出
# ------------------------------------------------------------
set -euo pipefail

# ========== デフォルト値 ==========
VERSION=""
CHANNEL="rolling"          # rolling or current など
ARCH="amd64"
TAG=""
WORKDIR="$HOME/vyos"
ISO_PATH=""
VERBOSE=false

# ========== ログ関数 ==========
log() { echo -e "[\e[1;32mINFO\e[0m] $*"; }
warn(){ echo -e "[\e[1;33mWARN\e[0m] $*"; }
err() { echo -e "[\e[1;31mERR \e[0m] $*" 1>&2; }
vecho(){ $VERBOSE && echo "[DBG ] $*" || true; }

# ========== 引数パース ==========
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2;;
    --channel) CHANNEL="$2"; shift 2;;
    --arch)    ARCH="$2"; shift 2;;
    --tag)     TAG="$2"; shift 2;;
    --workdir) WORKDIR="$2"; shift 2;;
    --iso)     ISO_PATH="$2"; shift 2;;
    -v|--verbose) VERBOSE=true; shift;;
    -h|--help)
      sed -n '1,120p' "$0"; exit 0;;
    *) err "unknown arg: $1"; exit 1;;
  esac
done

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ========== 依存関係チェック ==========
need() {
  if ! command -v "$1" >/dev/null 2>&1; then err "require '$1' not found"; return 1; fi
}
need curl
need tar
need docker
need sha256sum || true

HAS_BSDTAR=false; command -v bsdtar >/dev/null 2>&1 && HAS_BSDTAR=true
HAS_7Z=false;    command -v 7z      >/dev/null 2>&1 && HAS_7Z=true
HAS_UNSQUASH=false; command -v unsquashfs >/dev/null 2>&1 && HAS_UNSQUASH=true

if ! $HAS_UNSQUASH; then
  err "unsquashfs (squashfs-tools) が必要です。 sudo apt-get install -y squashfs-tools"
  exit 1
fi

# ========== ISO URL 推定（未指定時） ==========
# 公式の nightly/rolling の URL 体系は変更されがちなので、ここでは変数を構成しつつ
# 最終的にユーザが --iso を直接渡すか、--iso-url を自分で埋める想定。

# ISO 名を決定
ISO_BASENAME=""
if [[ -n "$VERSION" ]]; then
  ISO_BASENAME="vyos-${VERSION}-${CHANNEL}-generic-${ARCH}.iso"
fi

# 既存 ISO の優先
if [[ -n "$ISO_PATH" ]]; then
  if [[ ! -f "$ISO_PATH" ]]; then err "--iso で指定したファイルが見つかりません: $ISO_PATH"; exit 1; fi
  ISO_FILE="$ISO_PATH"
else
  if [[ -z "$VERSION" ]]; then
    err "--version か --iso のどちらかは必須です"
    exit 1
  fi
  ISO_FILE="$WORKDIR/$ISO_BASENAME"
fi

# ========== ISO ダウンロード（必要時） ==========
# NOTE: VyOS のダウンロード URL はビルド環境によって変わるため、ここでは代表例のパス候補を用意。
# 失敗したら README を参照して実際の URL に置き換えるか、--iso でローカルパスを渡してください。

try_download_iso() {
  local url="$1"
  log "Try downloading ISO from: $url"
  if curl -fL "$url" -o "$ISO_FILE"; then
    log "Downloaded: $ISO_FILE"
    return 0
  else
    warn "Failed: $url"
    return 1
  fi
}

if [[ ! -f "$ISO_FILE" ]]; then
  log "ISO not found locally. Trying to download..."
  # 候補1: （例）community mirror / artifacts (要調整)
  CANDIDATES=(
    "https://downloads.vyos.io/rolling/${VERSION}/$ISO_BASENAME"
    "https://downloads.vyos.io/rolling/current/$ISO_BASENAME"
    "https://github.com/vyos/vyos-nightly-build/releases/download/${VERSION}/$ISO_BASENAME"
  )
  DL_OK=false
  for u in "${CANDIDATES[@]}"; do
    if try_download_iso "$u"; then DL_OK=true; break; fi
  done
  if ! $DL_OK; then
    err "ISO 自動取得に失敗しました。URL が変わっている可能性があります。--iso でローカル ISO を指定してください。期待ファイル名: $ISO_BASENAME"
    exit 1
  fi
else
  log "Reuse existing ISO: $ISO_FILE"
fi

# ========== checksum 検証（可能なら） ==========
try_verify_checksum() {
  local baseurl
  baseurl=$(dirname "$1")
  local sha_url="$baseurl/sha256sum.txt"
  vecho "try sha256 url: $sha_url"
  if curl -fsSL "$sha_url" -o sha256sum.txt; then
    if command -v sha256sum >/dev/null 2>&1; then
      if grep -q "$ISO_BASENAME" sha256sum.txt; then
        log "Verify sha256..."
        (grep "$ISO_BASENAME" sha256sum.txt | sha256sum -c -) || { err "sha256 mismatch"; exit 1; }
        log "sha256 OK"
        return 0
      fi
    fi
  fi
  warn "Checksum file not found or verification skipped"
  return 0
}

# 可能なら検証
if [[ -f "$ISO_FILE" && -n "$VERSION" ]]; then
  try_verify_checksum "${CANDIDATES[0]}" || true
fi

# ========== ISO から live/filesystem.squashfs を抽出 ==========
SQUASHFS_PATH="$WORKDIR/filesystem.squashfs"
if [[ -f "$SQUASHFS_PATH" ]]; then
  log "Reuse existing squashfs: $SQUASHFS_PATH"
else
  log "Extract live/filesystem.squashfs from ISO"
  if $HAS_BSDTAR; then
    bsdtar -xf "$ISO_FILE" "live/filesystem.squashfs" -O > "$SQUASHFS_PATH" || {
      warn "bsdtar stream extract failed; try file extract"
      bsdtar -xf "$ISO_FILE" "live/filesystem.squashfs"
      mv -f live/filesystem.squashfs "$SQUASHFS_PATH"
    }
  elif $HAS_7Z; then
    7z e -y -o"$WORKDIR" "$ISO_FILE" live/filesystem.squashfs >/dev/null
    mv -f "$WORKDIR/live/filesystem.squashfs" "$SQUASHFS_PATH"
  else
    warn "bsdtar/7z なし → ループマウントで抽出 (sudo 必要)"
    mkdir -p "$WORKDIR/mnt"
    sudo mount -o loop "$ISO_FILE" "$WORKDIR/mnt"
    cp "$WORKDIR/mnt/live/filesystem.squashfs" "$SQUASHFS_PATH"
    sudo umount "$WORKDIR/mnt"
  fi
  log "Extracted: $SQUASHFS_PATH"
fi

# ========== squashfs 展開 → rootfs.tar 作成 ==========
ROOTFS_DIR="$WORKDIR/rootfs"
ROOTFS_TAR="$WORKDIR/rootfs.tar"
if [[ -f "$ROOTFS_TAR" ]]; then
  log "Reuse existing rootfs.tar: $ROOTFS_TAR"
else
  rm -rf "$ROOTFS_DIR" && mkdir -p "$ROOTFS_DIR"
  log "unsquashfs → $ROOTFS_DIR"
  unsquashfs -f -d "$ROOTFS_DIR" "$SQUASHFS_PATH"
  log "Create rootfs.tar"
  tar -C "$ROOTFS_DIR" -cf "$ROOTFS_TAR" .
fi

# ========== Dockerfile 生成（なければ） ==========
DOCKERFILE="$WORKDIR/Dockerfile"
if [[ ! -f "$DOCKERFILE" ]]; then
  cat > "$DOCKERFILE" <<'EOF'
FROM scratch
ADD rootfs.tar /
CMD ["/sbin/init"]
EOF
  log "Wrote Dockerfile"
fi

# ========== Docker ビルド ==========
if [[ -z "$TAG" ]]; then
  if [[ -n "$VERSION" ]]; then
    TAG="vyos:${CHANNEL}-${VERSION%%-*}"
  else
    TAG="vyos:custom"
  fi
fi

log "docker build -t $TAG ."
docker build -t "$TAG" .

# ========== 動作テスト（任意） ==========
log "Quick test: run container (Ctrl+C to stop)"
set +e
if docker run --rm -it "$TAG" /bin/sh -lc 'cat /etc/os-release 2>/dev/null || true; ps aux | head -n 5'; then
  log "Container started successfully (light check)."
else
  warn "Container exited or /sbin/init not PID1 in test shell. For full system init, run without command: docker run -it $TAG"
fi
set -e

log "DONE. Built image: $TAG"

# ========== 参考: containerlab ノード指定（lab1.yml の例） ==========
cat <<'HINT'

# --- containerlab example snippet ---
#   nodes:
#    r1:
#     kind: vyosnetworks_vyos
#     image: vyos:rolling-2025.10.01
#     startup-config: configs/r1.boot
#     ports: ["2221:22"]

HINT

