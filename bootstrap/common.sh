#!/bin/bash

set -euo pipefail

# 这里集中定义所有 bootstrap 阶段共享的环境变量、路径、日志函数和辅助函数。
# 任何阶段脚本都只需要 source 这一份公共文件，避免重复定义和行为漂移。

export TZ="${TZ:-Asia/Shanghai}"
export OPENCLAW_TZ="${OPENCLAW_TZ:-Asia/Shanghai}"

# OpenClaw 的运行状态目录和配置文件路径。
# Dockerfile、entrypoint、sync-watch 和所有 bootstrap 阶段都依赖这两个变量。
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/root/.openclaw}"
export OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"

CONFIG="$OPENCLAW_CONFIG_PATH"
OPENCLAW_DIR="$OPENCLAW_STATE_DIR"
LOCAL_TEMPLATE_DIR="/opt/bootstrap-assets"
LOCAL_OPENCLAW_TEMPLATE="$LOCAL_TEMPLATE_DIR/openclaw.json"
# HF Buckets 的仓库配置，默认指向当前 worker 的持久化数据集。
BUCKET_REPO="${BUCKET_REPO:-EmilyReed96989/OpenClaw-Worker-Storage}"
BUCKET_TYPE="${BUCKET_TYPE:-dataset}"
IP_RECORD="$OPENCLAW_DIR/.last_outbound_ip"

# wechat-allauto-gzh 项目路径和凭证文件路径。
WECHAT_ALLAUTO_GZH_REPO_URL="${WECHAT_ALLAUTO_GZH_REPO_URL:-https://github.com/Viciy2023/wechat-allauto-gzh.git}"
WECHAT_ALLAUTO_GZH_BRANCH="${WECHAT_ALLAUTO_GZH_BRANCH:-main}"
WECHAT_ALLAUTO_GZH_DIR="$OPENCLAW_DIR/workspace/wechat-allauto-gzh"
WECHAT_CREDS_FILE="$WECHAT_ALLAUTO_GZH_DIR/credentials.json"

# 构建期必须预装、运行期也必须通过校验的 ClawHub skills。
# Tavily 在当前方案里只要求安装 Python SDK（tavily-python），
# 不强制要求 ClawHub 内存在名为 tavily-search 的 skill。
CLAWHUB_SKILLS=(ddg-web-search n2-free-search)

# 首次启动标记通过临时文件在多个 bootstrap 子脚本之间传递，
# 因为每个阶段脚本都是独立进程，不能依赖 shell 变量自动继承回写。
FIRST_RUN="${FIRST_RUN:-false}"
VERIFY_FAILURES=0
FIRST_RUN_FLAG_FILE="/tmp/openclaw-first-run.flag"

hf_cli() {
  if command -v hf >/dev/null 2>&1; then
    hf "$@"
  elif command -v huggingface-cli >/dev/null 2>&1; then
    huggingface-cli "$@"
  else
    fail "未找到 Hugging Face CLI（hf 或 huggingface-cli）"
  fi
}

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

warn() {
  log "⚠️  $*"
}

# 统一失败出口，任何关键阶段无法继续时都从这里退出。
fail() {
  log "❌ $*"
  exit 1
}

# 统一记录运行时验证失败次数，最后由 verify 阶段决定是否阻断启动。
mark_verify_failure() {
  VERIFY_FAILURES=$((VERIFY_FAILURES + 1))
}

# 通用重试函数，适合 git clone/pull 这类易受临时网络抖动影响的命令。
retry() {
  local attempts="$1"
  local delay_secs="$2"
  shift 2

  local attempt
  for attempt in $(seq 1 "$attempts"); do
    if "$@"; then
      return 0
    fi
    if [ "$attempt" -lt "$attempts" ]; then
      warn "命令失败，第 ${attempt}/${attempts} 次，${delay_secs}s 后重试: $*"
      sleep "$delay_secs"
    fi
  done
  return 1
}

# 优先走全局 openclaw 命令，找不到时退回 node /app/openclaw.mjs。
# 这样既兼容镜像内 PATH，也兼容调试场景。
run_openclaw() {
  if command -v openclaw >/dev/null 2>&1; then
    openclaw "$@"
  else
    node /app/openclaw.mjs "$@"
  fi
}

ensure_dir() {
  mkdir -p "$1"
}

# 下面几组 check_* 函数用于运行时完整性校验，
# 区别是它们只记录失败，不会当场退出，由 verify 阶段统一收口。
check_required_dir() {
  local path="$1"
  local label="$2"
  if [ -d "$path" ]; then
    log "✅ ${label}: ${path}"
  else
    log "❌ ${label}: 缺失目录 ${path}"
    mark_verify_failure
  fi
}

check_required_file() {
  local path="$1"
  local label="$2"
  if [ -f "$path" ]; then
    log "✅ ${label}: ${path}"
  else
    log "❌ ${label}: 缺失文件 ${path}"
    mark_verify_failure
  fi
}

check_optional_command() {
  local command_name="$1"
  local label="$2"
  if command -v "$command_name" >/dev/null 2>&1; then
    log "✅ ${label}: $(command -v "$command_name")"
  else
    warn "${label}: 未找到命令 ${command_name}"
  fi
}

# clone 或更新外部仓库，供 wechat-allauto-gzh 这种运行期项目使用。
clone_or_update_repo() {
  local repo_url="$1"
  local branch="$2"
  local target_dir="$3"

  mkdir -p "$(dirname "$target_dir")"
  if [ -d "$target_dir/.git" ]; then
    log "=== 更新仓库: ${target_dir} ==="
    git -C "$target_dir" fetch origin "$branch"
    git -C "$target_dir" checkout "$branch"
    git -C "$target_dir" pull --ff-only origin "$branch"
  else
    log "=== 克隆仓库: ${repo_url} -> ${target_dir} ==="
    rm -rf "$target_dir"
    git clone --depth 1 --branch "$branch" "$repo_url" "$target_dir"
  fi
}

# 写入微信公众号 credentials.json，供 wechat-allauto-gzh 在运行期直接调用。
write_wechat_credentials() {
  if [ -z "${WECHAT_APP_ID:-}" ] || [ -z "${WECHAT_APP_SECRET:-}" ]; then
    warn "WECHAT_APP_ID 或 WECHAT_APP_SECRET 未设置，跳过凭证写入"
    return 1
  fi

  mkdir -p "$WECHAT_ALLAUTO_GZH_DIR"
  cat > "$WECHAT_CREDS_FILE" <<EOF
{
  "AppID": "${WECHAT_APP_ID}",
  "AppSecret": "${WECHAT_APP_SECRET}"
}
EOF
  chmod 600 "$WECHAT_CREDS_FILE"
  log "✅ 微信公众号凭证已写入: ${WECHAT_CREDS_FILE}"
}
