#!/bin/bash

set -euo pipefail

source /bootstrap/common.sh

# 先把可能为空的环境变量取成安全值，避免 set -u 下直接报错。
gateway_token_value="${GATEWAY_TOKEN:-}"
wecom_token_value="${WECOM_TOKEN:-}"
wechat_app_id_value="${WECHAT_APP_ID:-}"

# 第三阶段：对 openclaw.json 做占位符渲染。
# 所有运行时密钥都由 HF Secrets 注入，这一步负责把模板值替换成实际值。
log "=== 调试：检查环境变量 ==="
log "GATEWAY_TOKEN length: ${#gateway_token_value}"
log "WECOM_TOKEN length: ${#wecom_token_value}"
log "WECHAT_APP_ID length: ${#wechat_app_id_value}"

if [ ! -f "$CONFIG" ]; then
  fail "配置文件不存在: ${CONFIG}"
fi

log "=== 替换 openclaw.json 占位符 ==="

# PUBLIC_BASE_URL 既可能是纯域名，也可能是带协议的完整地址，
# 这里做兼容处理，尽量保留正确的 Control UI Origin。
CONTROL_UI_ORIGIN="${PUBLIC_BASE_URL:-}"
CONTROL_UI_ORIGIN="${CONTROL_UI_ORIGIN%/}"
if [ -n "$CONTROL_UI_ORIGIN" ]; then
  CONTROL_UI_ORIGIN="${CONTROL_UI_ORIGIN%%/*}"
  if [[ "$PUBLIC_BASE_URL" =~ ^https?:// ]]; then
    CONTROL_UI_ORIGIN="${PUBLIC_BASE_URL%/}"
  fi
fi

# 基础访问配置：
# - __PUBLIC_BASE_URL__：Gateway/控制台对外访问地址
# - __WECOM_APP_API_BASE_URL__：企业微信应用回调/API 对外基址
# - __GATEWAY_TOKEN__：OpenClaw Gateway 访问令牌
sed -i "s|__PUBLIC_BASE_URL__|${CONTROL_UI_ORIGIN}|g" "$CONFIG"
sed -i "s|__WECOM_APP_API_BASE_URL__|${WECOM_APP_API_BASE_URL:-}|g" "$CONFIG"
sed -i "s|__GATEWAY_TOKEN__|${GATEWAY_TOKEN:-}|g" "$CONFIG"

# 主对话模型配置：
# - __PRIMARY_PROVIDER_NAME__：主模型提供商显示名/标识
# - __PRIMARY_PROVIDER_BASE_URL__：主模型 API 基址
# - __PRIMARY_PROVIDER_API_KEY__：主模型 API 密钥
# - __PRIMARY_PROVIDER_API__：主模型 API 类型或接入协议标识
# - __PRIMARY_MODEL_ID__：主模型实际调用的模型 ID
# - __PRIMARY_MODEL_NAME__：主模型显示名称
sed -i "s|__PRIMARY_PROVIDER_NAME__|${PRIMARY_PROVIDER_NAME:-}|g" "$CONFIG"
sed -i "s|__PRIMARY_PROVIDER_BASE_URL__|${PRIMARY_PROVIDER_BASE_URL:-}|g" "$CONFIG"
sed -i "s|__PRIMARY_PROVIDER_API_KEY__|${PRIMARY_PROVIDER_API_KEY:-}|g" "$CONFIG"
sed -i "s|__PRIMARY_PROVIDER_API__|${PRIMARY_PROVIDER_API:-}|g" "$CONFIG"
sed -i "s|__PRIMARY_MODEL_ID__|${PRIMARY_MODEL_ID:-}|g" "$CONFIG"
sed -i "s|__PRIMARY_MODEL_NAME__|${PRIMARY_MODEL_NAME:-}|g" "$CONFIG"

# 文生图配置（给 ClawEdit 等图像生成流程使用）：
# - __TEXT2IMG_KEY__：文生图服务 API Key
# - __TEXT2IMG_BASE_URL__：文生图服务地址
# - __TEXT2IMG_MODEL__：文生图模型名
# - __TEXT2IMG_TYPE__：文生图接口类型，默认 openai-compatible
# - __TEXT2IMG_TIMEOUT__：文生图超时毫秒数
sed -i "s|__TEXT2IMG_KEY__|${TEXT2IMG_KEY:-}|g" "$CONFIG"
sed -i "s|__TEXT2IMG_BASE_URL__|${TEXT2IMG_BASE_URL:-}|g" "$CONFIG"
sed -i "s|__TEXT2IMG_MODEL__|${TEXT2IMG_MODEL:-grok-imagine-1.0-fast}|g" "$CONFIG"
sed -i "s|__TEXT2IMG_TYPE__|${TEXT2IMG_TYPE:-openai-compatible}|g" "$CONFIG"
sed -i "s|__TEXT2IMG_TIMEOUT__|${TEXT2IMG_TIMEOUT:-120000}|g" "$CONFIG"

# 图生图配置：
# - __IMG2IMG_KEY__：图像编辑/重绘服务 API Key
# - __IMG2IMG_BASE_URL__：图像编辑服务地址
# - __IMG2IMG_MODEL__：图生图模型名
# - __IMG2IMG_TYPE__：图生图接口类型
# - __IMG2IMG_TIMEOUT__：图生图超时毫秒数
sed -i "s|__IMG2IMG_KEY__|${IMG2IMG_KEY:-}|g" "$CONFIG"
sed -i "s|__IMG2IMG_BASE_URL__|${IMG2IMG_BASE_URL:-}|g" "$CONFIG"
sed -i "s|__IMG2IMG_MODEL__|${IMG2IMG_MODEL:-grok-imagine-1.0-edit}|g" "$CONFIG"
sed -i "s|__IMG2IMG_TYPE__|${IMG2IMG_TYPE:-openai-compatible}|g" "$CONFIG"
sed -i "s|__IMG2IMG_TIMEOUT__|${IMG2IMG_TIMEOUT:-120000}|g" "$CONFIG"

# 图生视频配置：
# - __IMG2VIDEO_KEY__：图转视频服务 API Key
# - __IMG2VIDEO_BASE_URL__：图转视频服务地址
# - __IMG2VIDEO_MODEL__：图转视频模型名
# - __IMG2VIDEO_TYPE__：图转视频接口类型
# - __IMG2VIDEO_TIMEOUT__：图转视频超时毫秒数
sed -i "s|__IMG2VIDEO_KEY__|${IMG2VIDEO_KEY:-}|g" "$CONFIG"
sed -i "s|__IMG2VIDEO_BASE_URL__|${IMG2VIDEO_BASE_URL:-}|g" "$CONFIG"
sed -i "s|__IMG2VIDEO_MODEL__|${IMG2VIDEO_MODEL:-grok-imagine-1.0-video}|g" "$CONFIG"
sed -i "s|__IMG2VIDEO_TYPE__|${IMG2VIDEO_TYPE:-openai-compatible}|g" "$CONFIG"
sed -i "s|__IMG2VIDEO_TIMEOUT__|${IMG2VIDEO_TIMEOUT:-300000}|g" "$CONFIG"

# 备用模型一：Qwen 系列
# 这组通常作为主模型或插件模型的候补提供商配置。
# - __QWEN2API_KEY__：Qwen 服务 Key
# - __QWEN2API_BASE_URL__：Qwen 服务地址
# - __QWEN2API_MODEL__：Qwen 模型名
# - __QWEN2API_TYPE__：Qwen 接口类型
# - __QWEN2API_TIMEOUT__：Qwen 请求超时
sed -i "s|__QWEN2API_KEY__|${QWEN2API_KEY:-}|g" "$CONFIG"
sed -i "s|__QWEN2API_BASE_URL__|${QWEN2API_BASE_URL:-}|g" "$CONFIG"
sed -i "s|__QWEN2API_MODEL__|${QWEN2API_MODEL:-qwen-max}|g" "$CONFIG"
sed -i "s|__QWEN2API_TYPE__|${QWEN2API_TYPE:-openai-compatible}|g" "$CONFIG"
sed -i "s|__QWEN2API_TIMEOUT__|${QWEN2API_TIMEOUT:-120000}|g" "$CONFIG"

# 备用模型二：DeepSeek 系列
# - __DS2API_KEY__：DeepSeek 服务 Key
# - __DS2API_BASE_URL__：DeepSeek 服务地址
# - __DS2API_MODEL__：DeepSeek 模型名
# - __DS2API_TYPE__：DeepSeek 接口类型
# - __DS2API_TIMEOUT__：DeepSeek 请求超时
sed -i "s|__DS2API_KEY__|${DS2API_KEY:-}|g" "$CONFIG"
sed -i "s|__DS2API_BASE_URL__|${DS2API_BASE_URL:-}|g" "$CONFIG"
sed -i "s|__DS2API_MODEL__|${DS2API_MODEL:-deepseek-chat}|g" "$CONFIG"
sed -i "s|__DS2API_TYPE__|${DS2API_TYPE:-openai-compatible}|g" "$CONFIG"
sed -i "s|__DS2API_TIMEOUT__|${DS2API_TIMEOUT:-120000}|g" "$CONFIG"

# 企业微信机器人渠道配置：
# - __WECOM_WS_BOT_ID__：企业微信机器人 ID
# - __WECOM_WS_SECRET__：企业微信机器人密钥
# - __WECOM_TOKEN__：企业微信消息校验 Token
# - __WECOM_AES_KEY__：企业微信消息加解密 AES Key
# - __WECOM_CORP_ID__：企业微信企业 ID
sed -i "s|__WECOM_WS_BOT_ID__|${WECOM_WS_BOT_ID:-}|g" "$CONFIG"
sed -i "s|__WECOM_WS_SECRET__|${WECOM_WS_SECRET:-}|g" "$CONFIG"
sed -i "s|__WECOM_TOKEN__|${WECOM_TOKEN:-}|g" "$CONFIG"
sed -i "s|__WECOM_AES_KEY__|${WECOM_AES_KEY:-}|g" "$CONFIG"
sed -i "s|__WECOM_CORP_ID__|${WECOM_CORP_ID:-}|g" "$CONFIG"

# 企业微信应用渠道配置：
# - __WECOM_APP_TOKEN__：企业微信应用回调 Token
# - __WECOM_APP_AES_KEY__：企业微信应用回调 AES Key
# - __WECOM_APP_SECRET__：企业微信应用 Secret
# - __WECOM_APP_ASR_APP_ID__：企业微信应用语音识别 App ID
# - __WECOM_APP_ASR_SECRET_ID__：企业微信应用语音识别 Secret ID
# - __WECOM_APP_ASR_SECRET_KEY__：企业微信应用语音识别 Secret Key
sed -i "s|__WECOM_APP_TOKEN__|${WECOM_APP_TOKEN:-}|g" "$CONFIG"
sed -i "s|__WECOM_APP_AES_KEY__|${WECOM_APP_AES_KEY:-}|g" "$CONFIG"
sed -i "s|__WECOM_APP_SECRET__|${WECOM_APP_SECRET:-}|g" "$CONFIG"
sed -i "s|__WECOM_APP_ASR_APP_ID__|${WECOM_APP_ASR_APP_ID:-}|g" "$CONFIG"
sed -i "s|__WECOM_APP_ASR_SECRET_ID__|${WECOM_APP_ASR_SECRET_ID:-}|g" "$CONFIG"
sed -i "s|__WECOM_APP_ASR_SECRET_KEY__|${WECOM_APP_ASR_SECRET_KEY:-}|g" "$CONFIG"

# QQ 机器人渠道配置：
# - __QQBOT_APP_ID__：QQ 机器人应用 ID
# - __QQBOT_CLIENT_SECRET__：QQ 机器人客户端密钥
# - __QQBOT_ASR_APP_ID__：QQ 机器人语音识别 App ID
# - __QQBOT_ASR_SECRET_ID__：QQ 机器人语音识别 Secret ID
# - __QQBOT_ASR_SECRET_KEY__：QQ 机器人语音识别 Secret Key
sed -i "s|__QQBOT_APP_ID__|${QQBOT_APP_ID:-}|g" "$CONFIG"
sed -i "s|__QQBOT_CLIENT_SECRET__|${QQBOT_CLIENT_SECRET:-}|g" "$CONFIG"
sed -i "s|__QQBOT_ASR_APP_ID__|${QQBOT_ASR_APP_ID:-}|g" "$CONFIG"
sed -i "s|__QQBOT_ASR_SECRET_ID__|${QQBOT_ASR_SECRET_ID:-}|g" "$CONFIG"
sed -i "s|__QQBOT_ASR_SECRET_KEY__|${QQBOT_ASR_SECRET_KEY:-}|g" "$CONFIG"

# 飞书渠道配置：
# - __FEISHU_APP_ID__：飞书应用 App ID
# - __FEISHU_APP_SECRET__：飞书应用 Secret
# - __FEISHU_VERIFICATION_TOKEN__：飞书事件订阅校验 Token
# - __FEISHU_ENCRYPT_KEY__：飞书事件加密 Key
sed -i "s|__FEISHU_APP_ID__|${FEISHU_APP_ID:-}|g" "$CONFIG"
sed -i "s|__FEISHU_APP_SECRET__|${FEISHU_APP_SECRET:-}|g" "$CONFIG"
sed -i "s|__FEISHU_VERIFICATION_TOKEN__|${FEISHU_VERIFICATION_TOKEN:-}|g" "$CONFIG"
sed -i "s|__FEISHU_ENCRYPT_KEY__|${FEISHU_ENCRYPT_KEY:-}|g" "$CONFIG"

chmod 600 "$CONFIG"

# 渲染后检查是否还有未替换占位符，便于尽早发现 Secret 漏配。
REMAINING=$(grep -o "__[A-Z0-9_]*__" "$CONFIG" 2>/dev/null | sort -u | tr '\n' ' ' || true)
if [ -n "$REMAINING" ]; then
  warn "仍有未替换占位符: ${REMAINING}"
else
  log "✅ 所有占位符替换完成"
fi

if [ -f "$FIRST_RUN_FLAG_FILE" ] && [ -n "${HF_TOKEN:-}" ]; then
  # 首次启动时，必须在配置已经渲染完成之后，再把当前状态推到 Buckets。
  # 否则 Buckets 里会留下未替换占位符的半成品配置。
  log "=== 首次启动：推送初始快照到 Buckets ==="
  /sync-watch.sh --push-once
  rm -f "$FIRST_RUN_FLAG_FILE"
  log "✅ 初始快照推送完成"
fi
