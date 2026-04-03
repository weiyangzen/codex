# blob-size-policy.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流负责在 Pull Request 中检查新增或修改的文件大小，防止大文件意外提交到 Git 仓库。这是 Git 仓库健康维护的重要机制，避免仓库体积膨胀和克隆性能下降。

## 功能点目的

1. **防止大文件提交**：阻止超过 512KB 的文件被合并
2. **白名单机制**：允许特定的大文件（如图片、锁文件）通过配置豁免
3. **PR 范围检测**：仅检查 PR 中实际变更的文件，而非整个仓库
4. **二进制文件识别**：区分二进制文件和文本文件，在报告中标注

## 具体技术实现

### 触发条件
```yaml
on:
  pull_request: {}
```
- 仅在 Pull Request 时触发
- 不监听 push 事件，因为 main 分支的变更已通过 PR 检查

### 权限配置
```yaml
jobs:
  check:
    name: Blob size policy
    runs-on: ubuntu-24.04
```
- 使用最小权限（未显式声明 permissions，使用默认只读）
- 在 Ubuntu 24.04 上运行

### Git 范围检测
```yaml
- name: Determine PR comparison range
  id: range
  shell: bash
  run: |
    set -euo pipefail
    echo "base=$(git rev-parse HEAD^1)" >> "$GITHUB_OUTPUT"
    echo "head=$(git rev-parse HEAD^2)" >> "$GITHUB_OUTPUT"
```
- 使用 `HEAD^1` 和 `HEAD^2` 获取 PR 的 base 和 head commit
- 这是 GitHub Actions 中检测 PR 变更范围的标准方法
- 需要 `fetch-depth: 0` 确保完整历史可用

### 文件大小检查
```yaml
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
- 调用 Python 脚本 `scripts/check_blob_size.py`
- 参数：
  - `--base` / `--head`：比较的 commit 范围
  - `--max-bytes`：大小限制 512000 字节（500KB）
  - `--allowlist`：白名单文件路径

## 关键代码路径与文件引用

### 工作流文件
| 文件 | 作用 |
|------|------|
| `.github/workflows/blob-size-policy.yml` | 本工作流定义 |
| `scripts/check_blob_size.py` | 文件大小检查脚本 |
| `.github/blob-size-allowlist.txt` | 大文件白名单 |

### 检查脚本详解 (scripts/check_blob_size.py)

#### 核心数据结构
```python
@dataclass(frozen=True)
class ChangedBlob:
    path: str
    size_bytes: int
    is_allowlisted: bool
    is_binary: bool
```

#### 关键函数
1. **获取变更文件列表**：
```python
def get_changed_paths(base: str, head: str) -> list[str]:
    output = run_git(
        "diff", "--name-only", "--diff-filter=AM", "--no-renames", "-z",
        base, head,
    )
    return [path for path in output.split("\0") if path]
```
- `--diff-filter=AM`：仅包含 Added (A) 和 Modified (M) 的文件
- `--no-renames`：不检测重命名，将重命名视为删除+添加
- `-z`：使用 NUL 分隔符处理特殊文件名

2. **检测二进制文件**：
```python
def is_binary_change(base: str, head: str, path: str) -> bool:
    output = run_git("diff", "--numstat", ...).strip()
    added, deleted, _ = output.split("\t", 2)
    return added == "-" and deleted == "-"
```
- Git 的 `--numstat` 对二进制文件显示 `-` 而非行数

3. **获取文件大小**：
```python
def blob_size(commit: str, path: str) -> int:
    return int(run_git("cat-file", "-s", f"{commit}:{path}").strip())
```
- 使用 `git cat-file -s` 获取 blob 对象大小

4. **白名单加载**：
```python
def load_allowlist(path: Path) -> set[str]:
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if line:
            allowlist.add(line)
```
- 支持 `#` 注释
- 精确路径匹配（非通配符）

### 白名单文件 (.github/blob-size-allowlist.txt)
```
.github/codex-cli-splash.png
MODULE.bazel.lock
codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json
codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json
codex-rs/tui/tests/fixtures/oss-story.jsonl
codex-rs/tui_app_server/tests/fixtures/oss-story.jsonl
```
- 6 个文件被豁免
- 包括：启动画面图片、Bazel 锁文件、JSON Schema、测试 fixtures

## 依赖与外部交互

### 外部依赖
- Python 3（Ubuntu 24.04 预装）
- Git（actions/checkout 提供）

### 被依赖方
- PR 合并流程：作为必需检查阻止大文件合并

## 风险、边界与改进建议

### 风险
1. **白名单膨胀**：当前白名单有 6 个文件，需要定期审查防止滥用
2. **误报**：某些合法的大文件（如数据文件）可能需要频繁添加白名单
3. **性能**：大仓库中 `git diff` 和 `git cat-file` 可能影响性能

### 边界条件
- 仅检查 Added 和 Modified 文件，不检查 Deleted 文件
- 重命名文件会被视为新文件检查
- 白名单使用精确匹配，不支持通配符

### 改进建议
1. **白名单通配符支持**：添加 `*.png`、`*.lock` 等模式匹配
2. **大小分层限制**：对不同类型文件设置不同限制（如图片 1MB，代码 100KB）
3. **自动压缩建议**：对图片等可压缩文件，建议用户使用压缩版本
4. **PR 注释**：将检查结果以 PR 评论形式展示，而非仅控制台输出
5. **历史清理**：定期运行 `git-filter-repo` 清理已存在的大文件
