#!/bin/bash

set -euo pipefail

source /bootstrap/common.sh

# 这是 bootstrap 的第一个阶段。
# 职责只有一个：把 OpenClaw 运行所需的目录结构准备好。
log "=== 初始化目录结构 ==="
ensure_dir "$OPENCLAW_DIR"
ensure_dir "$OPENCLAW_DIR/workspace"
ensure_dir "$OPENCLAW_DIR/extensions"
ensure_dir "$OPENCLAW_DIR/cron"
ensure_dir "$OPENCLAW_DIR/skills"
ensure_dir "$OPENCLAW_DIR/workspace/skills"

# extensions 目录可能会被 Buckets 恢复或 GitHub deploy source 写入，
# 这里统一把所有权修回 root，避免后续插件部署和同步时报权限问题。
if [ -d "$OPENCLAW_DIR/extensions" ]; then
  chown -R root:root "$OPENCLAW_DIR/extensions" 2>/dev/null || true
fi

log "✅ 状态目录初始化完成"
