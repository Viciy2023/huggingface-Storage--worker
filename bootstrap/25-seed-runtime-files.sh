#!/bin/bash

set -euo pipefail

source /bootstrap/common.sh

# 第 2.5 阶段：只有在 Buckets 没恢复出配置文件时才执行。
# 作用是仅从镜像内模板预置最小可运行的 openclaw.json。
# 私有工作区文件、cron、extensions/clawedit 等内容不再从 GitHub 获取，
# 建议在本地仓库中按 OpenClaw 实际运行路径维护，然后同步到私有 HF Buckets：
# - workspace/
# - cron/
# - extensions/clawedit/
if [ -f "$CONFIG" ]; then
  log "ℹ️ 已存在配置文件，跳过 GitHub 默认文件预置"
  exit 0
fi

log "=== 预置运行时默认文件 ==="

if [ -f "$LOCAL_OPENCLAW_TEMPLATE" ]; then
  mkdir -p "$OPENCLAW_DIR"
  cp "$LOCAL_OPENCLAW_TEMPLATE" "$CONFIG"
  chmod 600 "$CONFIG"
  log "✅ 已从镜像内模板预置 openclaw.json"
else
  fail "镜像内缺少 openclaw.json 模板: ${LOCAL_OPENCLAW_TEMPLATE}"
fi

log "ℹ️ 私有 workspace / cron / extensions/clawedit 预设应提前存入 HF Buckets，本阶段不再从 GitHub 补齐"
