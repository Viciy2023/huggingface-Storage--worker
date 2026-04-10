#!/bin/bash

set -euo pipefail

source /bootstrap/common.sh

# 第二阶段：优先从 HF Buckets 恢复上一次运行留下的状态。
# 这里不再做“猜测式探测”，而是直接列举 Buckets 文件并逐个恢复，
# 然后根据真实恢复结果判断是否属于首次启动。
log "=== 从 HF Buckets 加载持久化数据 ==="

if [ -z "${HF_TOKEN:-}" ]; then
  warn "HF_TOKEN 未设置，跳过 Buckets 加载，将使用镜像内默认文件"
  exit 0
fi

RESTORE_OUTPUT=$(python3 - <<'PY'
import os
import sys
from huggingface_hub import HfFileSystem

token = os.environ.get("HF_TOKEN", "")
repo = os.environ.get("BUCKET_REPO", "")
local_root = os.environ.get("OPENCLAW_STATE_DIR", "/root/.openclaw")


def to_relative_path(remote_file: str, repo_name: str) -> str:
    prefixes = (
        f"hf://buckets/{repo_name}/",
        f"buckets/{repo_name}/",
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
bucket_root = f"hf://buckets/{repo}"
os.makedirs(local_root, exist_ok=True)

try:
    if not fs.exists(bucket_root):
        print("0")
        sys.exit(0)

    restored = []
    for remote_file in fs.glob(f"{bucket_root}/**/*"):
        if not fs.isfile(remote_file):
            continue
        rel_path = to_relative_path(remote_file, repo)
        if not rel_path or rel_path.startswith("buckets/"):
            continue
        local_file = os.path.join(local_root, rel_path)
        os.makedirs(os.path.dirname(local_file), exist_ok=True)
        fs.get(remote_file, local_file)
        restored.append(rel_path)

    print(str(len(restored)))
    for rel_path in restored[:50]:
        print(rel_path)
except Exception:
    print("0")
PY
)

RESTORED_COUNT=$(printf '%s' "$RESTORE_OUTPUT" | tr -d '\r' | head -n 1)

if [[ "$RESTORED_COUNT" =~ ^[0-9]+$ ]] && [ "$RESTORED_COUNT" -gt 0 ]; then
  log "✅ Buckets 中有持久化数据，开始恢复"

  [ -f "$OPENCLAW_DIR/openclaw.json" ] && log "✅ openclaw.json 已恢复" || warn "openclaw.json 恢复失败，继续使用镜像内文件"

  if [ -f "$OPENCLAW_DIR/workspace/AGENTS.md" ] || [ -f "$OPENCLAW_DIR/workspace/SOUL.md" ]; then
    log "✅ workspace 私有文档已恢复"
  else
    warn "workspace 私有文档未恢复到常见路径"
  fi

  if [ -f "$OPENCLAW_DIR/cron/jobs.json" ]; then
    log "✅ cron/jobs.json 已恢复"
  else
    warn "cron/jobs.json 未恢复到常见路径"
  fi

  if [ -d "$OPENCLAW_DIR/extensions/clawedit" ]; then
    log "✅ extensions/clawedit 已恢复"
  else
    warn "extensions/clawedit 未恢复到常见路径"
  fi

  [ -d "$OPENCLAW_DIR/skills" ] && log "✅ skills 目录已恢复/存在" || warn "skills 目录恢复失败或为空"

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
  warn "Buckets 中暂无数据，将使用镜像内默认文件并标记为首次启动"
  FIRST_RUN=true
  touch "$FIRST_RUN_FLAG_FILE"
fi

if [ -f "$FIRST_RUN_FLAG_FILE" ]; then
  log "=== 首次启动将于配置渲染完成后推送初始快照 ==="
fi
