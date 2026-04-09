#!/bin/bash

set -euo pipefail

# 复用 bootstrap 的公共变量和日志函数，保证和主启动链路使用同一套配置。
source /bootstrap/common.sh

# 这些目录/文件代表需要持久化到 HF Buckets 的核心运行状态。
# 只要它们发生变更，就会被同步到 Buckets。
WATCH_DIRS=(
  "$OPENCLAW_DIR/workspace"
  "$OPENCLAW_DIR/extensions"
  "$OPENCLAW_DIR/cron"
  "$OPENCLAW_DIR/skills"
)
WATCH_FILES=(
  "$OPENCLAW_DIR/openclaw.json"
)

DEBOUNCE_SECS=8

# 过滤掉不应该进入 Buckets 的运行期垃圾文件和仓库元数据。
# 否则 clone 下来的 .git、依赖目录、Python 缓存会污染持久化层。
should_ignore_path() {
  local changed_path="$1"
  case "$changed_path" in
    *.swp|*.tmp|*~|*.lock|*/.git/*|*/node_modules/*|*/__pycache__/*|*/.venv/*)
      return 0
      ;;
  esac
  return 1
}

# 推送单个文件到 Buckets。
# Buckets 中使用相对 OPENCLAW_DIR 的路径，保持目录结构稳定。
push_file() {
  local local_path="$1"
  local rel_path="${local_path#$OPENCLAW_DIR/}"
  local error_log

  [ -f "$local_path" ] || return 0

  error_log=$(mktemp)

  hf_cli upload \
    "$BUCKET_REPO" \
    "$local_path" \
    "$rel_path" \
    --repo-type "$BUCKET_TYPE" \
    --token "$HF_TOKEN" >/dev/null 2>"$error_log" && \
    log "✅ 已同步：$rel_path" || { \
      warn "同步失败：$rel_path"; \
      sed 's/^/[sync-watch stderr] /' "$error_log" >&2 || true; \
    }

  rm -f "$error_log"
}

# 推送目录到 Buckets。
# 如果目录里含有 .git / node_modules / __pycache__ 等内容，
# 会先复制到临时目录并清理这些无关文件后再上传。
push_dir() {
  local dir="$1"
  local rel_dir="${dir#$OPENCLAW_DIR/}"
  local error_log

  [ -d "$dir" ] || return 0

  local upload_dir="$dir"
  local cleanup_temp=""
  error_log=$(mktemp)
  if [ -d "$dir/.git" ] || [ -d "$dir/node_modules" ] || [ -d "$dir/__pycache__" ]; then
    cleanup_temp=$(mktemp -d)
    upload_dir="$cleanup_temp/$rel_dir"
    mkdir -p "$(dirname "$upload_dir")"
    cp -a "$dir" "$upload_dir"
    rm -rf "$upload_dir/.git" "$upload_dir/node_modules" "$upload_dir/__pycache__" "$upload_dir/.venv"
  fi

  hf_cli upload \
    "$BUCKET_REPO" \
    "$upload_dir" \
    "$rel_dir" \
    --repo-type "$BUCKET_TYPE" \
    --token "$HF_TOKEN" >/dev/null 2>"$error_log" && \
    log "✅ 已同步目录：$rel_dir" || { \
      warn "目录同步失败：$rel_dir"; \
      sed 's/^/[sync-watch stderr] /' "$error_log" >&2 || true; \
    }

  if [ -n "$cleanup_temp" ]; then
    rm -rf "$cleanup_temp"
  fi
  rm -f "$error_log"
}

# 执行一次全量推送。
# 用于首次启动、容器退出和定时/防抖触发后的完整状态落盘。
push_all() {
  log "开始全量推送到 Buckets..."
  push_file "$OPENCLAW_DIR/openclaw.json"
  local dir
  for dir in "${WATCH_DIRS[@]}"; do
    push_dir "$dir"
  done
  log "全量推送完成"
}

MODE="${1:---daemon}"

case "$MODE" in
  --push-once)
    # 一次性全量推送，通常由首次启动和退出清理阶段调用。
    [ -n "${HF_TOKEN:-}" ] || fail "HF_TOKEN 未设置，无法推送"
    push_all
    ;;
  --daemon)
    # 持续后台监控模式，容器正常运行期间常驻。
    [ -n "${HF_TOKEN:-}" ] || fail "HF_TOKEN 未设置，无法启动同步守护"

    if ! command -v inotifywait >/dev/null 2>&1; then
      # 某些基础镜像里可能没有 inotifywait，这里降级为定时轮询，确保仍可同步。
      warn "inotifywait 不可用，降级为 60 秒轮询同步"
      while true; do
        sleep 60
        push_all
      done
    fi

    log "启动 inotifywait 监控模式（防抖 ${DEBOUNCE_SECS}s）"
    WATCH_PATHS=()
    for dir in "${WATCH_DIRS[@]}"; do
      [ -d "$dir" ] && WATCH_PATHS+=("$dir")
    done
    for file in "${WATCH_FILES[@]}"; do
      [ -f "$file" ] && WATCH_PATHS+=("$file")
    done

    [ ${#WATCH_PATHS[@]} -gt 0 ] || fail "无可监控路径"

    # 用一个临时文件记录最后一次变化时间，用于实现跨子进程的防抖判断。
    LAST_CHANGE_FILE=$(mktemp)
    date +%s > "$LAST_CHANGE_FILE"

    inotifywait -m -r \
      -e modify,create,delete,move \
      --format "%w%f" \
      "${WATCH_PATHS[@]}" 2>/dev/null | \
    while read -r changed_path; do
      if should_ignore_path "$changed_path"; then
        continue
      fi

      date +%s > "$LAST_CHANGE_FILE"
      log "检测到变更：$changed_path"

      (
        # 防抖：只有在指定秒数内没有新变更时才真正推送，避免频繁上传。
        sleep "$DEBOUNCE_SECS"
        current_ts=$(date +%s)
        last_change_ts=$(cat "$LAST_CHANGE_FILE")
        if [ $((current_ts - last_change_ts)) -ge "$DEBOUNCE_SECS" ]; then
          log "防抖触发，开始推送..."
          push_all
        fi
      ) &
    done
    ;;
  *)
    echo "用法：$0 [--daemon | --push-once]"
    exit 1
    ;;
esac
