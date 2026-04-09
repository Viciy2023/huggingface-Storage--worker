#!/bin/bash

set -euo pipefail

source /bootstrap/common.sh

# 第五阶段：做运行期网络相关检查。
# 这里不负责部署，只负责把“出口 IP”和“公众号 API 是否能打通”明确打印出来。

CURRENT_IP=$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null || curl -s --max-time 10 https://api.ipify.org 2>/dev/null || echo "unknown")

echo ""
echo "════════════════════════════════════════════════════════════════"
log "🌐 HF Space 出口 IP：${CURRENT_IP}"
echo "════════════════════════════════════════════════════════════════"
echo ""

if [ -n "${WECHAT_APP_ID:-}" ] && [ -n "${WECHAT_APP_SECRET:-}" ]; then
  log "=== 测试微信公众号 API 连通性 ==="
  WECHAT_TOKEN_URL="https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=${WECHAT_APP_ID}&secret=${WECHAT_APP_SECRET}"
  WECHAT_RESPONSE=$(curl -s --max-time 10 "$WECHAT_TOKEN_URL" || echo '{"errcode":-1,"errmsg":"network error"}')

  # 成功时会拿到 access_token；失败时打印错误码并给出常见问题提示。
  if echo "$WECHAT_RESPONSE" | grep -q '"access_token"'; then
    log "✅ 微信公众号 API 连通成功"
  else
    warn "微信公众号 API 连通失败: ${WECHAT_RESPONSE}"
    ERRCODE=$(echo "$WECHAT_RESPONSE" | grep -o '"errcode":[0-9-]*' | cut -d':' -f2 || true)
    case "$ERRCODE" in
      40013) warn "Hint: WECHAT_APP_ID 无效" ;;
      40001) warn "Hint: WECHAT_APP_SECRET 无效" ;;
      40164) warn "Hint: 当前出口 IP ${CURRENT_IP} 不在公众号白名单" ;;
      -1) warn "Hint: 网络异常或请求超时" ;;
    esac
  fi
else
  warn "WECHAT_APP_ID 或 WECHAT_APP_SECRET 未设置，跳过公众号 API 探活"
fi

LAST_IP=""
[ -f "$IP_RECORD" ] && LAST_IP=$(cat "$IP_RECORD")

if [ "$CURRENT_IP" != "unknown" ] && [ "$CURRENT_IP" != "$LAST_IP" ]; then
  echo "$CURRENT_IP" > "$IP_RECORD"

  if [ -n "${WECOM_WEBHOOK_KEY:-}" ]; then
    # IP 首次出现或发生变化时，用企业微信 webhook 通知维护者更新白名单。
    if [ -z "$LAST_IP" ]; then
      MSG="🦞 OpenClaw HF Space 首次启动\n\n出口IP: ${CURRENT_IP}\n\n请确认该IP已添加到可信IP白名单中。"
    else
      MSG="⚠️ OpenClaw HF Space 出口IP已变更\n\n旧IP: ${LAST_IP}\n新IP: ${CURRENT_IP}\n\n请立即更新可信IP白名单。"
    fi
    curl -s -X POST \
      "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${WECOM_WEBHOOK_KEY}" \
      -H "Content-Type: application/json" \
      -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"${MSG}\"}}" \
      >/dev/null 2>&1 || warn "企业微信 webhook 通知发送失败"
  fi
fi
