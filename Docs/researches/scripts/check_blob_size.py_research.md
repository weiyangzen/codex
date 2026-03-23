# check_blob_size.py 深度研究文档

## 场景与职责

`check_blob_size.py` 是一个 Git 仓库 Blob 大小检查工具，用于在 CI 中监控和限制提交到仓库的文件大小。该脚本主要服务于以下场景：

1. **防止仓库膨胀**：阻止意外提交大文件，保持仓库克隆速度
2. **PR 大小审查**：在代码审查阶段自动标记超大文件变更
3. **二进制文件管理**：区分文本和二进制文件，应用不同的策略
4. **合规性检查**：确保文件大小符合项目策略

### 在 CI 中的位置

```yaml
# .github/workflows/blob-size-policy.yml
- name: Check changed blob sizes
  env:
    BASE_SHA: ${{ steps.range.outputs.base }}
    HEAD_SHA: ${{ steps.range.outputs.head }}
  run: |
    python3 scripts/check_blob_size.py \
      --base "$BASE_SHA" \
      --head "$HEAD_SHA" \
      --max-bytes 512000 \
      --allowlist .github/blob-size-allowlist.txt
```

## 功能点目的

### 1. 变更文件检测
- **目的**：识别 PR 中新增或修改的文件
- **Git 命令**：`git diff --name-only --diff-filter=AM --no-renames -z`
- **范围**：仅检查 Added (A) 和 Modified (M) 的文件，排除删除和重命名

### 2. Blob 大小计算
- **目的**：获取文件在 Git 对象库中的实际大小
- **Git 命令**：`git cat-file -s <commit>:<path>`
- **意义**：反映文件在仓库中的实际存储占用

### 3. 二进制文件检测
- **目的**：区分文本文件和二进制文件
- **Git 命令**：`git diff --numstat` 的输出分析
- **判断逻辑**：如果 added 和 deleted 都显示为 "-"，则为二进制文件

### 4. 白名单机制
- **目的**：允许特定大文件存在（如图片、锁文件等）
- **配置**：`.github/blob-size-allowlist.txt`
- **格式**：每行一个路径，支持 `#` 注释

### 5. GitHub Actions 集成
- **目的**：生成可视化的步骤摘要
- **输出**：Markdown 格式的表格，显示每个文件的状态

## 具体技术实现

### 核心数据结构

```python
@dataclass(frozen=True)
class ChangedBlob:
    path: str           # 文件路径
    size_bytes: int     # 文件大小（字节）
    is_allowlisted: bool # 是否在白名单中
    is_binary: bool     # 是否为二进制文件
```

### 关键流程

```
解析命令行参数 (--base, --head, --max-bytes, --allowlist)
├── 加载白名单文件
├── 获取变更文件列表 (git diff --name-only)
├── 对每个变更文件：
│   ├── 计算 blob 大小 (git cat-file -s)
│   ├── 检测是否为二进制 (git diff --numstat)
│   └── 检查是否在白名单中
├── 识别违规文件（大小 > max-bytes 且不在白名单）
├── 生成 GitHub 步骤摘要
└── 返回退出码 (0=通过, 1=有违规)
```

### Git 命令详解

#### 1. 获取变更文件列表
```python
git diff \
    --name-only      # 仅输出文件名
    --diff-filter=AM # 仅 Added 和 Modified
    --no-renames     # 不检测重命名
    -z               # 使用 NUL 分隔符（处理特殊文件名）
    base             # 基准提交
    head             # 目标提交
```

#### 2. 检测二进制文件
```python
git diff \
    --numstat        # 输出添加/删除行数统计
    --diff-filter=AM
    --no-renames
    base head -- path

# 输出格式：
# "-\t-\tfilename"  # 二进制文件（无法统计行数）
# "10\t5\tfile"     # 文本文件（10 行添加，5 行删除）
```

#### 3. 获取 Blob 大小
```python
git cat-file -s "{commit}:{path}"
# 返回：对象的字节大小
```

### 白名单文件格式

```
# .github/blob-size-allowlist.txt
# 路径是相对于仓库根目录的精确匹配

.github/codex-cli-splash.png
MODULE.bazel.lock
codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json
codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json
codex-rs/tui/tests/fixtures/oss-story.jsonl
codex-rs/tui_app_server/tests/fixtures/oss-story.jsonl
```

### GitHub 步骤摘要生成

