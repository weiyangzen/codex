# .github/blob-size-allowlist.txt 研究文档

## 场景与职责

`.github/blob-size-allowlist.txt` 是 Codex 项目中用于**大文件体积管控**的配置文件，属于 CI/CD 质量门禁体系的一部分。其核心职责包括：

1. **豁免特定大文件**：允许某些 intentionally large 的文件（如图片、lock 文件、测试 fixture、schema bundle）超出默认大小限制
2. **防止仓库膨胀**：通过明确的白名单机制，避免意外提交大文件导致 git 仓库体积失控
3. **支持自动化检查**：为 `blob-size-policy.yml` GitHub Actions 工作流提供豁免清单

该文件体现了项目对仓库健康的主动管理策略——既允许必要的大文件存在，又通过显式声明的方式确保每个大文件都经过审慎评估。

---

## 功能点目的

### 1. 大文件检测与拦截

项目通过 GitHub Actions 工作流 `.github/workflows/blob-size-policy.yml` 在每次 Pull Request 时自动检测变更文件的大小：

- **默认阈值**：512,000 bytes (约 500 KiB)
- **检测范围**：所有新增 (A) 和修改 (M) 的文件
- **豁免机制**：通过白名单文件声明允许的大文件路径

### 2. 白名单管理策略

白名单采用**精确路径匹配**（非 glob 模式），路径相对于仓库根目录。文件格式支持注释（以 `#` 开头）。

### 3. 当前豁免的文件类别

| 文件路径 | 大小 | 类别 | 豁免原因 |
|---------|------|------|---------|
| `.github/codex-cli-splash.png` | 838,131 bytes | 图片资源 | CLI 启动画面， intentionally checked-in asset |
| `MODULE.bazel.lock` | 1,181,488 bytes | Lock 文件 | Bazel 依赖锁定文件，由工具自动生成/更新 |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json` | 380,836 bytes | Schema Bundle | v1 API 完整 JSON Schema，供客户端消费 |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | 303,850 bytes | Schema Bundle | v2 API 完整 JSON Schema，供客户端消费 |
| `codex-rs/tui/tests/fixtures/oss-story.jsonl` | 838,122 bytes | 测试 Fixture | TUI 集成测试用的会话录制数据 |
| `codex-rs/tui_app_server/tests/fixtures/oss-story.jsonl` | 838,122 bytes | 测试 Fixture | TUI App Server 集成测试用的会话录制数据 |

---

## 具体技术实现

### 核心检测脚本

**文件**: `scripts/check_blob_size.py` (193 行 Python)

#### 关键数据结构

```python
@dataclass(frozen=True)
class ChangedBlob:
    path: str           # 文件路径（相对于仓库根目录）
    size_bytes: int     # 文件大小（字节）
    is_allowlisted: bool # 是否在白名单中
    is_binary: bool     # 是否为二进制文件
```

#### 白名单加载逻辑

```python
def load_allowlist(path: Path) -> set[str]:
    allowlist: set[str] = set()
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].strip()  # 支持行内注释
        if line:
            allowlist.add(line)
    return allowlist
```

#### 文件变更检测

```python
def get_changed_paths(base: str, head: str) -> list[str]:
    output = run_git(
        "diff",
        "--name-only",
        "--diff-filter=AM",    # 仅检测新增和修改
        "--no-renames",        # 不处理重命名
        "-z",                  # 使用 null 分隔符处理特殊字符
        base,
        head,
    )
    return [path for path in output.split("\0") if path]
```

#### 二进制检测

```python
def is_binary_change(base: str, head: str, path: str) -> bool:
    output = run_git(
        "diff", "--numstat", "--diff-filter=AM", "--no-renames",
        base, head, "--", path
    ).strip()
    if not output:
        return False
    added, deleted, _ = output.split("\t", 2)
    return added == "-" and deleted == "-"  # git 对二进制文件显示 "-"
```

#### Blob 大小获取

```python
def blob_size(commit: str, path: str) -> int:
    return int(run_git("cat-file", "-s", f"{commit}:{path}").strip())
```

### GitHub Actions 工作流集成

**文件**: `.github/workflows/blob-size-policy.yml`

```yaml
name: blob-size-policy

on:
  pull_request: {}

