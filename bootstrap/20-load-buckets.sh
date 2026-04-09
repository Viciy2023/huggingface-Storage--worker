#!/bin/bash

set -euo pipefail

source /bootstrap/common.sh

# 第二阶段：优先从 HF Buckets 恢复上一次运行留下的状态。
# 这是 storage worker 最核心的职责，优先级高于 GitHub 默认文件预置。
log "=== 从 HF Buckets 加载持久化数据 ==="

if [ -z "${HF_TOKEN:-}" ]; then
  warn "HF_TOKEN 未设置，跳过 Buckets 加载，将使用镜像内默认文件"
  exit 0
fi

restore_bucket_patterns() {
  local destination_dir="$1"
  shift
  local patterns=("$@")

  python3 - <<'PY'
import os
import sys
from huggingface_hub import snapshot_download

repo_id = os.environ["BUCKET_REPO"]
repo_type = os.environ["BUCKET_TYPE"]
token = os.environ["HF_TOKEN"]
destination_dir = os.environ["RESTORE_DESTINATION_DIR"]
patterns = [p for p in os.environ.get("RESTORE_PATTERNS", "").split("\n") if p]

snapshot_download(
    repo_id=repo_id,
    repo_type=repo_type,
    token=token,
    local_dir=destination_dir,
    allow_patterns=patterns,
)
PY
}

# 不再只用 openclaw.json 作为唯一探针，因为你可能先上传的是 workspace/cron/extensions。
# 这里优先探测 workspace、cron、extensions 任一目录是否存在，再决定 Buckets 是否已有持久化数据。
BUCKET_HAS_DATA="no"
for probe_path in "workspace/*" "cron/*" "extensions/*" "skills/*" "openclaw.json"; do
  export RESTORE_DESTINATION_DIR="/tmp/hf-check"
  export RESTORE_PATTERNS="$probe_path"
  if restore_bucket_patterns "/tmp/hf-check" "$probe_path" >/dev/null 2>&1; then
    BUCKET_HAS_DATA="yes"
    break
  fi
done

if [ "$BUCKET_HAS_DATA" = "yes" ]; then
  log "✅ Buckets 中有持久化数据，开始恢复"

  # 先恢复 openclaw.json，再恢复 workspace / extensions / cron / skills。
  # 这样后续 bootstrap 阶段能直接基于恢复后的状态继续处理。
  export RESTORE_DESTINATION_DIR="$OPENCLAW_DIR"
  export RESTORE_PATTERNS="openclaw.json"
  restore_bucket_patterns "$OPENCLAW_DIR" "openclaw.json" >/dev/null 2>&1 && \
    log "✅ openclaw.json 已恢复" || warn "openclaw.json 恢复失败，继续使用镜像内文件"

  for include_path in "workspace/*" "extensions/*" "cron/*" "skills/*"; do
    export RESTORE_DESTINATION_DIR="$OPENCLAW_DIR"
    export RESTORE_PATTERNS="$include_path"
    restore_bucket_patterns "$OPENCLAW_DIR" "$include_path" >/dev/null 2>&1 && \
      log "✅ 已恢复 ${include_path}" || warn "恢复 ${include_path} 失败或为空"
  done

  log "=== Buckets 恢复后的目录快照 ==="
  if [ -d "$OPENCLAW_DIR/workspace" ]; then
    log "workspace entries: $(find "$OPENCLAW_DIR/workspace" -mindepth 1 -maxdepth 2 | tr '\n' ' ' | cut -c 1-600)"
  fi
  if [ -d "$OPENCLAW_DIR/cron" ]; then
    log "cron entries: $(find "$OPENCLAW_DIR/cron" -mindepth 1 -maxdepth 2 | tr '\n' ' ' | cut -c 1-600)"
  fi
  if [ -d "$OPENCLAW_DIR/extensions" ]; then
    log "extensions entries: $(find "$OPENCLAW_DIR/extensions" -mindepth 1 -maxdepth 3 | tr '\n' ' ' | cut -c 1-800)"
  fi
  if [ -d "$OPENCLAW_DIR/skills" ]; then
    log "skills entries: $(find "$OPENCLAW_DIR/skills" -mindepth 1 -maxdepth 2 | tr '\n' ' ' | cut -c 1-400)"
  fi
else
  # 如果 Buckets 里还没有数据，说明这是首次启动。
  # 这里不直接推送，而是先打标，等配置渲染完成后再推送首个快照。
  warn "Buckets 中暂无数据，将使用镜像内默认文件并标记为首次启动"
  FIRST_RUN=true
  touch "$FIRST_RUN_FLAG_FILE"
fi

rm -rf /tmp/hf-check

if [ -f "$FIRST_RUN_FLAG_FILE" ]; then
  log "=== 首次启动将于配置渲染完成后推送初始快照 ==="
fi
