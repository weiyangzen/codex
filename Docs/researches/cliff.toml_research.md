# cliff.toml 文件研究文档

## 场景与职责

cliff.toml 是 [git-cliff](https://git-cliff.org/) 工具的配置文件，用于：
- **自动生成变更日志**: 从 Git 提交历史生成结构化的 CHANGELOG.md
- **版本发布管理**: 为每个版本生成一致的发布说明
- **提交分类**: 根据提交消息前缀自动分类（Features、Bug Fixes 等）
- **发布流程自动化**: 与 CI/CD 集成，自动更新发布说明

## 功能点目的

### 1. 变更日志生成流程
```
Git 提交历史
    ↓
[Conventional Commits 解析]
    ↓
[分组和过滤]
    ↓
[模板渲染]
    ↓
CHANGELOG.md
```

### 2. 提交分类规则
| 前缀 | 分组 | 说明 |
|------|------|------|
| `^feat` | 🚀 Features | 新功能 |
| `^fix` | 🪲 Bug Fixes | 修复 |
| `^bump` | 🛳️ Release | 版本升级 |
| `.*` | 💼 Other | 其他（兜底）|

### 3. 模板变量
| 变量 | 说明 | 示例 |
|------|------|------|
| `{{ version }}` | 版本号 | `0.101.0` |
| `{{ timestamp }}` | 时间戳 | 用于生成日期 |
| `{{ commits }}` | 提交列表 | 按分组组织 |
| `{{ commit.scope }}` | 提交范围 | `tui`, `core` |
| `{{ commit.breaking }}` | 是否破坏性变更 | `true`/`false` |

## 具体技术实现

### 文件结构
```toml
[changelog]           # 变更日志配置
├── header           # 页眉模板
├── body             # 主体模板（提交列表）
├── footer           # 页脚模板
├── trim             # 是否修剪空白
└── postprocessors   # 后处理器

[git]                # Git 配置
├── conventional_commits  # 启用约定式提交
├── commit_parsers        # 提交解析规则
├── filter_unconventional # 是否过滤非约定式提交
├── sort_commits          # 提交排序方式
└── topo_order            # 是否拓扑排序
```

### 模板引擎
使用 [Tera](https://keats.github.io/tera/) 模板引擎（类似 Jinja2）：

```jinja2
{% if version -%}
## [{{ version | trim_start_matches(pat="v") }}] - {{ timestamp | date(format="%Y-%m-%d") }}
{%- else %}
## [unreleased]
{% endif %}
```

### 关键模板逻辑

#### 版本标题
```jinja2
{% if version -%}
## [{{ version | trim_start_matches(pat="v") }}] - {{ timestamp | date(format="%Y-%m-%d") }}
{%- else %}
## [unreleased]
{% endif %}
```
- 移除版本号前缀的 `v`
- 格式化日期为 `YYYY-MM-DD`

#### 提交分组
```jinja2
{%- for group, commits in commits | group_by(attribute="group") %}
### {{ group | striptags | trim }}

{% for commit in commits %}
- {% if commit.scope %}*({{ commit.scope }})* {% endif %}
  {% if commit.breaking %}[**breaking**] {% endif %}
  {{ commit.message | upper_first }}
{% endfor %}
{%- endfor -%}
```

### 输出示例
```markdown
# Changelog

You can install any of these versions: `npm install -g @openai/codex@<version>`

## [0.101.0] - 2026-03-15

### 🚀 Features

- *(tui)* Add new chat composer
- *(core)* [**breaking**] Change API response format

### 🪲 Bug Fixes

- *(exec)* Fix sandbox permission issue

<!-- generated - do not edit -->
```

## 关键代码路径与文件引用

### 相关文件
| 文件 | 说明 |
|------|------|
| `/home/sansha/Github/codex/cliff.toml` | 本文件 |
| `/home/sansha/Github/codex/CHANGELOG.md` | 生成的变更日志 |
| `/home/sansha/Github/codex/.github/workflows/rust-release.yml` | 发布工作流 |

### CI/CD 集成
```yaml
# 在发布工作流中使用
- name: Generate Changelog
  run: |
    cargo install git-cliff
    git-cliff --output CHANGELOG.md
```

### 与发布流程的关系
```
发布流程
├── 创建标签 (rust-v0.101.0)
├── 运行 git-cliff 生成 CHANGELOG
├── 创建 GitHub Release
│   └── 使用生成的发布说明
└── 发布到 npm
```

## 依赖与外部交互

### 外部工具
```
cliff.toml
├── git-cliff CLI ───────────────┐
│   ├── Git 命令                 │
│   ├── Tera 模板引擎            ├── 变更日志生成
│   └── 正则表达式引擎           │
└── Git 仓库 ────────────────────┘
    └── 提交历史
```

### 依赖约定
- **Conventional Commits**: 提交消息需遵循 `type(scope): message` 格式
- **Git 标签**: 版本标签格式为 `rust-v*.*.*`

### 与其他工具的关系
| 工具 | 关系 | 说明 |
|------|------|------|
| git-cliff | 主工具 | 解析配置并生成变更日志 |
| cargo-release | 可选 | 自动化版本发布 |
| semantic-release | 替代方案 | 另一种发布自动化工具 |

## 风险、边界与改进建议

### 风险

#### 1. 提交消息质量依赖
```
风险: 提交消息不规范导致分类错误
示例: "fix bug" → 被分到 "💼 Other" 而非 "🪲 Bug Fixes"
```

#### 2. 破坏性变更标记
```
当前: 依赖提交消息中的 breaking 标记
风险: 开发者可能忘记标记 [**breaking**]
```

#### 3. 范围 (scope) 不一致
```
示例:
- feat(tui): ...
- feat(TUI): ...
- feat(tui-app): ...
结果: 被当作不同的 scope 显示
```

### 边界

#### 功能边界
- 仅处理已合并到主分支的提交
- 不支持自动生成升级指南
- 不验证提交消息的准确性
- 不支持多语言变更日志

#### 技术边界
- 依赖 Git 历史完整性
- 不支持自定义过滤器（除正则外）
- 模板语法限于 Tera 支持的功能

### 改进建议

#### 1. 添加更多提交类型
```toml
[git]
commit_parsers = [
  { message = "^feat", group = "<!-- 0 -->🚀 Features" },
  { message = "^fix",  group = "<!-- 1 -->🪲 Bug Fixes" },
  { message = "^docs", group = "<!-- 2 -->📚 Documentation" },
  { message = "^style", group = "<!-- 3 -->💎 Style" },
  { message = "^refactor", group = "<!-- 4 -->♻️ Refactor" },
  { message = "^perf", group = "<!-- 5 -->⚡ Performance" },
  { message = "^test", group = "<!-- 6 -->🧪 Tests" },
  { message = "^chore", group = "<!-- 7 -->🔧 Chores" },
  { message = "^bump", group = "<!-- 8 -->🛳️ Release" },
  { message = "^security", group = "<!-- 9 -->🔒 Security" },
  { message = ".*",  group = "<!-- 10 -->💼 Other" },
]
```

#### 2. 添加提交链接
```toml
[changelog]
body = """
{% for commit in commits %}
- {% if commit.scope %}*({{ commit.scope }})* {% endif %}
  {% if commit.breaking %}[**breaking**] {% endif %}
  {{ commit.message | upper_first }}
  ([{{ commit.id | truncate(length=7, end="") }}](https://github.com/openai/codex/commit/{{ commit.id }}))
{% endfor %}
"""
```

#### 3. 添加作者信息
```toml
[changelog]
body = """
{% for commit in commits %}
- {{ commit.message }} — @{{ commit.author.name }}
{% endfor %}
"""
```

#### 4. 添加过滤规则
```toml
[git]
# 过滤掉特定提交
commit_parsers = [
  { message = "^chore\(release\)", skip = true },
  { message = "^Merge pull request", skip = true },
  { message = "^ci\(bot\)", skip = true },
  # ...
]
```

#### 5. 添加预提交钩子
```bash
#!/bin/bash
# .git/hooks/commit-msg

# 验证提交消息符合 Conventional Commits
if ! grep -qE "^(feat|fix|docs|style|refactor|perf|test|chore|bump)(\(.+\))?: .+" "$1"; then
    echo "Error: Commit message does not follow Conventional Commits"
    echo "Format: type(scope): message"
    exit 1
fi
```

#### 6. CI 集成验证
```yaml
# .github/workflows/lint-commits.yml
name: Lint Commits
on: [pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Check Conventional Commits
        uses: wagoid/commitlint-github-action@v5
```

#### 7. 自动化发布流程
```yaml
# 建议的发布工作流增强
- name: Generate Changelog
  run: |
    git-cliff --tag "rust-v${VERSION}" --output CHANGELOG.md
    
- name: Commit Changelog
  run: |
    git add CHANGELOG.md
    git commit -m "chore(release): update changelog for v${VERSION}"
    git push
```

#### 8. 多格式输出
```toml
[changelog]
# 同时生成 Markdown 和 JSON
postprocessors = [
  { pattern = '.*', replace = '' }  # 可以配置多个输出
]
```

### 与现有流程的整合建议

#### 当前流程
```
1. 开发者提交代码
2. 创建 GitHub Release（手动输入发布说明）
3. 发布到 npm
```

#### 建议流程
```
1. 开发者提交代码（遵循 Conventional Commits）
2. 运行 git-cliff 生成 CHANGELOG
3. 创建 GitHub Release（使用生成的说明）
4. 发布到 npm
```

### 配置验证
```bash
#!/bin/bash
# 验证 cliff.toml 配置

echo "Testing cliff.toml configuration..."

# 检查语法
git-cliff --config cliff.toml --dry-run

# 预览输出
git-cliff --config cliff.toml --unreleased

echo "Configuration test complete"
```