jobs:
  check:
    name: Blob size policy
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0  # 需要完整历史进行 diff

      - name: Determine PR comparison range
        id: range
        run: |
          echo "base=$(git rev-parse HEAD^1)" >> "$GITHUB_OUTPUT"
          echo "head=$(git rev-parse HEAD^2)" >> "$GITHUB_OUTPUT"

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

### 报告输出

脚本会生成详细的检查报告，包括：

1. **控制台输出**：列出每个变更文件的大小、类型（binary/non-binary）和状态（ok/allowlisted/blocked）
2. **GitHub Step Summary**：Markdown 格式的表格，显示在 PR 的 Checks 标签页中

示例输出格式：
```
Checked 3 changed file(s) against the 512000-byte limit.
- foo.png: 1048576 bytes (1024.0 KiB) [binary, blocked]
- bar.json: 380836 bytes (371.9 KiB) [non-binary, allowlisted]
- baz.rs: 1024 bytes (1.0 KiB) [non-binary, ok]
```

---

## 关键代码路径与文件引用

### 配置层

| 文件 | 作用 |
|-----|------|
| `.github/blob-size-allowlist.txt` | 白名单配置文件（本研究对象） |

### 执行层

| 文件 | 作用 |
|-----|------|
| `.github/workflows/blob-size-policy.yml` | GitHub Actions 工作流定义 |
| `scripts/check_blob_size.py` | 核心检测脚本 |

### 被豁免的大文件

| 文件 | 大小 | 生成/更新方式 |
|-----|------|--------------|
| `.github/codex-cli-splash.png` | 838 KiB | 手动设计资源 |
| `MODULE.bazel.lock` | 1,154 KiB | `just bazel-lock-update` |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json` | 372 KiB | `just write-app-server-schema` |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | 297 KiB | `just write-app-server-schema` |
| `codex-rs/tui/tests/fixtures/oss-story.jsonl` | 819 KiB | 测试录制数据 |
| `codex-rs/tui_app_server/tests/fixtures/oss-story.jsonl` | 819 KiB | 测试录制数据 |

### Schema 生成相关代码

| 文件 | 作用 |
|-----|------|
| `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs` | Schema 生成 CLI 入口 |
| `codex-rs/app-server-protocol/src/schema_fixtures.rs` | Schema 文件读写、规范化逻辑 |
| `codex-rs/app-server-protocol/src/export.rs` | TypeScript/JSON Schema 导出核心 |

---

## 依赖与外部交互

### 内部依赖

1. **Git 命令**：脚本依赖 `git diff`, `git cat-file` 等命令获取变更文件信息和 blob 大小
2. **Python 标准库**：仅使用 `argparse`, `dataclasses`, `pathlib`, `subprocess` 等标准库，无第三方依赖
3. **GitHub Actions 环境**：依赖 `GITHUB_STEP_SUMMARY` 环境变量写入检查结果摘要

### 外部交互

```
┌─────────────────────────────────────────────────────────────────┐
│                      Pull Request Created                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              GitHub Actions: blob-size-policy.yml                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ git rev-parse   │  │ git diff        │  │ check_blob_size │ │
│  │ HEAD^1 / HEAD^2 │→ │ --name-only     │→ │ .py             │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                              │                                   │
│                              ▼                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  读取 .github/blob-size-allowlist.txt                       │ │
│  │  对比变更文件大小与阈值 (512KB)                              │ │
│  │  生成检查报告                                               │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
    ┌─────────────────┐             ┌─────────────────┐
    │  所有文件合规    │             │  存在违规文件    │
    │  Check Pass     │             │  Check Fail     │
    └─────────────────┘             └─────────────────┘
```

### 豁免文件的生成链

#### MODULE.bazel.lock
```
开发者修改 codex-rs/Cargo.toml
        ↓
just bazel-lock-update
        ↓
bazel mod deps --lockfile_mode=update
        ↓
更新 MODULE.bazel.lock (1.1MB+)
```

#### Schema JSON Bundle
```
修改 codex-rs/app-server-protocol/src/protocol/v*.rs
        ↓
just write-app-server-schema
        ↓
cargo run -p codex-app-server-protocol --bin write_schema_fixtures
        ↓
