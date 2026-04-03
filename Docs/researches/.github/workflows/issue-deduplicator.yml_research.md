# issue-deduplicator.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流利用 OpenAI Codex AI 能力自动检测新创建的 Issue 是否与现有 Issue 重复。这是项目维护的智能化辅助工具，帮助减少重复问题，提高 Issue 管理效率。

## 功能点目的

1. **自动重复检测**：新 Issue 创建时自动分析内容相似度
2. **两阶段搜索策略**：先搜索所有 Issue，如无匹配再搜索开放的 Issue
3. **智能评论**：在检测到潜在重复时自动添加评论
4. **标签触发**：支持通过 `codex-deduplicate` 标签手动触发

## 具体技术实现

### 触发条件
```yaml
on:
  issues:
    types:
      - opened
      - labeled
```

| 触发时机 | 说明 |
|----------|------|
| `opened` | 新 Issue 创建时 |
| `labeled` | 添加标签时（用于手动触发） |

### 执行条件
```yaml
if: github.repository == 'openai/codex' && (github.event.action == 'opened' || (github.event.action == 'labeled' && github.event.label.name == 'codex-deduplicate'))
```
- 仅在 `openai/codex` 仓库运行（防止 fork 浪费资源）
- 新 Issue 或添加 `codex-deduplicate` 标签时触发

### 工作流结构

工作流包含 4 个 job：
1. `gather-duplicates-all`：第一阶段，搜索所有 Issue
2. `gather-duplicates-open`：第二阶段，仅搜索开放 Issue（回退策略）
3. `select-final`：选择最终结果
4. `comment-on-issue`：在 Issue 上添加评论

### Job 1: gather-duplicates-all

#### 输入准备
```yaml
- name: Prepare Codex inputs
  run: |
    CURRENT_ISSUE_FILE=codex-current-issue.json
    EXISTING_ALL_FILE=codex-existing-issues-all.json
    
    gh issue list --repo "$REPO" \
      --json number,title,body,createdAt,updatedAt,state,labels \
      --limit 1000 --state all \
      | jq '[.[] | {number, title, body: ((.body // "")[0:4000]), ...}]' \
      > "$EXISTING_ALL_FILE"
    
    gh issue view "$ISSUE_NUMBER" --repo "$REPO" \
      --json number,title,body \
      | jq '{number, title, body: ((.body // "")[0:4000])}' \
      > "$CURRENT_ISSUE_FILE"
```

- 获取最近 1000 个 Issue（所有状态）
- 限制 body 长度为 4000 字符（控制 token 使用量）
- 使用 `gh` CLI 和 `jq` 处理数据

#### AI 分析
```yaml
- id: codex-all
  uses: openai/codex-action@main
  with:
    openai-api-key: ${{ secrets.CODEX_OPENAI_API_KEY }}
    allow-users: "*"
    prompt: |
      You are an assistant that triages new GitHub issues by identifying potential duplicates.
      
      You will receive:
      - `codex-current-issue.json`: 新 Issue 信息
      - `codex-existing-issues-all.json`: 现有 Issue 列表
      
      Instructions:
      - Compare to find up to five potential duplicates
      - Prioritize concrete overlap in symptoms, reproduction details
      - Return fewer matches rather than speculative ones
      - Include at most five issue numbers
      - Provide a short reason for your decision
    
    output-schema: |
      {
        "type": "object",
        "properties": {
          "issues": { "type": "array", "items": { "type": "string" } },
          "reason": { "type": "string" }
        },
        "required": ["issues", "reason"]
      }
```

- 使用 `openai/codex-action@main`
- 结构化输出（JSON Schema 约束）
- 最多返回 5 个潜在重复 Issue

#### 输出规范化
```yaml
- id: normalize-all
  run: |
    raw=${CODEX_OUTPUT//$'\r'/}
    if [ -n "$raw" ] && printf '%s' "$raw" | jq -e 'type == "object" and (.issues | type == "array")' >/dev/null 2>&1; then
      issues=$(printf '%s' "$raw" | jq -c '[.issues[] | tostring]')
      reason=$(printf '%s' "$raw" | jq -r '.reason // ""')
    fi
    
    # 过滤掉当前 Issue 本身，去重，限制 5 个
    filtered=$(jq -cn --argjson issues "$issues" --arg current "$CURRENT_ISSUE_NUMBER" '[
      $issues[] | tostring | select(. != $current)
    ] | reduce .[] as $issue ([]; if index($issue) then . else . + [$issue] end) | .[:5]')
```

- 清理 Windows 换行符 (`\r`)
- 验证 JSON 结构和类型
- 过滤当前 Issue、去重、限制数量

