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

# 不再只用 openclaw.json 作为唯一探针，因为你可能先上传的是 workspace/cron/extensions。
# 这里优先探测 workspace、cron、extensions 任一目录是否存在，再决定 Buckets 是否已有持久化数据。
BUCKET_HAS_DATA="no"
for probe_path in "workspace/*" "cron/*" "extensions/*" "skills/*" "openclaw.json"; do
  if hf_cli download \
    "$BUCKET_REPO" \
    --repo-type "$BUCKET_TYPE" \
    --token "$HF_TOKEN" \
    --include "$probe_path" \
    --local-dir /tmp/hf-check >/dev/null 2>&1; then
    BUCKET_HAS_DATA="yes"
    break
  fi
done

if [ "$BUCKET_HAS_DATA" = "yes" ]; then
  log "✅ Buckets 中有持久化数据，开始恢复"

  # 先恢复 openclaw.json，再恢复 workspace / extensions / cron / skills。
  # 这样后续 bootstrap 阶段能直接基于恢复后的状态继续处理。
  hf_cli download \
    "$BUCKET_REPO" \
    --repo-type "$BUCKET_TYPE" \
    --token "$HF_TOKEN" \
    openclaw.json \
    --local-dir "$OPENCLAW_DIR" >/dev/null 2>&1 && \
    log "✅ openclaw.json 已恢复" || warn "openclaw.json 恢复失败，继续使用镜像内文件"

  for include_path in "workspace/*" "extensions/*" "cron/*" "skills/*"; do
    hf_cli download \
      "$BUCKET_REPO" \
      --repo-type "$BUCKET_TYPE" \
      --token "$HF_TOKEN" \
      --include "$include_path" \
      --local-dir "$OPENCLAW_DIR" >/dev/null 2>&1 && \
      log "✅ 已恢复 ${include_path}" || warn "恢复 ${include_path} 失败或为空"
  done
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