更新 codex_app_server_protocol.schemas.json (372KB)
更新 codex_app_server_protocol.v2.schemas.json (297KB)
```

---

## 风险、边界与改进建议

### 当前风险

1. **白名单膨胀风险**
   - 当前已有 6 个豁免文件，总大小约 4.3 MB
   - 如果缺乏审慎控制，白名单可能逐渐膨胀，失去管控意义

2. **重复 Fixture 数据**
   - `oss-story.jsonl` 在两个目录中各有一份（tui 和 tui_app_server）
   - 内容相同（均为 838,122 bytes），造成存储冗余

3. **Schema Bundle 体积**
   - v1 + v2 两个 schema 文件合计约 669 KB
   - 随着 API 演进，schema 文件可能持续增长

4. **无通配符支持**
   - 白名单使用精确路径匹配，新增同类文件需手动更新配置
   - 例如：新增 `codex_app_server_protocol.v3.schemas.json` 需要显式添加到白名单

### 边界情况

1. **文件删除**：`--diff-filter=AM` 不检测删除 (D)，删除大文件不会触发检查
2. **重命名文件**：`--no-renames` 参数确保重命名被检测为删除+新增，不会绕过检查
3. **特殊字符**：使用 `-z` 参数和 `\0` 分隔符正确处理文件名中的特殊字符
4. **二进制检测**：依赖 git 的启发式算法（`--numstat` 显示 "-"），可能误判某些文本文件

### 改进建议

#### 短期（维护性）

1. **去重 oss-story.jsonl**
   ```bash
   # 建议：将 fixture 移至共享目录，通过符号链接或测试配置引用
   codex-rs/tests/fixtures/oss-story.jsonl
   codex-rs/tui/tests/fixtures/oss-story.jsonl → ../../tests/fixtures/oss-story.jsonl
   codex-rs/tui_app_server/tests/fixtures/oss-story.jsonl → ../../tests/fixtures/oss-story.jsonl
   ```

2. **添加文件大小注释**
   ```text
   # .github/blob-size-allowlist.txt
   # 格式: <path>  # <size> <reason>
   
   .github/codex-cli-splash.png  # 838KB CLI splash image
   MODULE.bazel.lock             # 1.1MB Bazel lockfile (auto-generated)
   ```

3. **添加 CI 检查防止白名单引用不存在的文件**
   ```python
   # 在 check_blob_size.py 中添加验证
   for path in allowlist:
       if not os.path.exists(path):
           print(f"Warning: Allowlisted file does not exist: {path}")
   ```

#### 中期（功能性）

4. **支持目录级豁免**
   ```text
   # 允许特定目录下的所有文件（谨慎使用）
   codex-rs/app-server-protocol/schema/json/*.json
   ```

5. **分级阈值策略**
   ```python
   # 不同文件类型使用不同阈值
   THRESHOLDS = {
       "*.png": 1 * 1024 * 1024,    # 图片: 1MB
       "*.lock": 2 * 1024 * 1024,   # Lock 文件: 2MB
       "*.json": 500 * 1024,        # JSON: 500KB
       "default": 512 * 1024,       # 默认: 512KB
   }
   ```

6. **Schema Bundle 拆分**
   - 将 monolithic schema 拆分为按模块/命名空间组织的多个小文件
   - 客户端按需加载，减少单文件体积

#### 长期（架构性）

7. **LFS 迁移评估**
   - 对于真正的大文件（如图片、测试数据），评估使用 Git LFS
   - 权衡：LFS 的复杂性 vs 仓库克隆速度

8. **自动化白名单审查**
   - 定期生成报告：白名单文件的实际大小、最后修改时间、引用次数
   - 识别"僵尸"豁免（文件已删除或大幅缩小但仍留在白名单）

9. **与 justfile 集成**
   ```just
   # 添加验证命令
   check-blob-allowlist:
       python3 scripts/check_blob_size.py \
           --base origin/main \
           --head HEAD \
           --max-bytes 512000 \
           --allowlist .github/blob-size-allowlist.txt
   ```

---

## 附录：相关命令速查

```bash
# 本地运行大文件检查（对比当前分支与 main）
python3 scripts/check_blob_size.py \
    --base origin/main \
    --head HEAD \
    --max-bytes 512000 \
    --allowlist .github/blob-size-allowlist.txt

# 查看白名单文件实际大小
wc -c $(grep -v '^#' .github/blob-size-allowlist.txt | grep -v '^$')

# 更新 Bazel lockfile（会修改 MODULE.bazel.lock）
just bazel-lock-update

# 更新 Schema fixtures（会修改 codex_app_server_protocol.*.schemas.json）
just write-app-server-schema
```

---

*文档生成时间: 2026-03-22*
*基于仓库状态: commit 3月19日*
