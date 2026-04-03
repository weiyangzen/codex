# cla.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流实现 Contributor License Agreement (CLA) 签署检查，确保所有向项目贡献代码的开发者已签署 CLA。这是开源项目法律合规的重要组成部分，保护项目和贡献者的权益。

## 功能点目的

1. **CLA 签署验证**：检查 PR 作者是否已签署贡献者许可协议
2. **自动评论交互**：通过评论触发重新检查或签署流程
3. **PR 锁定**：合并后锁定 PR 以保留 CLA 协议记录
4. **白名单支持**：允许特定用户（如机器人）跳过 CLA 检查

## 具体技术实现

### 触发条件
```yaml
on:
  issue_comment:
    types: [created]
  pull_request_target:
    types: [opened, closed, synchronize]
```

| 事件 | 触发时机 |
|------|----------|
| `issue_comment:created` | 创建评论时（用于重新检查或签署） |
| `pull_request_target:opened` | PR 创建时 |
| `pull_request_target:closed` | PR 关闭时（检查是否合并） |
| `pull_request_target:synchronize` | PR 更新时（新提交推送） |

使用 `pull_request_target` 而非 `pull_request` 的原因：
- `pull_request_target` 在目标仓库上下文中运行
- 可以访问仓库的 secrets（如 CLA 签名存储）
- 即使 PR 来自 fork 也能正常工作

### 权限配置
```yaml
permissions:
  actions: write
  contents: write
  pull-requests: write
  statuses: write
```

| 权限 | 用途 |
|------|------|
| `actions: write` | 可能用于触发其他工作流 |
| `contents: write` | 锁定 PR、写入签名存储 |
| `pull-requests: write` | 评论、更新 PR 状态 |
| `statuses: write` | 设置 commit status |

### 仓库限制
```yaml
jobs:
  cla:
    if: ${{ github.repository_owner == 'openai' }}
```
- 仅在 `openai` 组织的仓库中运行
- 防止在 fork 中运行浪费资源
- 避免向 fork 的贡献者发送重复的 CLA 通知

### 执行条件
```yaml
if: |
  (
    github.event_name == 'pull_request_target' &&
    (
      github.event.action == 'opened' ||
      github.event.action == 'synchronize' ||
      (github.event.action == 'closed' && github.event.pull_request.merged == true)
    )
  ) ||
  (
    github.event_name == 'issue_comment' &&
    (
      github.event.comment.body == 'recheck' ||
      github.event.comment.body == 'I have read the CLA Document and I hereby sign the CLA'
    )
  )
```

#### PR 事件处理
- `opened`：新 PR 创建时检查
- `synchronize`：PR 更新时重新检查
- `closed` + `merged == true`：合并后锁定 PR

#### 评论事件处理
- `recheck`：手动触发重新检查
- `I have read the CLA Document and I hereby sign the CLA`：签署 CLA

### CLA Assistant 配置
```yaml
- uses: contributor-assistant/github-action@v2.6.1
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  with:
    path-to-document: https://github.com/openai/codex/blob/main/docs/CLA.md
    path-to-signatures: signatures/cla.json
    branch: cla-signatures
    allowlist: codex,dependabot,dependabot[bot],github-actions[bot]
```

| 配置项 | 说明 |
|--------|------|
| `path-to-document` | CLA 文档位置（主分支） |
| `path-to-signatures` | 签名存储文件路径 |
| `branch` | 签名存储分支（独立于主分支） |
| `allowlist` | 跳过 CLA 检查的用户/机器人列表 |

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.github/workflows/cla.yml` | 本工作流定义 |
| `docs/CLA.md` | 贡献者许可协议文档 |
| `signatures/cla.json`（在 cla-signatures 分支） | CLA 签名存储 |

### CLA 文档结构
CLA 文档通常包含：
- 授予项目的许可（专利、版权）
- 原创性声明
- 贡献者信息收集

### 签名存储格式
`cla.json` 格式示例：
```json
{
  "signedContributors": [
    {
      "name": "username",
      "id": 123456,
      "comment_id": 1234567890,
      "created_at": "2024-01-01T00:00:00Z",
      "repoId": 123456789,
      "pullRequestNo": 123
    }
  ]
}
```

## 依赖与外部交互

### 外部 Action
- `contributor-assistant/github-action@v2.6.1`：CLA Assistant 官方 Action

### 依赖的资源
- `docs/CLA.md`：CLA 文档
- `cla-signatures` 分支：签名存储
- `secrets.GITHUB_TOKEN`：GitHub API 访问

## 风险、边界与改进建议

### 风险
1. **Action 版本**：使用 v2.6.1，需要关注安全更新
2. **签名存储分支**：`cla-signatures` 分支需要保护，防止篡改
3. **白名单维护**：需要及时更新以包含新的自动化工具
4. **fork 贡献者体验**：fork 的贡献者可能不清楚 CLA 流程

### 边界条件
- 仅在 `openai` 组织仓库运行
- 需要 `cla-signatures` 分支存在
- 首次贡献者需要理解 CLA 签署流程

### 改进建议
1. **Action 更新**：评估升级到 v3 版本
2. **自动化白名单**：自动检测并添加常见的 GitHub Apps
3. **签署提醒优化**：改进首次贡献者的签署引导
4. **签名验证**：添加签名完整性检查
5. **多语言支持**：如果项目国际化，考虑多语言 CLA 文档
6. **企业贡献者**：支持企业贡献者的不同签署流程

### 建议的白名单更新
```yaml
allowlist: >
  codex,
  dependabot[bot],
  dependabot,
  github-actions[bot],
  renovate[bot],
  semantic-release-bot,
  allcontributors[bot]
```