```python
def write_step_summary(max_bytes, blobs, violations):
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    
    # 生成 Markdown 表格
    lines = [
        "## Blob Size Policy",
        "",
        f"Default max: `{max_bytes}` bytes",
        f"Changed files checked: `{len(blobs)}`",
        f"Violations: `{len(violations)}`",
        "",
        "| Path | Kind | Size | Status |",
        "| --- | --- | ---: | --- |",
        # ... 每行一个文件
    ]
```

## 关键代码路径与文件引用

### 脚本本身
- **路径**：`scripts/check_blob_size.py` (193 行)
- **Shebang**：`#!/usr/bin/env python3`

### 调用方
- **CI 工作流**：`.github/workflows/blob-size-policy.yml`

### 配置文件
- **白名单**：`.github/blob-size-allowlist.txt`

### 相关文件
- `MODULE.bazel.lock` - Bazel 锁文件（白名单中的大文件示例）
- `.github/codex-cli-splash.png` - 项目图片资源

## 依赖与外部交互

### Python 标准库
| 模块 | 用途 |
|------|------|
| `argparse` | 命令行参数解析 |
| `subprocess` | 执行 Git 命令 |
| `dataclasses` | `ChangedBlob` 数据类 |
| `pathlib.Path` | 路径处理 |

### 外部依赖
| 依赖 | 用途 |
|------|------|
| Git | 版本控制和文件分析 |

### 环境变量
| 变量 | 用途 |
|------|------|
| `GITHUB_STEP_SUMMARY` | GitHub Actions 步骤摘要文件路径 |

## 风险、边界与改进建议

### 已知风险

1. **Git 历史重写风险**
   - 风险：大文件一旦提交，即使后续删除仍存在于 Git 历史中
   - 缓解：此脚本在 PR 阶段拦截，防止进入主分支

2. **白名单维护负担**
   - 风险：白名单可能过时，包含已删除的文件
   - 缓解：定期审查白名单内容

3. **二进制文件误判**
   - 风险：某些文本文件可能被误判为二进制
   - 场景：包含 NUL 字节或非常长的行的文件

4. **性能问题**
   - 风险：大型 PR（数百个文件）可能导致检查变慢
   - 缓解：Git 命令效率较高，通常可接受

### 边界情况

1. **空 PR（无文件变更）**
   - 行为：输出 "No changed files were detected."，返回 0

2. **文件路径包含特殊字符**
   - 处理：使用 `-z` 标志和 `\0` 分隔符正确处理

3. **子模块变更**
   - 行为：作为普通文件处理，可能产生误导性结果

4. **权限问题**
   - 风险：无法读取 Git 对象时可能失败
   - 缓解：CI 环境通常有完整权限

### 改进建议

1. **添加软限制和硬限制**
   ```python
   # 建议添加警告阈值
   parser.add_argument("--warn-bytes", type=int, help="Warning threshold")
   parser.add_argument("--max-bytes", type=int, required=True, help="Hard limit")
   ```

2. **支持通配符白名单**
   ```python
   # 当前：精确匹配
   # 建议：支持 glob 模式
   if fnmatch.fnmatch(path, pattern):
       return True
   ```

3. **添加文件类型统计**
   ```python
   # 在摘要中添加统计信息
   binary_count = sum(1 for b in blobs if b.is_binary)
   text_count = len(blobs) - binary_count
   ```

4. **集成 Git LFS 检测**
   ```python
   # 建议：检测是否应使用 Git LFS
   def should_use_lfs(path, size):
       return size > 100 * 1024  # 100KB
   ```

5. **支持目录白名单**
   ```python
   # 当前：仅支持具体文件
   # 建议：支持整个目录
   tests/fixtures/*
   ```

6. **添加详细模式**
   ```python
   parser.add_argument("-v", "--verbose", action="store_true")
   # 输出每个文件的详细分析过程
   ```

7. **历史大小趋势**
   ```python
   # 建议：记录大小变化趋势
   # 可集成到 GitHub Actions 的图表输出
   ```

### 测试建议

```python
# 单元测试场景
def test_binary_detection():
    """测试二进制文件检测逻辑"""
    pass

def test_allowlist_loading():
    """测试白名单加载和匹配"""
    pass

def test_size_calculation():
    """测试 blob 大小计算"""
    pass

def test_github_summary():
    """测试 GitHub 摘要生成"""
    pass
```
