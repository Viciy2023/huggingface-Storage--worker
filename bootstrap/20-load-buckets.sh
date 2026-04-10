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

RESTORED_COUNT=$(python3 - <<'PY'
import os
import sys
from huggingface_hub import HfFileSystem

token = os.environ.get("HF_TOKEN", "")
repo = os.environ.get("BUCKET_REPO", "")
local_root = os.environ.get("OPENCLAW_STATE_DIR", "/root/.openclaw")
repo_type = os.environ.get("BUCKET_TYPE", "dataset")


def to_relative_path(remote_file: str, repo_name: str) -> str:
    repo_prefix = {
        "dataset": "datasets",
        "space": "spaces",
        "model": "models",
    }.get(repo_type, "datasets")
    prefixes = (
        f"hf://{repo_prefix}/{repo_name}/",
        f"{repo_prefix}/{repo_name}/",
        f"/{repo_name}/",
        f"{repo_name}/",
    )
    rel_path = remote_file
    while True:
        for prefix in prefixes:
            if rel_path.startswith(prefix):
                rel_path = rel_path[len(prefix):]
                break
        else:
            break
    return rel_path.lstrip("/")


if not token or not repo:
    print("0")
    sys.exit(0)

fs = HfFileSystem(token=token)
prefix = {"dataset": "datasets", "space": "spaces", "model": "models"}.get(repo_type, "datasets")
bucket_root = f"hf://{prefix}/{repo}"
os.makedirs(local_root, exist_ok=True)

try:
    if not fs.exists(bucket_root):
        print("0")
        sys.exit(0)

    files = fs.glob(f"{bucket_root}/**/*")
    restored = 0
    for remote_file in files:
        if fs.isfile(remote_file):
            rel_path = to_relative_path(remote_file, repo)
            if not rel_path or rel_path.startswith("buckets/"):
                continue
            local_file = os.path.join(local_root, rel_path)
            os.makedirs(os.path.dirname(local_file), exist_ok=True)
            fs.get(remote_file, local_file)
            restored += 1
            if restored <= 20:
                print(f"[bucket_restore] {remote_file} -> {local_file}", file=sys.stderr)
    print(str(restored))
except Exception:
    print("0")
PY
)

if [ "$RESTORED_COUNT" -gt 0 ] 2>/dev/null; then
  log "✅ Buckets 中有持久化数据，开始恢复"
  if [ -f "$OPENCLAW_DIR/openclaw.json" ]; then
    log "✅ openclaw.json 已恢复"
  else
    warn "openclaw.json 恢复失败，继续使用镜像内文件"
  fi
  [ -d "$OPENCLAW_DIR/workspace" ] && log "✅ 已恢复 workspace/*" || warn "恢复 workspace/* 失败或为空"
  [ -d "$OPENCLAW_DIR/extensions" ] && log "✅ 已恢复 extensions/*" || warn "恢复 extensions/* 失败或为空"
  [ -d "$OPENCLAW_DIR/cron" ] && log "✅ 已恢复 cron/*" || warn "恢复 cron/* 失败或为空"
  [ -d "$OPENCLAW_DIR/skills" ] && log "✅ 已恢复 skills/*" || warn "恢复 skills/* 失败或为空"

  log "=== Buckets 恢复后的目录快照 ==="
  if [ -d "$OPENCLAW_DIR/workspace" ]; then
    log "workspace entries: $(find "$OPENCLAW_DIR/workspace" -mindepth 1 -maxdepth 3 | tr '\n' ' ' | cut -c 1-1200)"
  fi
  if [ -d "$OPENCLAW_DIR/cron" ]; then
    log "cron entries: $(find "$OPENCLAW_DIR/cron" -mindepth 1 -maxdepth 3 | tr '\n' ' ' | cut -c 1-1200)"
  fi
  if [ -d "$OPENCLAW_DIR/extensions" ]; then
    log "extensions entries: $(find "$OPENCLAW_DIR/extensions" -mindepth 1 -maxdepth 4 | tr '\n' ' ' | cut -c 1-1600)"
  fi
  if [ -d "$OPENCLAW_DIR/skills" ]; then
    log "skills entries: $(find "$OPENCLAW_DIR/skills" -mindepth 1 -maxdepth 3 | tr '\n' ' ' | cut -c 1-800)"
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
