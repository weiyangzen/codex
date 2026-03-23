# readme_toc.py 深度研究文档

## 场景与职责

`readme_toc.py` 是一个 Markdown 目录（Table of Contents, ToC）管理工具，用于验证和自动更新 README 文件的目录结构。该脚本主要服务于以下场景：

1. **文档一致性维护**：确保 README 的目录与实际标题结构保持一致
2. **CI/CD 质量门禁**：在持续集成中检查目录是否过时
3. **自动化文档管理**：支持一键修复目录结构
4. **多文件支持**：可处理任意 Markdown 文件，不限于 README.md

### 在 CI 中的位置

```yaml
# .github/workflows/ci.yml
- name: Check root README ToC
  run: python3 scripts/readme_toc.py README.md
- name: Check codex-cli/README ToC
  run: python3 scripts/readme_toc.py codex-cli/README.md
```

### 与 asciicheck 的协作

`readme_toc.py` 和 `asciicheck.py` 通常在同一 CI 阶段运行，共同确保文档质量：
- `asciicheck.py`：确保字符集合规
- `readme_toc.py`：确保目录结构正确

## 功能点目的

### 1. 目录生成
- **目的**：从 Markdown 标题自动生成目录
- **支持级别**：`##` 到 `######`（H2 到 H6）
- **排除范围**：代码块内的标题不纳入目录

### 2. 目录验证
- **目的**：检查现有目录是否与生成结果一致
- **验证范围**：`<!-- Begin ToC -->` 和 `<!-- End ToC -->` 标记之间的内容
- **失败处理**：显示统一差异（unified diff）帮助定位问题

### 3. 自动修复
- **目的**：一键更新过时的目录
- **触发方式**：`--fix` 命令行参数
- **保留内容**：标记外的所有内容保持不变

### 4. 锚点生成
- **目的**：生成与 GitHub 兼容的标题锚点
- **处理规则**：
  - 转换为小写
  - 替换特殊 Unicode 字符（不间断空格、各种连字符）
  - 移除标点符号
  - 空格替换为连字符

## 具体技术实现

### 核心数据结构

```python
# 目录标记
BEGIN_TOC: str = "<!-- Begin ToC -->"
END_TOC: str = "<!-- End ToC -->"

# 标题信息元组：(级别, 文本)
headings: list[tuple[int, str]] = []

# 生成的目录行
# "- [标题文本](#锚点)"
# "  - [子标题](#子标题锚点)"
```

### 关键流程

