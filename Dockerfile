# ============================================================
# Dockerfile - OpenClaw HF Buckets 持久化部署版（Bootstrap 架构）
# 构建期负责固定安装，运行期由 bootstrap 分阶段准备项目与校验
# ============================================================

FROM ghcr.io/openclaw/openclaw:latest

USER root

# 统一 OpenClaw 运行目录与配置文件路径，后续所有 bootstrap 脚本都依赖这两个环境变量。
ENV OPENCLAW_STATE_DIR=/root/.openclaw
ENV OPENCLAW_CONFIG_PATH=/root/.openclaw/openclaw.json
# 强制北京时间，解决 HF Spaces 默认为 UTC 导致日志、汇报、定时相关时间不一致的问题。
ENV TZ=Asia/Shanghai
ENV OPENCLAW_TZ=Asia/Shanghai
# Playwright/agent-browser 直接复用系统 Chromium，避免运行时二次下载浏览器。
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium
ENV PLAYWRIGHT_BROWSERS_PATH=/root/.cache/ms-playwright
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
# 这里声明构建期必须预装的 ClawHub skills，后面的 RUN 会统一循环安装和校验。
ENV CLAWHUB_SKILLS="ddg-web-search n2-free-search tavily-search"

RUN ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone

# 一次性安装基础工具、Buckets 同步工具、浏览器依赖和 Python 包。
# 这些都属于镜像内可确定资产，放在构建期最稳定。
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      python3 python3-pip \
      inotify-tools \
      curl git wget \
      ca-certificates \
      dos2unix \
      chromium chromium-driver \
      libxcb-shm0 libx11-xcb1 libx11-6 libxcb1 libxext6 libxrandr2 \
      libxcomposite1 libxcursor1 libxdamage1 libxfixes3 libxi6 libgtk-3-0 \
      libpangocairo-1.0-0 libpango-1.0-0 libatk1.0-0 libcairo-gobject2 \
      libcairo2 libgdk-pixbuf-2.0-0 libxrender1 libasound2 libfreetype6 \
      libfontconfig1 libdbus-1-3 libnss3 libnspr4 libatk-bridge2.0-0 \
      libdrm2 libxkbcommon0 libatspi2.0-0 libcups2 libxshmfence1 libgbm1 && \
    pip3 install --no-cache-dir --break-system-packages \
      huggingface_hub \
      requests \
      pyyaml \
      tavily-python && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 预创建 OpenClaw 工作目录，保证构建期安装插件/skills 时目录结构已经存在。
RUN mkdir -p /root/.openclaw/extensions /root/.openclaw/skills /root/.openclaw/workspace /root/.openclaw/workspace/skills /root/.openclaw/cron

# 安装 openclaw-china channels 插件。
# 注意：`openclaw china setup` 是交互式向导，需要 TTY，不能在 HF Docker 构建阶段执行。
# 渠道配置统一通过 openclaw.json 模板 + HF Secrets 在运行期注入。
RUN node /app/openclaw.mjs plugins install @openclaw-china/channels && \
    test -d /root/.openclaw/extensions/channels

# 从 openclaw-china 插件目录中复制 wecom-app 专用 skill 到全局 skills 目录。
# 这样运行期不需要再做补装，只做验证即可。
RUN WECOM_SKILL_SRC="/root/.openclaw/extensions/channels/extensions/wecom-app/skills/wecom-app-ops" && \
    test -d "$WECOM_SKILL_SRC" && \
    cp -a "$WECOM_SKILL_SRC" /root/.openclaw/skills/ && \
    test -d /root/.openclaw/skills/wecom-app-ops

# 安装 agent-browser CLI，并在构建期直接做版本校验。
# 如果这里失败，镜像构建就应该失败，而不是拖到运行期再发现。
RUN echo "📦 Installing agent-browser CLI..." && \
    (npm install -g @openclaw/agent-browser || npm install -g agent-browser@latest) && \
    agent-browser --version

# 构建期安装 ClawHub skills，并为带 package.json 的 skill 补齐 Node 依赖。
# 这里保留重试语义，但把网络安装前移到 build 阶段，避免容器启动时再联网装技能。
RUN set -e; \
    cd /root/.openclaw/workspace; \
    install_skill_with_retry() { \
      local skill_name="$1"; \
      local max_retries=3; \
      local retry_delay=10; \
      for attempt in $(seq 1 "$max_retries"); do \
        if npx -y clawhub@latest install "$skill_name" --force; then \
          return 0; \
        fi; \
        if [ "$attempt" -lt "$max_retries" ]; then \
          sleep "$retry_delay"; \
        fi; \
      done; \
      return 1; \
    }; \
    install_skill_node_deps_in_root() { \
      local root_dir="$1"; \
      [ -d "$root_dir" ] || return 0; \
      find "$root_dir" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r skill_dir; do \
        if [ -f "$skill_dir/package.json" ]; then \
          npm install --prefix "$skill_dir" --omit=dev --no-audit --no-fund; \
        fi; \
      done; \
    }; \
    for skill_name in $CLAWHUB_SKILLS; do \
      install_skill_with_retry "$skill_name"; \
      sleep 3; \
    done; \
    install_skill_node_deps_in_root /root/.openclaw/workspace/skills; \
    install_skill_node_deps_in_root /root/.openclaw/skills; \
    for skill_name in $CLAWHUB_SKILLS; do \
      test -d "/root/.openclaw/workspace/skills/$skill_name" -o -d "/root/.openclaw/skills/$skill_name"; \
    done

# 让 openclaw 命令在容器内全局可用，便于 bootstrap 脚本和人工排障直接调用。
RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw && chmod +x /app/openclaw.mjs

# 复制 bootstrap 架构下的所有脚本。
# entrypoint 只做总控，具体逻辑都在 /bootstrap 下按阶段拆开。
COPY openclaw.json /opt/bootstrap-assets/openclaw.json
COPY bootstrap /bootstrap
COPY entrypoint.sh /entrypoint.sh
COPY sync-watch.sh /sync-watch.sh

# 统一转换为 Unix 行尾并设置执行权限，避免 Windows 工作区提交后容器内脚本无法执行。
RUN sed -i 's/\r$//' /opt/bootstrap-assets/openclaw.json && \
    find /bootstrap -type f -name "*.sh" -exec sed -i 's/\r$//' {} + && \
    sed -i 's/\r$//' /entrypoint.sh /sync-watch.sh && \
    chmod +x /entrypoint.sh /sync-watch.sh /bootstrap/*.sh

EXPOSE 7860 18789

HEALTHCHECK --interval=3m --timeout=10s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:7860/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# 入口只走总控脚本，由它按顺序调度 bootstrap 阶段并最终启动 Gateway。
ENTRYPOINT ["/entrypoint.sh"]
