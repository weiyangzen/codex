# codespell.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流负责运行 `codespell` 工具检查代码库中的拼写错误。拼写检查是代码质量的基础保障，有助于维护专业形象并减少因拼写错误导致的理解困难。

## 功能点目的

1. **拼写错误检测**：自动发现代码和文档中的常见拼写错误
2. **PR 注释集成**：将拼写错误位置标注在 PR 的 Files changed 标签页
3. **可配置忽略**：支持自定义忽略词列表和文件排除模式
4. **轻量快速**：检查速度快，对 CI 时间影响小

## 具体技术实现

### 触发条件
```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

| 触发方式 | 说明 |
|----------|------|
| `push:main` | main 分支推送时检查 |
| `pull_request:main` | 目标为 main 的 PR 时检查 |

### 权限配置
```yaml
permissions:
  contents: read
```
- 最小权限原则：仅需读取代码内容

### 作业配置
```yaml
jobs:
  codespell:
    name: Check for spelling errors
    runs-on: ubuntu-latest
```
- 名称明确："Check for spelling errors"
- 在 Ubuntu 最新版上运行

### 执行步骤
```yaml
steps:
  - name: Checkout
    uses: actions/checkout@v6
  
  - name: Annotate locations with typos
    uses: codespell-project/codespell-problem-matcher@b80729f885d32f78a716c2f107b4db1025001c42 # v1
  
  - name: Codespell
    uses: codespell-project/actions-codespell@8f01853be192eb0f849a5c7d721450e7a467c579 # v2.2
    with:
      ignore_words_file: .codespellignore
```

#### 步骤详解

1. **Checkout**
   - 检出代码

2. **Problem Matcher**
   - Action：`codespell-project/codespell-problem-matcher@v1`
   - 作用：将 codespell 输出转换为 GitHub Annotation
   - 效果：拼写错误会显示在 PR 的 "Files changed" 页面

3. **Codespell 执行**
   - Action：`codespell-project/actions-codespell@v2.2`
   - 配置：`ignore_words_file: .codespellignore`
   - 主配置来自 `.codespellrc`（注释中提到）

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.github/workflows/codespell.yml` | 本工作流定义 |
| `.codespellrc` | codespell 主配置文件 |
| `.codespellignore` | 忽略词列表 |

### 配置文件详解

#### .codespellrc
```ini
[codespell]
skip = .git*,vendor,*-lock.yaml,*.lock,.codespellrc,*test.ts,*.jsonl,frame*.txt,*.snap,*.snap.new,*meriyah.umd.min.js
check-hidden = true
ignore-regex = ^\s*"image/\S+": ".*|\b(afterAll)\b
ignore-words-list = ratatui,ser,iTerm,iterm2,iterm,te,TE
```

| 配置项 | 说明 |
|--------|------|
| `skip` | 跳过的文件/目录模式（逗号分隔） |
| `check-hidden` | 检查隐藏文件（以点开头的文件） |
| `ignore-regex` | 忽略匹配正则表达式的内容 |
| `ignore-words-list` | 忽略的单词列表 |

#### 跳过文件模式分析
- `.git*`：Git 元数据
- `vendor`：第三方依赖目录
- `*-lock.yaml,*.lock`：锁文件
- `*test.ts`：测试文件（可能有故意拼写错误）
- `*.jsonl`：JSON Lines 文件（数据文件）
- `*.snap,*.snap.new`：快照测试文件
- `*meriyah.umd.min.js`：压缩后的 JS 库

#### .codespellignore
```
iTerm
iTerm2
psuedo
te
TE
```

这些是被视为正确拼写的单词：
- `iTerm`/`iTerm2`：macOS 终端模拟器名称
- `psuedo`：可能是 `pseudo` 的变体（需要确认是否故意）
- `te`/`TE`：可能是特定缩写

## 依赖与外部交互

### 外部 Action
1. `codespell-project/codespell-problem-matcher@v1` - 问题匹配器
2. `codespell-project/actions-codespell@v2.2` - codespell 执行

### codespell 工具
- 项目：https://github.com/codespell-project/codespell
- 原理：基于常见拼写错误字典进行匹配
- 特点：只检查已知错误模式，不产生误报

## 风险、边界与改进建议

### 风险
1. **字典限制**：只能检测已知的常见拼写错误
2. **技术术语**：某些技术术语可能被误判
3. **Action 版本**：使用固定 commit hash，需要定期更新
4. **配置分散**：配置分布在 `.codespellrc` 和 `.codespellignore`

### 边界条件
- 仅检查文本文件，自动跳过二进制文件
- 受 `skip` 模式限制，某些文件不会被检查
- 忽略词列表需要手动维护

### 改进建议
1. **定期更新 Action**：检查并更新到最新版本
2. **统一配置**：考虑将所有配置移到 `.codespellrc`
3. **自定义字典**：添加项目特定的术语字典
4. **本地检查**：在 `justfile` 或 `package.json` 中添加本地检查命令
5. **自动修复**：配置自动修复 PR（使用 `--write-changes`）
6. **忽略词审查**：定期审查 `.codespellignore`，移除不再需要的词

### 建议的本地检查配置

添加到 `justfile`：
```justfile
# 检查拼写
codespell:
    codespell

# 自动修复拼写
codespell-fix:
    codespell --write-changes
```

添加到 `package.json` scripts：
```json
{
  "scripts": {
    "spellcheck": "codespell",
    "spellcheck:fix": "codespell --write-changes"
  }
}
```
