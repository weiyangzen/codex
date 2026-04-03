# rust-release-prepare.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流负责定期更新 `models.json` 文件，该文件包含 Codex CLI 支持的 OpenAI 模型列表。这是自动化维护模型配置的关键工作流，确保用户可以使用最新的模型。

## 功能点目的

1. **模型列表同步**：从 OpenAI API 获取最新可用模型列表
2. **自动 PR 创建**：当模型列表变化时自动创建更新 PR
3. **定期执行**：每 4 小时检查一次，及时发现新模型
4. **人工审查**：通过 PR 流程确保变更经过审查

## 具体技术实现

### 触发条件
```yaml
on:
  workflow_dispatch:
  schedule:
    - cron: "0 */4 * * *"
```

| 触发方式 | 说明 |
|----------|------|
| `workflow_dispatch` | 手动触发，用于紧急更新 |
| `schedule` | 定时触发，每 4 小时执行一次 |

### 并发控制
```yaml
concurrency:
  group: ${{ github.workflow }}
  cancel-in-progress: false
```
- 按工作流名称分组
- 不取消进行中的运行（避免中断正在创建的 PR）

### 权限配置
```yaml
permissions:
  contents: write
  pull-requests: write
```

| 权限 | 用途 |
|------|------|
| `contents: write` | 提交变更、创建分支 |
| `pull-requests: write` | 创建 PR |

### 仓库限制
```yaml
jobs:
  prepare:
    if: github.repository == 'openai/codex'
```
- 仅在 `openai/codex` 仓库运行
- 防止在 fork 中运行浪费资源

### 执行步骤

#### 1. 检出代码
```yaml
- uses: actions/checkout@v6
  with:
    ref: main
    fetch-depth: 0
```
- 检出 main 分支
- 完整历史（用于创建分支）

#### 2. 更新 models.json
```yaml
- name: Update models.json
  env:
    OPENAI_API_KEY: ${{ secrets.CODEX_OPENAI_API_KEY }}
  run: |
    set -euo pipefail
    
    client_version="99.99.99"
    terminal_info="github-actions"
    user_agent="codex_cli_rs/99.99.99 (Linux $(uname -r); $(uname -m)) ${terminal_info}"
    base_url="${OPENAI_BASE_URL:-https://chatgpt.com/backend-api/codex}"
    
    headers=(
      -H "Authorization: Bearer ${OPENAI_API_KEY}"
      -H "User-Agent: ${user_agent}"
    )
    
    url="${base_url%/}/models?client_version=${client_version}"
    curl --http1.1 --fail --show-error --location "${headers[@]}" "${url}" | jq '.' > codex-rs/core/models.json
```

##### 请求参数分析

| 参数 | 值 | 说明 |
|------|-----|------|
| `client_version` | 99.99.99 | 占位版本号 |
| `terminal_info` | github-actions | 标识来源 |
| `user_agent` | codex_cli_rs/... | 客户端标识 |
| `base_url` | chatgpt.com/backend-api/codex | OpenAI Codex API 端点 |

##### curl 选项
- `--http1.1`：强制使用 HTTP/1.1
- `--fail`：HTTP 错误码时返回非零退出码
- `--show-error`：显示错误信息
- `--location`：跟随重定向

#### 3. 创建 PR
```yaml
- name: Open pull request (if changed)
  uses: peter-evans/create-pull-request@v8
  with:
    commit-message: "Update models.json"
    title: "Update models.json"
    body: "Automated update of models.json."
    branch: "bot/update-models-json"
    reviewers: "pakrym-oai,aibrahim-oai"
    delete-branch: true
```

| 配置项 | 说明 |
|--------|------|
| `commit-message` | 提交信息 |
| `title` | PR 标题 |
| `body` | PR 描述 |
| `branch` | 分支名称（固定） |
| `reviewers` | 自动分配的审查者 |
| `delete-branch` | 合并后删除分支 |

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.github/workflows/rust-release-prepare.yml` | 本工作流定义 |
| `codex-rs/core/models.json` | 模型列表文件 |
| `peter-evans/create-pull-request` | PR 创建 Action |

### models.json 结构
模型文件通常包含：
```json
{
  "models": [
    {
      "id": "codex-...",
      "name": "...",
      "capabilities": [...]
    }
  ]
}
```

## 依赖与外部交互

### 外部服务
1. **OpenAI API** (chatgpt.com/backend-api/codex)：获取模型列表
2. **GitHub API**：创建 PR

### 密钥依赖
- `secrets.CODEX_OPENAI_API_KEY`：OpenAI API 访问

### Action 依赖
- `peter-evans/create-pull-request@v8`：PR 创建

## 风险、边界与改进建议

### 风险
1. **API 可用性**：依赖 OpenAI API，服务不可用时会失败
2. **API 变更**：OpenAI API 响应格式变更可能导致解析错误
3. **PR 堆积**：如果 PR 未及时合并，可能产生多个重复 PR
4. **审查者依赖**：固定审查者可能不在或忙碌
5. **版本号硬编码**：99.99.99 是占位符，可能误导

### 边界条件
- 仅在 `openai/codex` 仓库运行
- 需要 `CODEX_OPENAI_API_KEY`
- 每 4 小时最多创建一个 PR

### 改进建议
1. **变更检测**：添加步骤比较新旧文件，无变化时不创建 PR
2. **动态审查者**：从团队列表中轮换选择审查者
3. **失败通知**：添加失败通知（Slack/Email）
4. **API 重试**：添加 curl 重试逻辑处理临时失败
5. **变更描述**：在 PR body 中列出具体变更（新增/删除的模型）
6. **版本号**：使用实际版本号或从 Git 获取
7. **自动合并**：对于仅添加新模型的变更，配置自动合并

### 建议的变更检测
```yaml
- name: Check for changes
  id: check
  run: |
    if git diff --quiet codex-rs/core/models.json; then
      echo "changed=false" >> "$GITHUB_OUTPUT"
    else
      echo "changed=true" >> "$GITHUB_OUTPUT"
      # 生成变更摘要
      echo "summary<<EOF" >> "$GITHUB_OUTPUT"
      git diff codex-rs/core/models.json | head -100 >> "$GITHUB_OUTPUT"
      echo "EOF" >> "$GITHUB_OUTPUT"
    fi

- name: Open pull request
  if: steps.check.outputs.changed == 'true'
  uses: peter-evans/create-pull-request@v8
  with:
    body: |
      Automated update of models.json.
      
      ### Changes
      ```diff
      ${{ steps.check.outputs.summary }}
      ```
```

### 建议的审查者轮换
```yaml
reviewers: ${{ fromJson('["pakrym-oai","aibrahim-oai","other-reviewer"]')[github.run_number % 3] }}
```
