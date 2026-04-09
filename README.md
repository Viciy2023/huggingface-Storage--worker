---
title: OpenClaw
emoji: 🦞
colorFrom: red
colorTo: yellow
sdk: docker
pinned: false
---

# HF Storage Worker Template

这是一个适合公开仓库的 Hugging Face Docker Space 模板，用于部署带 HF Buckets 持久化能力的 OpenClaw Worker。

你可以在本地子项目里保留私有运行预设文件，按 OpenClaw 的真实运行路径维护，但通过 `.gitignore` 忽略，不提交到公开 GitHub 仓库。

## 1. 公开仓库与私有数据的边界

当前模板的设计原则是：

1. GitHub 公开仓库只保存可公开的部署骨架
2. 私有工作区文件、私有 cron、私有插件预设通过 HF Buckets 保存

公开仓库建议保留：

1. `Dockerfile`
2. `entrypoint.sh`
3. `sync-watch.sh`
4. `bootstrap/`
5. `.github/`
6. `.gitignore`
7. `openclaw.json`
8. `README.md`

私有 HF Buckets 建议按 OpenClaw 实际运行路径存放：

1. `workspace/`
2. `cron/`
3. `extensions/clawedit/`
4. `skills/`（如有私有 skill）

## 2. 本地开发与提交流程

本地修改当前仓库后，推送到 GitHub：

```powershell
git add .
git commit -m "update hf storage worker"
git push origin main
```

## 3. GitHub Actions 自动同步到 HF Space

本仓库包含工作流：

- `.github/workflows/sync-to-hf-space.yml`

触发条件：

1. 推送到 `main`
2. 推送到 `master`

在仓库设置中需要配置：

1. Secret：`HF_TOKEN`
2. Repository Variable：`HF_SPACE_REPO`

示例：

```text
HF_SPACE_REPO=your-hf-username/your-space-name
```

工作流会把当前 GitHub 仓库内容同步到对应的 HF Space。

## 4. HF Space 构建阶段

HF Space 收到 Git 更新后，会自动读取：

1. `Dockerfile`
2. `README.md` frontmatter

然后开始 Docker 构建。

构建阶段会安装：

1. OpenClaw 中国区插件
2. `wecom-app-ops`
3. `agent-browser`
4. ClawHub skills
5. Python / Chromium / 同步依赖

其中：

1. ClawHub skills 当前只包含 `ddg-web-search` 和 `n2-free-search`
2. Tavily 能力通过 `tavily-python` 提供，不依赖名为 `tavily-search` 的 ClawHub skill

## 5. 容器启动后的运行顺序

容器启动后，执行入口：

- `entrypoint.sh`

它按顺序执行以下 bootstrap 阶段：

1. `bootstrap/10-init-state.sh`
2. `bootstrap/20-load-buckets.sh`
3. `bootstrap/25-seed-runtime-files.sh`
4. `bootstrap/30-render-config.sh`
5. `bootstrap/40-deploy-projects.sh`
6. `bootstrap/50-network-checks.sh`
7. `bootstrap/60-verify-runtime.sh`
8. `bootstrap/70-install-cli.sh`

然后：

9. 启动 `sync-watch.sh --daemon`
10. 启动 OpenClaw Gateway

## 6. HF Buckets 持久化逻辑

`bootstrap/20-load-buckets.sh` 会优先从 HF Buckets 恢复：

1. `openclaw.json`
2. `workspace/`
3. `extensions/`
4. `cron/`
5. `skills/`

这意味着私有预设文件应该提前上传到私有 HF Buckets，而不是放在公开 GitHub 仓库里。

## 7. 首次启动逻辑

如果 Buckets 里还没有历史数据：

1. 容器会先使用镜像内自带的 `openclaw.json` 模板
2. 然后继续渲染 Secrets 并启动

注意：

1. 私有 `workspace/` 不会从 GitHub 自动补齐
2. 私有 `cron/` 不会从 GitHub 自动补齐
3. 私有 `extensions/clawedit/` 不会从 GitHub 自动补齐

这些内容应由你提前上传到 HF Buckets。

## 8. 你需要准备什么

### GitHub 侧

1. `HF_TOKEN` secret
2. `HF_SPACE_REPO` repository variable

### HF Space 侧

1. Docker Space 项目
2. 运行时所需 Secrets
3. 私有 HF Buckets 数据集

### HF Buckets 侧

建议提前放入：

1. `workspace/`
2. `cron/`
3. `extensions/clawedit/`

## 9. 一句话总结

本模板负责公开的部署骨架，私有业务文件交给 HF Buckets 保存。GitHub 推送后，GitHub Actions 自动同步到 HF Space，HF Space 构建并启动容器，容器启动时优先恢复私有 Buckets 数据，最后启动 OpenClaw Gateway。
