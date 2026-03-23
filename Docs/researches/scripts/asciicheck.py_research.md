# asciicheck.py 深度研究文档

## 场景与职责

`asciicheck.py` 是一个代码质量检查工具脚本，用于确保项目中的文本文件仅包含 ASCII 字符和明确允许的 Unicode 码点。该脚本主要服务于以下场景：

1. **CI/CD 质量门禁**：在 GitHub Actions 工作流中运行，防止包含非预期 Unicode 字符的文件进入主分支
2. **文档一致性保障**：确保 Markdown 文件（如 README.md）的字符集符合规范，避免因特殊字符导致的渲染问题
3. **正则表达式兼容性**：防止非 ASCII 字符（如不间断空格 U+00A0）导致正则匹配失败
4. **GitHub 锚点一致性**：确保 Markdown 标题锚点在不同渲染环境下保持一致

### 在 CI 中的位置

```yaml
# .github/workflows/ci.yml
- name: Ensure root README.md contains only ASCII and certain Unicode code points
  run: ./scripts/asciicheck.py README.md
- name: Ensure codex-cli/README.md contains only ASCII and certain Unicode code points
  run: ./scripts/asciicheck.py codex-cli/README.md
```

## 功能点目的

### 1. 非 ASCII 字符检测
- **目的**：识别文件中所有非 ASCII 字符（码点超出 0x20-0x7E 范围）
- **例外处理**：允许特定白名单码点（如 ✨ U+2728 sparkles）
- **输出格式**：精确报告问题字符的位置（行号、列号）和 Unicode 码点

### 2. 自动修复功能（--fix 模式）
- **目的**：自动将常见的非 ASCII 字符替换为 ASCII 等效字符
- **使用场景**：开发者本地运行，快速修复复制粘贴引入的特殊字符
- **替换映射**：
  - 不间断空格 (U+00A0) → 普通空格
  - 各种连字符/破折号 (U+2011, U+2013, U+2014) → ASCII 连字符
  - 智能引号 (U+2018, U+2019, U+201C, U+201D) → ASCII 引号
  - 省略号 (U+2026) → 三个点
  - 窄不间断空格 (U+202F) → 普通空格

### 3. UTF-8 解码错误处理
- **目的**：处理非 UTF-8 编码的文件
- **行为**：报告解码错误的位置（字节偏移、行号、列号）

## 具体技术实现

### 核心数据结构

```python
# 字符替换映射表：Unicode 码点 → ASCII 替换字符串
substitutions: dict[int, str] = {
    0x00A0: " ",   # non-breaking space
    0x2011: "-",   # non-breaking hyphen
    0x2013: "-",   # en dash
    0x2014: "-",   # em dash
    0x2018: "'",   # left single quote
    0x2019: "'",   # right single quote
    0x201C: '"',   # left double quote
    0x201D: '"',   # right double quote
    0x2026: "...", # ellipsis
    0x202F: " ",   # narrow non-breaking space
}

# 允许的 Unicode 码点白名单
allowed_unicode_codepoints = {
    0x2728,  # sparkles
}
```

### 关键流程

#### 1. 主入口流程 (`main`)
```
解析命令行参数 (--fix, files)
├── 遍历每个文件
│   └── 调用 lint_utf8_ascii(path, fix=args.fix)
│       ├── 以二进制模式读取文件
│       ├── 尝试 UTF-8 解码
│       ├── 逐行逐字符检查
│       ├── 收集违规字符
│       └── 如 --fix 且存在违规，执行替换
└── 返回退出码 (0=无错误, 1=有错误)
```

#### 2. 字符检查逻辑 (`lint_utf8_ascii`)
```python
for lineno, line in enumerate(text.splitlines(keepends=True), 1):
    for colno, char in enumerate(line, 1):
        codepoint = ord(char)
        if char == "\n":
            continue
        if not (0x20 <= codepoint <= 0x7E) and codepoint not in allowed_unicode_codepoints:
            errors.append((lineno, colno, char, codepoint))
```

