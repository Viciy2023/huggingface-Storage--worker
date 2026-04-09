#!/bin/bash
set -euo pipefail

# 统一加载共享环境变量、日志函数和通用辅助函数。
source /bootstrap/common.sh

# bootstrap 阶段严格按顺序执行。
# 前面的阶段负责准备基础状态，后面的阶段依赖前面的输出结果。
BOOTSTRAP_STEPS=(
  /bootstrap/10-init-state.sh
  /bootstrap/20-load-buckets.sh
  /bootstrap/25-seed-runtime-files.sh
  /bootstrap/30-render-config.sh
  /bootstrap/40-deploy-projects.sh
  /bootstrap/50-network-checks.sh
  /bootstrap/60-verify-runtime.sh
  /bootstrap/70-install-cli.sh
)

# 逐个执行 bootstrap 步骤。
# 任一步返回非 0 都会因为 set -e 直接终止启动，避免半残状态继续跑 Gateway。
for step in "${BOOTSTRAP_STEPS[@]}"; do
  log "=== 执行 bootstrap 步骤: ${step} ==="
  "$step"
done

# 只有 HF_TOKEN 存在时才启动 Buckets 同步守护。
# 没有 HF_TOKEN 的场景下容器仍可运行，只是不会做持久化同步。
if [ -n "${HF_TOKEN:-}" ]; then
  log "=== 启动后台同步守护 sync-watch ==="
  /sync-watch.sh --daemon &
  SYNC_PID=$!
  log "✅ sync-watch 已启动 (PID: ${SYNC_PID})"
else
  warn "HF_TOKEN 未设置，跳过后台同步守护"
fi

# 容器收到停止信号时，优先把当前状态再同步一次到 Buckets，
# 然后再结束 Gateway 和 sync-watch，尽量减少状态丢失。
cleanup() {
  log "=== 收到停止信号，开始执行清理 ==="
  if [ -n "${HF_TOKEN:-}" ]; then
    /sync-watch.sh --push-once 2>/dev/null || true
    log "✅ 最终快照推送完成"
  fi
  if [ -n "${GATEWAY_PID:-}" ]; then
    kill "$GATEWAY_PID" 2>/dev/null || true
  fi
  if [ -n "${SYNC_PID:-}" ]; then
    kill "$SYNC_PID" 2>/dev/null || true
  fi
}

trap cleanup SIGTERM SIGINT

# 所有 bootstrap 阶段成功后，最后才启动 OpenClaw Gateway。
log "=== 启动 OpenClaw Gateway ==="
node /app/openclaw.mjs gateway --port 7860 --bind lan --allow-unconfigured &
GATEWAY_PID=$!
log "✅ Gateway 已启动 (PID: ${GATEWAY_PID})"

wait "$GATEWAY_PID"
