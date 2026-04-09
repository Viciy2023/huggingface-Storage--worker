# Private Buckets Content Example

本仓库是公开模板骨架，不提交私有业务文件。

你可以在本地子项目里保留这些私有文件，按 OpenClaw 真实运行路径维护，并通过 `.gitignore` 忽略；真正部署时，再同步到私有 HF Buckets。

如果你要完整启用工作区、定时任务、私有插件预设，请先将以下内容上传到你自己的私有 HF Buckets：

## 建议上传目录（按 OpenClaw 实际运行路径）

1. `workspace/`
2. `cron/`
3. `extensions/clawedit/`
4. `skills/`（如果你有私有 skill）

## 最低建议内容

### 1. 工作区文档

例如：

1. `workspace/AGENTS.md`
2. `workspace/BOOTSTRAP.md`
3. `workspace/HEARTBEAT.md`
4. `workspace/IDENTITY.md`
5. `workspace/MEMORY.md`
6. `workspace/SOUL.md`
7. `workspace/TOOLS.md`
8. `workspace/USER.md`
9. `workspace/WORKFLOW_AUTO.md`
10. `workspace/task-dispatch.md`

### 2. 定时任务

例如：

1. `cron/jobs.json`

### 3. 私有插件预设

例如：

1. `extensions/clawedit/index.ts`
2. `extensions/clawedit/package.json`
3. `extensions/clawedit/openclaw.plugin.json`

## 使用原则

1. 公开 GitHub 仓库只放部署骨架
2. 私有业务文件只放在私有 HF Buckets
3. 容器启动时优先从 Buckets 恢复私有内容