#### 3. 自动修复逻辑
```python
if errors and fix:
    new_contents = ""
    for char in text:
        codepoint = ord(char)
        if codepoint in substitutions:
            new_contents += substitutions[codepoint]
        else:
            new_contents += char
    # 写回文件
```

### 命令行接口

```bash
# 检查模式（默认）
./scripts/asciicheck.py README.md
./scripts/asciicheck.py codex-cli/README.md

# 修复模式
./scripts/asciicheck.py --fix README.md

# 多文件检查
./scripts/asciicheck.py file1.md file2.md file3.md
```

## 关键代码路径与文件引用

### 脚本本身
- **路径**：`scripts/asciicheck.py` (127 行)
- **Shebang**：`#!/usr/bin/env python3`

### 调用方
- **CI 工作流**：`.github/workflows/ci.yml`
  - 行 55-56：检查根目录 README.md
  - 行 60-61：检查 codex-cli/README.md

### 被检查的目标文件
- `README.md` - 项目主文档
- `codex-cli/README.md` - CLI 包文档

### 相关脚本
- `scripts/readme_toc.py` - 同时检查 README 的目录结构，与 asciicheck 在同一 CI 阶段运行

## 依赖与外部交互

### Python 标准库
| 模块 | 用途 |
|------|------|
| `argparse` | 命令行参数解析 |
| `sys` | 退出码和 stderr 输出 |
| `pathlib.Path` | 跨平台路径处理 |

### 无外部依赖
- 纯 Python 标准库实现
- 无需 pip 安装任何包

### 执行环境
- 需要 Python 3.x
- 需要文件读取权限
- `--fix` 模式需要文件写入权限

## 风险、边界与改进建议

### 已知风险

1. **修复不完全**
   - 问题：自动修复只能处理预定义的替换映射表中的字符
   - 影响：不在映射表中的非 ASCII 字符无法自动修复，需手动处理
   - 缓解：脚本会报告所有违规字符，开发者需手动处理未覆盖的字符

2. **误报风险**
   - 问题：某些合法的非 ASCII 字符可能被误判
   - 缓解：通过 `allowed_unicode_codepoints` 白名单机制控制

3. **文件编码问题**
   - 问题：非 UTF-8 编码的文件会导致解码错误
   - 行为：脚本会报告解码错误位置，但不会崩溃

### 边界情况

1. **空文件**：正常处理，返回 0
2. **二进制文件**：会以 UTF-8 解码失败处理，报告解码错误
3. **大文件**：逐行读取，内存占用可控
4. **无写权限（--fix 模式）**：会抛出异常，退出码非 0

### 改进建议

1. **扩展替换映射**
   ```python
   # 建议添加更多常见特殊字符
   0x00AD: "",    # soft hyphen (通常不可见)
   0x200B: "",    # zero-width space
   0xFEFF: "",    # BOM (Byte Order Mark)
   ```

2. **配置文件支持**
   - 建议：支持 `.asciicheckrc` 配置文件，允许项目自定义白名单
   - 场景：不同子项目可能有不同的字符需求

3. **批量修复报告**
   - 建议：修复后生成详细报告，显示修改前后的对比
   - 实现：可集成 `difflib` 生成统一差异格式

4. **与 pre-commit 集成**
   - 建议：提供 pre-commit hook 配置
   - 收益：在提交前自动检查，减少 CI 失败

5. **性能优化**
   - 当前：逐字符检查，时间复杂度 O(n)
   - 建议：对超大文件可使用正则表达式预过滤

### 测试建议

```python
# 建议添加的测试用例
def test_non_breaking_space():
    """测试不间断空格检测和修复"""
    pass

def test_smart_quotes():
    """测试智能引号替换"""
    pass

def test_allowed_codepoints():
    """测试白名单码点不被标记"""
    pass

def test_utf8_decode_error():
    """测试非 UTF-8 文件处理"""
    pass
```