#### 1. 目录生成流程
```
读取文件内容
├── 按行分割
├── 遍历每行：
│   ├── 检测代码块标记（```）
│   ├── 跳过代码块内的内容
│   └── 匹配标题正则：^(#{2,6})\s+(.*)$
├── 提取标题级别和文本
└── 生成目录行：
    ├── 缩进："  " * (level - 2)
    ├── 链接文本：[text]
    └── 锚点：(#slug)
```

#### 2. 锚点生成逻辑
```python
def generate_slug(text: str) -> str:
    slug = text.lower()
    # 标准化特殊字符
    slug = slug.replace("\u00a0", " ")  # 不间断空格
    slug = slug.replace("\u2011", "-").replace("\u2013", "-").replace("\u2014", "-")
    # 移除标点
    slug = re.sub(r"[^0-9a-z\s-]", "", slug)
    # 空格转连字符
    slug = slug.strip().replace(" ", "-")
    return slug
```

#### 3. 验证流程
```
定位标记
├── 查找 BEGIN_TOC 索引
├── 查找 END_TOC 索引
├── 提取当前目录内容
├── 生成期望目录（排除现有目录部分）
├── 比较当前 vs 期望
└── 结果：
    ├── 一致：返回 0
    └── 不一致：
        ├── 显示 diff
        └── 返回 1（或 --fix 时更新文件）
```

### 代码块处理

```python
in_code = False
for line in lines:
    if line.strip().startswith("```"):
        in_code = not in_code
        continue
    if in_code:
        continue  # 跳过代码块内的标题
    # 处理标题...
```

### 统一差异输出

```python
diff = difflib.unified_diff(
    current,           # 现有目录行列表
    expected,          # 生成目录行列表
    fromfile="existing ToC",
    tofile="generated ToC",
    lineterm="",
)
```

## 关键代码路径与文件引用

### 脚本本身
- **路径**：`scripts/readme_toc.py` (120 行)
- **Shebang**：`#!/usr/bin/env python3`

### 调用方
- **CI 工作流**：`.github/workflows/ci.yml`
  - 行 57-58：检查根目录 README.md
  - 行 62-63：检查 codex-cli/README.md

### 目标文件
- `README.md` - 项目主文档
- `codex-cli/README.md` - CLI 包文档

### 相关脚本
- `scripts/asciicheck.py` - 同时检查 README 的字符集合规性

## 依赖与外部交互

### Python 标准库
| 模块 | 用途 |
|------|------|
| `argparse` | 命令行参数解析 |
| `sys` | 退出码和 stderr 输出 |
| `re` | 正则表达式匹配标题 |
| `difflib` | 生成统一差异格式 |
| `pathlib.Path` | 跨平台路径处理 |

### 无外部依赖
- 纯 Python 标准库实现
- 无需 pip 安装任何包

### 文件格式约定

#### 目录标记
```markdown
<!-- Begin ToC -->
- [标题一](#标题一)
- [标题二](#标题二)
  - [子标题](#子标题)
<!-- End ToC -->
```

#### 标题格式
```markdown
## H2 标题
### H3 标题
#### H4 标题
##### H5 标题
###### H6 标题
```

## 风险、边界与改进建议

### 已知风险

1. **锚点不一致风险**
   - 风险：生成的锚点可能与 GitHub 实际生成的锚点不一致
   - 场景：复杂的 Unicode 字符、特殊标点
   - 缓解：与 `asciicheck.py` 共享字符处理逻辑

2. **标记缺失处理**
   - 行为：如果没有找到 ToC 标记，静默跳过（返回 0）
   - 风险：可能掩盖应该存在目录的文件
   - 设计意图：允许某些文件无目录

3. **重复标题处理**
   - 风险：相同标题会产生相同锚点
   - GitHub 行为：自动添加后缀（如 `-1`, `-2`）
   - 当前：未处理此情况

### 边界情况

1. **无标记文件**
   - 输出：`Note: Skipping ToC check; no markers found in {path}.`
   - 退出码：0（不视为错误）

2. **空文件**
   - 行为：无标题可提取，生成空目录
   - 结果：如果标记存在，目录部分为空

3. **嵌套代码块**
   - 处理：正确跟踪代码块状态
   - 注意：不支持缩进代码块（仅围栏式）

4. **标记顺序错误**
   - 行为：`BEGIN_TOC` 必须在 `END_TOC` 之前
   - 风险：如果顺序颠倒，可能产生意外结果

5. **HTML 注释冲突**
   - 风险：如果标题包含 `<!-- Begin ToC -->` 字样
   - 概率：极低

### 改进建议

1. **支持更多标题样式**
   ```python
   # 当前仅支持 ATX 风格（# 开头）
   # 建议添加 Setext 风格支持
   # 标题
   # =====
   ```

2. **重复标题锚点去重**
   ```python
   slug_count: dict[str, int] = {}
   def generate_unique_slug(text: str) -> str:
       base_slug = generate_slug(text)
       count = slug_count.get(base_slug, 0)
       slug_count[base_slug] = count + 1
       return f"{base_slug}-{count}" if count > 0 else base_slug
   ```

3. **添加 H1 支持选项**
   ```python
   parser.add_argument("--include-h1", action="store_true",
                       help="Include H1 headings in ToC")
   ```

4. **支持目录深度限制**
   ```python
   parser.add_argument("--max-depth", type=int, default=6,
                       help="Maximum heading level to include")
   ```

5. **验证锚点有效性**
   ```python
   # 检查生成的锚点是否实际存在
   def validate_anchors(content: str, toc_lines: list[str]) -> list[str]:
       # 提取所有实际标题的锚点
       # 对比目录中的锚点
       # 返回无效锚点列表
   ```

6. **支持自定义标记**
   ```python
   parser.add_argument("--begin-marker", default="<!-- Begin ToC -->")
   parser.add_argument("--end-marker", default="<!-- End ToC -->")
   ```

7. **添加统计信息**
   ```python
   # 在修复模式下输出统计
   print(f"Updated ToC in {readme_path}:")
   print(f"  - Headings: {len(headings)}")
   print(f"  - Max depth: {max(level for level, _ in headings)}")
   ```

8. **与 asciicheck 集成**
   ```python
   # 共享 Unicode 字符处理逻辑
   from asciicheck import normalize_unicode
   # 确保锚点生成和字符检查使用相同的规则
   ```

### 测试建议

```python
# 单元测试场景
def test_heading_extraction():
    """测试标题提取"""
    content = "## Title\n### Subtitle"
    headings = extract_headings(content)
    assert headings == [(2, "Title"), (3, "Subtitle")]

def test_code_block_skip():
    """测试代码块内标题跳过"""
    content = "## Real\n```\n## In Code\n```"
    headings = extract_headings(content)
    assert headings == [(2, "Real")]

def test_slug_generation():
    """测试锚点生成"""
    assert generate_slug("Hello World") == "hello-world"
    assert generate_slug("Café") == "caf"
    assert generate_slug("A & B") == "a--b"

def test_toc_update():
    """测试目录更新"""
    # 创建临时文件测试 --fix 功能
    pass
```

### 与 GitHub 锚点算法的对比

| 场景 | 本脚本 | GitHub |
|------|--------|--------|
| 基础文本 | `hello-world` | `hello-world` |
| 大写 | 转小写 | 转小写 |
| 空格 | 转连字符 | 转连字符 |
| 标点 | 移除 | 移除 |
| 重复标题 | 相同锚点 | 添加 `-1`, `-2` 后缀 |
| Unicode | 部分支持 | 更完善的处理 |

建议定期验证生成的锚点与 GitHub 实际行为的一致性。
