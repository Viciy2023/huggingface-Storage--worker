#!/bin/bash

set -euo pipefail

source /bootstrap/common.sh

# 第六阶段：统一做运行时完整性验证。
# 这是启动 Gateway 前的最后一道硬门槛，缺少关键资产就直接阻断启动。

log "=== 验证环境变量加载 ==="
[ -n "${GATEWAY_TOKEN:-}" ] || { warn "GATEWAY_TOKEN 未设置"; mark_verify_failure; }
[ -n "${PRIMARY_PROVIDER_API_KEY:-}" ] || warn "PRIMARY_PROVIDER_API_KEY 未设置"

log "=== 验证 openclaw-china channels 插件 ==="
# 这里沿用插件列表输出做校验，确保构建期安装的插件在运行期仍然可见。
if run_openclaw plugins list 2>&1 | grep -qi "channels"; then
  log "✅ @openclaw-china/channels 已安装并可见"
else
  warn "@openclaw-china/channels 未出现在 plugins list 中"
  mark_verify_failure
fi

log "=== 验证 wecom-app-ops skill ==="
check_required_dir "$OPENCLAW_DIR/skills/wecom-app-ops" "wecom-app-ops skill"

log "=== 验证 ClawHub skills ==="
# 这些 skills 允许存在于 workspace/skills 或全局 skills，
# 所以两个路径都要兼容检查。
for skill_name in "${CLAWHUB_SKILLS[@]}"; do
  if [ -d "$OPENCLAW_DIR/workspace/skills/$skill_name" ] || [ -d "$OPENCLAW_DIR/skills/$skill_name" ]; then
    log "✅ 已找到 skill: ${skill_name}"
  else
    log "❌ 缺少 skill: ${skill_name}"
    mark_verify_failure
  fi
done

log "=== 验证 wechat-allauto-gzh 项目 ==="
# 公众号工作流依赖 skill.md、src/skills 和 credentials.json，缺一都不能算部署完成。
check_required_dir "$WECHAT_ALLAUTO_GZH_DIR" "wechat-allauto-gzh 根目录"
check_required_file "$WECHAT_ALLAUTO_GZH_DIR/skill.md" "wechat-allauto-gzh skill.md"
check_required_dir "$WECHAT_ALLAUTO_GZH_DIR/src/skills" "wechat-allauto-gzh Python skills"
check_required_file "$WECHAT_CREDS_FILE" "微信公众号凭证"

log "=== 验证私有 Buckets 内容恢复情况 ==="
# Buckets 恢复阶段已经输出了目录快照和关键文件存在性。
# 这里不再重复猜测路径，只保留简短提醒，避免日志重复且互相矛盾。
if [ -d "$OPENCLAW_DIR/extensions/clawedit" ] || [ -f "$OPENCLAW_DIR/cron/jobs.json" ] || [ -f "$OPENCLAW_DIR/workspace/AGENTS.md" ] || [ -f "$OPENCLAW_DIR/workspace/SOUL.md" ]; then
  log "✅ 检测到至少一项私有 Buckets 内容已恢复到常见路径"
else
  warn "未在常见路径发现私有 Buckets 内容；请以上一阶段的目录快照为准检查实际落盘位置"
fi

log "=== 验证 agent-browser ==="
# 浏览器自动化是这次要求中的必装项，因此缺失时也视为关键失败。
if command -v agent-browser >/dev/null 2>&1; then
  agent-browser --version || warn "agent-browser 版本检查失败"
else
  warn "agent-browser 未安装"
  mark_verify_failure
fi

if [ "$VERIFY_FAILURES" -gt 0 ]; then
  fail "运行时完整性验证失败，共 ${VERIFY_FAILURES} 项异常"
fi

log "✅ 运行时完整性验证通过"