### Job 2: gather-duplicates-open

与 Job 1 类似，但：
- 仅搜索 `state open` 的 Issue
- 仅在 Job 1 无匹配时执行（`needs.gather-duplicates-all.outputs.has_matches != 'true'`）
- 作为回退策略，放宽搜索范围

### Job 3: select-final

```yaml
- id: select-final
  run: |
    selected_issues='[]'
    selected_reason='No plausible duplicates found.'
    selected_pass='none'
    
    if [ "$PASS1_HAS_MATCHES" = "true" ]; then
      selected_issues=${PASS1_ISSUES:-'[]'}
      selected_pass='all'
    fi
    
    if [ "$PASS2_HAS_MATCHES" = "true" ]; then
      selected_issues=${PASS2_ISSUES:-'[]'}
      selected_pass='open-fallback'
    fi
```

- 优先使用第一阶段结果
- 记录使用的搜索策略（`pass` 字段）

### Job 4: comment-on-issue

```yaml
- name: Comment on issue
  uses: actions/github-script@v8
  with:
    script: |
      const filteredIssues = [...new Set(issues.map((value) => String(value)))]
        .filter((value) => value !== currentIssueNumber)
        .slice(0, 5);
      
      const lines = [
        'Potential duplicates detected. Please review them and close your issue if it is a duplicate.',
        '',
        ...filteredIssues.map((value) => `- #${String(value)}`),
        '',
        '*Powered by [Codex Action](https://github.com/openai/codex-action)*'
      ];
      
      await github.rest.issues.createComment({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number: context.payload.issue.number,
        body: lines.join("\n")
      });
```

- 格式化评论内容
- 列出潜在重复 Issue 链接
- 添加 Codex Action 署名

#### 标签清理
```yaml
- name: Remove codex-deduplicate label
  if: ${{ always() && github.event.action == 'labeled' && github.event.label.name == 'codex-deduplicate' }}
  run: |
    gh issue edit "$ISSUE_NUMBER" --remove-label codex-deduplicate || true
```
- 如果是通过标签触发的，完成后移除标签

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.github/workflows/issue-deduplicator.yml` | 本工作流定义 |
| `openai/codex-action` | OpenAI Codex GitHub Action |

### API 使用
- `gh issue list`：列出 Issue
- `gh issue view`：获取单个 Issue
- `gh issue edit`：编辑 Issue（移除标签）
- `github.rest.issues.createComment`：创建评论

## 依赖与外部交互

### 外部服务
1. **OpenAI API**：通过 `codex-action` 调用 GPT 模型
2. **GitHub API**：Issue 查询和评论

### 密钥依赖
- `secrets.CODEX_OPENAI_API_KEY`：OpenAI API 访问
- `github.token`：GitHub API 访问

### Action 依赖
- `openai/codex-action@main`：AI 分析
- `actions/github-script@v8`：JavaScript 执行

## 风险、边界与改进建议

### 风险
1. **API 成本**：每个新 Issue 都调用 OpenAI API，成本随 Issue 量增加
2. **AI 误判**：可能产生误报（非重复标记为重复）或漏报
3. **Token 限制**：Issue body 截断到 4000 字符，可能丢失关键信息
4. **隐私问题**：Issue 内容发送到 OpenAI API
5. **Action 版本**：使用 `@main` 分支，可能引入不稳定变更

### 边界条件
- 最多处理 1000 个历史 Issue
- 最多返回 5 个潜在重复
- 仅适用于 `openai/codex` 仓库
- 需要 OpenAI API Key

### 改进建议
1. **版本固定**：将 `codex-action@main` 改为固定版本
2. **缓存相似度**：缓存 Issue 向量表示，减少 API 调用
3. **阈值调整**：添加相似度阈值，低置信度时不评论
4. **反馈机制**：允许用户点击 "Not a duplicate" 反馈
5. **批量处理**：对大量 Issue 使用批处理优化
6. **本地模型**：考虑使用本地嵌入模型减少 API 依赖
7. **隐私控制**：添加标签允许用户选择不发送内容到 AI

### 建议的阈值配置
```yaml
# 在 output-schema 中添加置信度
output-schema: |
  {
    "properties": {
      "issues": { "type": "array", "items": { "type": "string" } },
      "reason": { "type": "string" },
      "confidence": { "type": "number", "minimum": 0, "maximum": 1 }
    }
  }

# 在 comment 步骤中添加阈值检查
if: ${{ fromJSON(needs.select-final.outputs.codex_output).confidence > 0.7 }}
```
