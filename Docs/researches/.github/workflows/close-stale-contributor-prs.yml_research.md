# close-stale-contributor-prs.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流自动关闭长时间未更新的内部贡献者 PR，帮助维护整洁的 PR 队列。该工作流专门针对具有写入权限的内部贡献者（员工），而非外部社区贡献者。

## 功能点目的

1. **清理陈旧 PR**：自动关闭 14 天未更新的内部贡献者 PR
2. **区分贡献者类型**：仅处理具有写入权限的内部贡献者，保护外部贡献者体验
3. **友好关闭**：添加说明评论，告知可以重新打开或创建新 PR
4. **可配置模式**：支持 dry-run 模式测试而不实际关闭

## 具体技术实现

### 触发条件
```yaml
on:
  workflow_dispatch:
  schedule:
    - cron: "0 6 * * *"
```

| 触发方式 | 说明 |
|----------|------|
| `workflow_dispatch` | 手动触发，用于测试或紧急执行 |
| `schedule` | 定时触发，每天 UTC 6:00 执行 |

### 权限配置
```yaml
permissions:
  contents: read
  issues: write
  pull-requests: write
```

| 权限 | 用途 |
|------|------|
| `contents: read` | 读取仓库内容 |
| `issues: write` | 创建评论（PR 评论使用 issues API） |
| `pull-requests: write` | 更新 PR 状态（关闭） |

### 仓库限制
```yaml
jobs:
  close-stale-contributor-prs:
    if: github.repository == 'openai/codex'
```
- 仅在 `openai/codex` 仓库运行
- 防止在 fork 中运行误关闭 PR

### 核心逻辑（JavaScript）
```javascript
const DAYS_INACTIVE = 14;
const cutoff = new Date(Date.now() - DAYS_INACTIVE * 24 * 60 * 60 * 1000);
const dryRun = false;
```

#### 参数配置
| 参数 | 值 | 说明 |
|------|-----|------|
| `DAYS_INACTIVE` | 14 | 不活跃天数阈值 |
| `dryRun` | false | 是否仅模拟运行 |

#### PR 获取
```javascript
const prs = await github.paginate(github.rest.pulls.list, {
  owner,
  repo,
  state: "open",
  per_page: 100,
  sort: "updated",
  direction: "asc",
});
```
- 获取所有 open 状态的 PR
- 每页 100 条（API 最大值）
- 按更新时间升序排序（最旧的在前）

#### 过滤逻辑
```javascript
for (const pr of prs) {
  const lastUpdated = new Date(pr.updated_at);
  if (lastUpdated > cutoff) {
    core.info(`PR ${pr.number} is fresh`);
    continue;
  }

  if (!pr.user || pr.user.type !== "User") {
    core.info(`PR ${pr.number} wasn't created by a user`);
    continue;
  }

  // 检查权限
  const permissionResponse = await github.rest.repos.getCollaboratorPermissionLevel({
    owner, repo, username: pr.user.login
  });
  const hasContributorAccess = ["admin", "maintain", "write"].includes(permission);
  if (!hasContributorAccess) {
    core.info(`Author ${pr.user.login} has ${permission} access; skipping #${pr.number}`);
    continue;
  }
  
  stalePrs.push(pr);
}
```

过滤条件：
1. **时间检查**：`updated_at` 超过 14 天
2. **用户类型**：必须是真实用户（非 App、Bot）
3. **权限检查**：具有 `admin`、`maintain` 或 `write` 权限

#### 权限级别说明
| 级别 | 说明 |
|------|------|
| `admin` | 管理员权限 |
| `maintain` | 维护者权限 |
| `write` | 写入权限 |
| `triage` | 分类权限（不满足条件） |
| `read` | 只读权限（不满足条件） |

#### 关闭操作
```javascript
const closeComment = `Closing this pull request because it has had no updates for more than ${DAYS_INACTIVE} days. If you plan to continue working on it, feel free to reopen or open a new PR.`;

if (dryRun) {
  core.info(`[dry-run] Would close contributor PR #${issue_number}`);
  continue;
}

await github.rest.issues.createComment({
  owner, repo, issue_number, body: closeComment
});

await github.rest.pulls.update({
  owner, repo, pull_number: issue_number, state: "closed"
});
```

- 添加友好说明评论
- 更新 PR 状态为 `closed`
- dry-run 模式仅记录不执行

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.github/workflows/close-stale-contributor-prs.yml` | 本工作流定义 |
| `actions/github-script@v8` | 执行 JavaScript 代码的 Action |

### GitHub API 使用
1. `github.rest.pulls.list` - 列出 PR
2. `github.rest.repos.getCollaboratorPermissionLevel` - 获取用户权限
3. `github.rest.issues.createComment` - 创建评论
4. `github.rest.pulls.update` - 更新 PR 状态

## 依赖与外部交互

### 外部 Action
- `actions/github-script@v8`：在 workflow 中直接编写 JavaScript 代码

### GitHub API
- Pulls API：PR 列表和更新
- Repos API：协作者权限查询
- Issues API：PR 评论（GitHub 中 PR 是特殊的 issue）

## 风险、边界与改进建议

### 风险
1. **误关闭风险**：权限判断错误可能导致错误关闭外部贡献者 PR
2. **时间阈值**：14 天可能过短，某些复杂 PR 需要更长时间
3. **无通知机制**：贡献者可能不会注意到 PR 被关闭
4. **Action 版本**：使用 v8，需要关注更新

### 边界条件
- 仅处理 open 状态的 PR
- 需要 `issues: write` 和 `pull-requests: write` 权限
- 仅在 `openai/codex` 仓库运行
- API 限制：每页最多 100 条，大量 PR 需要分页

### 改进建议
1. **标签豁免**：添加特定标签（如 `keep-open`）的 PR 跳过检查
2. **Draft PR 处理**：Draft PR 可以设置更长的阈值或不处理
3. **提前通知**：关闭前 2-3 天添加警告评论
4. **可配置阈值**：通过环境变量或输入参数化天数
5. **统计报告**：生成关闭 PR 的统计报告
6. **排除分支**：某些长期分支的 PR 可以排除

### 建议的改进代码
```javascript
// 标签豁免
const labels = pr.labels.map(l => l.name);
if (labels.includes('keep-open') || labels.includes('in-progress')) {
  core.info(`PR ${pr.number} has exemption label`);
  continue;
}

// Draft PR 处理
if (pr.draft) {
  core.info(`PR ${pr.number} is draft, using extended threshold`);
  // 使用更长的阈值，如 30 天
}

// 提前通知（需要额外状态跟踪）
const warningComment = `This PR will be closed in 3 days due to inactivity.`;
```
