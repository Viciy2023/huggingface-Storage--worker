#!/bin/bash

set -euo pipefail

source /bootstrap/common.sh

# 第四阶段：部署运行期依赖的外部项目。
# 当前只保留 wechat-allauto-gzh 的公开仓库部署。
# 私有内容建议在本地子项目中按实际运行路径维护：
# - workspace/
# - cron/
# - extensions/clawedit/
# 然后由你手动或脚本提前同步到私有 HF Buckets。

log "=== 部署 wechat-allauto-gzh 项目 ==="
# 对外部 Git 仓库 clone/pull 使用 retry，降低网络抖动导致启动失败的概率。
retry 3 5 clone_or_update_repo "$WECHAT_ALLAUTO_GZH_REPO_URL" "$WECHAT_ALLAUTO_GZH_BRANCH" "$WECHAT_ALLAUTO_GZH_DIR"

if [ -d "$WECHAT_ALLAUTO_GZH_DIR" ]; then
  log "=== 安装 wechat-allauto-gzh Python 依赖 ==="
  pip install --no-cache-dir requests pyyaml --break-system-packages
  write_wechat_credentials || true
else
  fail "wechat-allauto-gzh 部署失败"
fi

log "ℹ️ extensions/clawedit、cron 与 workspace 预设文件不再从 GitHub 拉取，请确保它们已提前同步到私有 HF Buckets"
