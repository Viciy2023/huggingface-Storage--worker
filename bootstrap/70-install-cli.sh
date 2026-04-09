#!/bin/bash

set -euo pipefail

source /bootstrap/common.sh

# 第七阶段：安装微信 CLI。
# 这是最后一步，因为它属于增强能力，不应该影响前面核心部署链路的可观测性。
log "=== 安装微信 CLI ==="
if npx -y @tencent-weixin/openclaw-weixin-cli@latest install; then
  log "✅ 微信 CLI 安装成功"
else
  # 按当前设计，微信 CLI 安装失败不会阻断 Gateway。
  # 这样可以避免 npm registry 短时抖动把整个容器启动拖死。
  warn "微信 CLI 安装失败，继续启动 Gateway"
fi
