# issue-labeler.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流利用 OpenAI Codex AI 能力自动为新创建的 GitHub Issue 分类并添加标签。这是项目维护的智能化辅助工具，帮助维护者快速识别 Issue 类型和涉及的产品模块。

## 功能点目的

1. **自动分类**：根据 Issue 内容自动判断类型（bug/enhancement/documentation）
2. **产品模块识别**：识别涉及的产品（CLI/extension/app/web 等）
3. **主题标签**：添加主题标签（windows-os/mcp/auth 等）
4. **标签触发**：支持通过 `codex-label` 标签手动触发重新分类

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
| `opened` | 新 Issue 创建时自动分类 |
| `labeled` | 添加 `codex-label` 标签时手动触发 |

### 执行条件
```yaml
if: github.repository == 'openai/codex' && (github.event.action == 'opened' || (github.event.action == 'labeled' && github.event.label.name == 'codex-label'))
```
- 仅在 `openai/codex` 仓库运行
- 新 Issue 或添加 `codex-label` 标签时触发

### 工作流结构

工作流包含 2 个 job：
1. `gather-labels`：生成标签建议
2. `apply-labels`：应用标签

### Job 1: gather-labels

#### AI 分析
```yaml
- id: codex
  uses: openai/codex-action@main
  with:
    openai-api-key: ${{ secrets.CODEX_OPENAI_API_KEY }}
    allow-users: "*"
    prompt: |
      You are an assistant that reviews GitHub issues for the repository.
      
      Your job is to choose the most appropriate labels for the issue.
      
      Rules:
      - Add one (and only one) of: bug, enhancement, documentation
      - If applicable, add one product label: CLI, extension, app, codex-web, github-action, iOS
      - Additionally add zero or more topic labels
      
      Issue number: ${{ github.event.issue.number }}
      Issue title: ${{ github.event.issue.title }}
      Issue body: ${{ github.event.issue.body }}
    
    output-schema: |
      {
        "type": "object",
        "properties": {
          "labels": { "type": "array", "items": { "type": "string" } }
        },
        "required": ["labels"]
      }
```

#### 标签体系

**类型标签（必选其一）**：
| 标签 | 说明 |
|------|------|
| `bug` | 可复现的缺陷 |
| `enhancement` | 功能请求或改进 |
| `documentation` | 文档更新或修正 |

**产品标签（可选其一）**：
| 标签 | 说明 |
|------|------|
| `CLI` | 命令行界面 |
| `extension` | VS Code 扩展 |
| `app` | 桌面应用 |
| `codex-web` | Web UI/Cloud |
| `github-action` | GitHub Action |
| `iOS` | iOS 应用 |

**主题标签（可选多个）**：
| 标签 | 说明 |
|------|------|
| `windows-os` | Windows 特定问题 |
| `mcp` | Model Context Protocol |
| `mcp-server` | codex mcp-server 命令 |
| `azure` | Azure OpenAI 部署 |
| `model-behavior` | LLM 行为问题 |
| `code-review` | 代码审查功能 |
| `safety-check` | 网络安全风险检测 |
| `auth` | 认证和访问令牌 |
| `codex-exec` | codex exec 命令 |
| `context-management` | 上下文窗口管理 |
| `custom-model` | 自定义模型提供商 |
| `rate-limits` | 令牌限制和速率限制 |
| `sandbox` | 本地沙箱环境 |
| `tool-calls` | 工具调用问题 |
| `TUI` | 终端用户界面 |

### Job 2: apply-labels

#### 标签应用
```yaml
- name: Apply labels
  run: |
    json=${CODEX_OUTPUT//$'\r'/}
    if [ -z "$json" ]; then
      echo "Codex produced no output. Skipping."
      exit 0
    fi
    
    if ! printf '%s' "$json" | jq -e 'type == "object" and (.labels | type == "array")' >/dev/null 2>&1; then
      echo "Codex output did not include a labels array."
      exit 0
    fi
    
    labels=$(printf '%s' "$json" | jq -r '.labels[] | tostring')
    
    cmd=(gh issue edit "$ISSUE_NUMBER")
    while IFS= read -r label; do
      cmd+=(--add-label "$label")
    done <<< "$labels"
    
    "${cmd[@]}" || true
```

- 清理 Windows 换行符
- 验证 JSON 结构
- 使用 `gh issue edit --add-label` 批量添加标签
- `|| true` 确保部分失败不中断

#### 触发标签清理
```yaml
- name: Remove codex-label trigger
  if: ${{ always() && github.event.action == 'labeled' && github.event.label.name == 'codex-label' }}
  run: |
    gh issue edit "$ISSUE_NUMBER" --remove-label codex-label || true
```

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.github/workflows/issue-labeler.yml` | 本工作流定义 |
| `openai/codex-action` | OpenAI Codex GitHub Action |

### API 使用
- `gh issue edit`：添加/移除标签

## 依赖与外部交互

### 外部服务
1. **OpenAI API**：通过 `codex-action` 调用 GPT 模型
2. **GitHub API**：标签管理

### 密钥依赖
- `secrets.CODEX_OPENAI_API_KEY`：OpenAI API 访问
- `github.token`：GitHub API 访问

### Action 依赖
- `openai/codex-action@main`：AI 分类
- `actions/checkout@v6`：代码检出（虽然实际上不需要代码）

## 风险、边界与改进建议

### 风险
1. **API 成本**：每个新 Issue 都调用 OpenAI API
2. **标签误分类**：AI 可能选择不恰当的标签
3. **标签不存在**：如果 AI 返回未定义的标签，命令会失败
4. **Action 版本**：使用 `@main` 分支，不稳定
5. **隐私问题**：Issue 内容发送到 OpenAI API

### 边界条件
- 仅适用于 `openai/codex` 仓库
- 需要 OpenAI API Key
- 标签必须在仓库中预先创建

### 改进建议
1. **版本固定**：将 `codex-action@main` 改为固定版本
2. **标签验证**：在应用前验证标签是否存在
3. **置信度阈值**：添加置信度分数，低置信度时不自动分类
4. **反馈学习**：收集维护者的标签修正，改进提示词
5. **批量标签**：支持一次处理多个未标签 Issue
6. **标签同步**：自动同步标签定义到提示词
7. **多语言支持**：改进非英语 Issue 的分类准确性

### 建议的标签验证
```yaml
- name: Validate and apply labels
  run: |
    # 获取仓库所有标签
    available_labels=$(gh label list --json name -q '.[].name')
    
    # 过滤 AI 建议的标签
    valid_labels=()
    for label in $suggested_labels; do
      if echo "$available_labels" | grep -q "^${label}$"; then
        valid_labels+=("$label")
      else
        echo "Warning: Label '$label' does not exist"
      fi
    done
    
    # 应用有效标签
    if [ ${#valid_labels[@]} -gt 0 ]; then
      gh issue edit "$ISSUE_NUMBER" --add-label "${valid_labels[*]}"
    fi
```

### 建议的置信度配置
```yaml
output-schema: |
  {
    "properties": {
      "labels": { "type": "array", "items": { "type": "string" } },
      "confidence": { "type": "number", "minimum": 0, "maximum": 1 },
      "reasoning": { "type": "string" }
    }
  }
```
