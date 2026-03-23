# workspace_root_test_launcher.sh.tpl 研究文档

## 场景与职责

`workspace_root_test_launcher.sh.tpl` 是 Bazel 测试启动器的 **Unix Shell 脚本模板文件**，用于解决在 Bazel 沙箱环境中运行 Rust 测试时的**工作目录定位问题**。该模板与 `defs.bzl` 中的 `workspace_root_test` 规则配合使用，是 Windows 批处理版本 (`workspace_root_test_launcher.bat.tpl`) 的 Unix/Linux/macOS 等价实现。

在 Codex 项目中，此文件服务于以下场景：
- **Insta 快照测试支持**：Insta 快照测试库需要知道仓库根目录以正确定位和管理快照文件
- **Bazel 沙箱兼容性**：Bazel 测试在隔离的 runfiles 目录中执行，需要解析回真实的工作区根目录
- **跨平台测试一致性**：为 Unix 平台（Linux/macOS）提供与 Windows 等价的功能
- **Cargo/Bazel 双构建系统支持**：统一两种构建系统下的测试行为

## 功能点目的

### 1. Runfile 解析函数

```bash
resolve_runfile() {
  local logical_path="$1"
  local workspace_logical_path="${logical_path}"
  if [[ -n "${TEST_WORKSPACE:-}" ]]; then
    workspace_logical_path="${TEST_WORKSPACE}/${logical_path}"
  fi
```

**目的**：
- 定义可复用的 `resolve_runfile` 函数，将逻辑路径解析为实际文件系统路径
- 处理 Bazel 的 `TEST_WORKSPACE` 环境变量前缀
- 使用局部变量避免污染全局命名空间

### 2. 多源路径查找

```bash
  for runfiles_root in "${RUNFILES_DIR:-}" "${TEST_SRCDIR:-}"; do
    if [[ -n "${runfiles_root}" && -e "${runfiles_root}/${logical_path}" ]]; then
      printf '%s\n' "${runfiles_root}/${logical_path}"
      return 0
    fi
    if [[ -n "${runfiles_root}" && -e "${runfiles_root}/${workspace_logical_path}" ]]; then
      printf '%s\n' "${runfiles_root}/${workspace_logical_path}"
      return 0
    fi
  done
```

**目的**：
- 按优先级检查 `RUNFILES_DIR` 和 `TEST_SRCDIR` 环境变量
- 支持两种路径格式：裸逻辑路径和带 workspace 前缀的路径
- 使用 `-e` 测试文件存在性，确保路径有效

### 3. Manifest 文件回退

```bash
  local manifest="${RUNFILES_MANIFEST_FILE:-}"
  if [[ -z "${manifest}" ]]; then
    if [[ -f "$0.runfiles_manifest" ]]; then
      manifest="$0.runfiles_manifest"
    elif [[ -f "$0.exe.runfiles_manifest" ]]; then
      manifest="$0.exe.runfiles_manifest"
    fi
  fi

  if [[ -n "${manifest}" && -f "${manifest}" ]]; then
    local resolved=""
    resolved="$(awk -v key="${logical_path}" '$1 == key { $1 = ""; sub(/^ /, ""); print; exit }' "${manifest}")"
    if [[ -z "${resolved}" ]]; then
      resolved="$(awk -v key="${workspace_logical_path}" '$1 == key { $1 = ""; sub(/^ /, ""); print; exit }' "${manifest}")"
    fi
    if [[ -n "${resolved}" ]]; then
      printf '%s\n' "${resolved}"
      return 0
    fi
  fi
```

**目的**：
- 当 runfiles 目录不可用时，回退到 manifest 文件解析
- 支持多种 manifest 文件命名约定（`$0.runfiles_manifest`, `$0.exe.runfiles_manifest`）
- 使用 `awk` 高效解析 manifest 文件的键值对格式

### 4. 工作区根目录计算

```bash
workspace_root_marker="$(resolve_runfile "__WORKSPACE_ROOT_MARKER__")"
workspace_root="$(dirname "$(dirname "$(dirname "${workspace_root_marker}")")")"
```

**目的**：
- 解析 `repo_root.marker` 文件位置（占位符 `__WORKSPACE_ROOT_MARKER__` 由 Bazel 替换）
- 通过三次 `dirname` 导航计算仓库根目录（marker 位于 `codex-rs/utils/cargo-bin/`）
- 路径：`codex-rs/utils/cargo-bin/repo_root.marker` → `codex-rs/utils/cargo-bin` → `codex-rs/utils` → `codex-rs` → `<workspace_root>`

### 5. 测试执行环境设置

```bash
export INSTA_WORKSPACE_ROOT="${workspace_root}"
cd "${workspace_root}"
exec "${test_bin}" "$@"
```

**目的**：
- 设置 `INSTA_WORKSPACE_ROOT` 环境变量，供 Insta 快照测试库使用
- 切换当前目录到仓库根目录
- 使用 `exec` 替换当前进程执行测试二进制，保留 PID 和信号处理
- 传递所有原始参数 (`$@`) 给测试进程

## 具体技术实现

### Shebang 和选项

```bash
#!/usr/bin/env bash
set -euo pipefail
```

| 选项 | 说明 |
|------|------|
| `#!/usr/bin/env bash` | 使用环境变量查找 bash，提高可移植性 |
| `set -e` | 命令失败时立即退出 |
| `set -u` | 使用未定义变量时报错 |
| `set -o pipefail` | 管道中任一命令失败则整体失败 |

### 模板替换变量

| 占位符 | 替换来源 | 说明 |
|--------|----------|------|
| `__WORKSPACE_ROOT_MARKER__` | `defs.bzl` 中的 `workspace_root_marker.short_path` | `repo_root.marker` 文件的 runfile 路径 |
| `__TEST_BIN__` | `defs.bzl` 中的 `test_bin.short_path` | 实际测试二进制文件的 runfile 路径 |

### 关键 Shell 技术

| 技术 | 用途 |
|------|------|
| `${VAR:-}` | 参数扩展，若未定义则返回空字符串 |
| `[[ -n "${VAR}" ]]` | 测试字符串非空 |
| `[[ -e "${path}" ]]` | 测试路径存在（文件或目录） |
| `[[ -f "${path}" ]]` | 测试路径是文件 |
| `$(command)` | 命令替换 |
| `awk -v key="..."` | 向 awk 传递变量 |
| `sub(/^ /, "")` | awk 函数，删除行首空格 |
| `dirname` | 提取路径的目录部分 |
| `exec` | 替换当前进程 |
| `$@` | 所有位置参数 |

### 路径解析优先级

```
1. RUNFILES_DIR/<logical_path>
2. RUNFILES_DIR/<workspace_logical_path>
3. TEST_SRCDIR/<logical_path>
4. TEST_SRCDIR/<workspace_logical_path>
5. RUNFILES_MANIFEST_FILE 查找
6. $0.runfiles_manifest 查找
7. $0.exe.runfiles_manifest 查找
```

### 目录结构关系

```
<workspace_root>/                    # 计算得到的仓库根目录
├── codex-rs/
│   └── utils/
│       └── cargo-bin/
│           └── repo_root.marker     # __WORKSPACE_ROOT_MARKER__ 指向此处
├── bazel-out/...
│   └── .../test                     # 测试启动器脚本
│   └── .../test.runfiles/           # RUNFILES_DIR
│       ├── __WORKSPACE_ROOT_MARKER__ -> .../repo_root.marker
│       └── __TEST_BIN__ -> .../unit-tests-bin
└── ...
```

## 关键代码路径与文件引用

### 调用方（生成者）

| 文件 | 代码 | 说明 |
|------|------|------|
| `/home/sansha/Github/codex/defs.bzl` | `ctx.actions.expand_template(...)` | 使用此模板生成测试启动器 |
| `/home/sansha/Github/codex/defs.bzl` | `_workspace_root_test_impl` | 实现规则，填充模板变量 |
| `/home/sansha/Github/codex/BUILD.bazel` | `exports_files([...])` | 导出模板文件供规则使用 |

### 配套文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `/home/sansha/Github/codex/workspace_root_test_launcher.bat.tpl` | Windows 对应版本 | 功能等价的批处理脚本模板 |
| `/home/sansha/Github/codex/defs.bzl` | 规则定义 | 定义 `workspace_root_test` 规则 |
| `/home/sansha/Github/codex/codex-rs/utils/cargo-bin/repo_root.marker` | 标记文件 | 用于定位仓库根的空标记文件 |
| `/home/sansha/Github/codex/codex-rs/utils/cargo-bin/src/lib.rs` | 库实现 | 提供 `repo_root()` 函数，逻辑与此模板一致 |

### 使用方（测试目标）

所有使用 `codex_rust_crate` 宏的 crate 都会间接使用此模板：

```
codex-rs/tui/BUILD.bazel → codex_rust_crate → workspace_root_test → 此模板
codex-rs/core/BUILD.bazel → codex_rust_crate → workspace_root_test → 此模板
codex-rs/cli/BUILD.bazel → codex_rust_crate → workspace_root_test → 此模板
... (所有 77 个 BUILD.bazel 文件)
```

## 依赖与外部交互

### Bazel 环境变量依赖

| 环境变量 | 来源 | 用途 |
|----------|------|------|
| `RUNFILES_DIR` | Bazel 测试运行器 | Runfiles 树的根目录 |
| `TEST_SRCDIR` | Bazel 测试运行器 | 测试源文件目录（通常与 RUNFILES_DIR 相同） |
| `TEST_WORKSPACE` | Bazel 测试运行器 | 当前测试的工作区名称 |
| `RUNFILES_MANIFEST_FILE` | Bazel 测试运行器 | Runfiles 清单文件路径 |

### 外部工具依赖

| 工具 | 用途 |
|------|------|
| `bash` | 脚本解释器 |
| `awk` | 文本处理，解析 manifest 文件 |
| `dirname` | 路径操作 |
| `printf` | 格式化输出 |

### 与 Insta 的交互

```bash
export INSTA_WORKSPACE_ROOT="${workspace_root}"
```

- **库**: [Insta](https://insta.rs/) - Rust 快照测试库
- **环境变量**: `INSTA_WORKSPACE_ROOT` 告诉 Insta 在哪里查找和更新 `.snap` 文件
- **行为**: 测试在仓库根目录执行，快照路径相对于根目录解析

### 执行流程

```
Bazel 测试触发
    ↓
生成 workspace_root_test 目标
    ↓
expand_template 填充 .sh.tpl → .sh
    ↓
执行生成的 .sh 文件
    ↓
解析 __WORKSPACE_ROOT_MARKER__ → repo_root.marker 路径
    ↓
解析 __TEST_BIN__ → 测试二进制路径
    ↓
计算 workspace_root = dirname(dirname(dirname(marker)))
    ↓
设置 INSTA_WORKSPACE_ROOT
    ↓
cd ${workspace_root}
    ↓
exec 测试二进制
    ↓
返回测试结果
```

## 风险、边界与改进建议

### 风险点

1. **目录深度硬编码**
   ```bash
   workspace_root="$(dirname "$(dirname "$(dirname "${workspace_root_marker}")")")"
   ```
   - 假设 marker 文件位于 `codex-rs/utils/cargo-bin/repo_root.marker`
   - 若目录结构变更，计算将出错
   - **缓解**: 文档化目录结构约定，添加变更检查

2. **Bash 依赖**
   - 使用 `#!/usr/bin/env bash` 而非 POSIX sh
   - 某些最小化环境（如 Alpine Linux 容器）可能无 bash
   - **缓解**: 评估是否可降级到 POSIX sh 以提高可移植性

3. **Manifest 解析假设**
   - 假设 manifest 文件格式为 `key value`（空格分隔）
   - 若 Bazel 变更格式，解析将失败
   - **缓解**: 使用 Bazel 提供的 runfiles 库（但会增加依赖）

4. **错误信息有限**
   - 失败时仅输出简单错误信息
   - 缺少对排查过程的可视化

### 边界情况

1. **符号链接处理**
   - `dirname` 和 `-e` 测试对符号链接的处理
   - 若 runfiles 包含循环链接可能导致问题

2. **路径中的空格**
   ```bash
   printf '%s\n' "${runfiles_root}/${logical_path}"
   ```
   - 正确引用变量处理含空格的路径
   - 但 `awk` 解析 manifest 时若值含空格可能出错

3. **并发执行**
   - 模板生成的脚本可能在同一目录并发执行
   - 但脚本本身无状态，无并发冲突风险

4. **macOS 兼容性**
   - `awk` 实现可能因系统而异（GNU awk vs BSD awk）
   - 当前用法使用基本功能，兼容性良好

### 改进建议

1. **添加详细日志模式**
   ```bash
   if [[ -n "${RBE_DEBUG:-}" ]]; then
       echo "[DEBUG] Resolving runfile: ${logical_path}" >&2
       echo "[DEBUG] RUNFILES_DIR=${RUNFILES_DIR:-}" >&2
       echo "[DEBUG] TEST_SRCDIR=${TEST_SRCDIR:-}" >&2
   fi
   ```

2. **动态目录深度计算**
   ```bash
   # 替代硬编码的三次 dirname
   workspace_root="${workspace_root_marker}"
   for _ in codex-rs utils cargo-bin; do
       workspace_root="$(dirname "${workspace_root}")"
   done
   ```

3. **增强错误诊断**
   ```bash
   echo "ERROR: Failed to resolve runfile: ${logical_path}" >&2
   echo "  Checked RUNFILES_DIR: ${RUNFILES_DIR:-<not set>}" >&2
   echo "  Checked TEST_SRCDIR: ${TEST_SRCDIR:-<not set>}" >&2
   echo "  Checked manifest: ${manifest:-<not found>}" >&2
   ```

4. **POSIX sh 兼容性**
   - 评估移除 bash 特有功能（如 `[[`）
   - 使用 `[` 和 POSIX 参数扩展
   - 但会失去 `pipefail` 等有用特性

5. **与 Windows 模板对齐**
   - 确保 `.sh.tpl` 和 `.bat.tpl` 的行为完全一致
   - 建立测试矩阵验证跨平台等价性

6. **单元测试**
   - 为 runfile 解析逻辑添加独立测试
   - 使用 mock 环境变量验证各种场景

7. **使用 Bazel Runfiles 库**
   - 考虑使用 Bazel 官方提供的 runfiles 库
   - 提供更可靠的跨平台 runfile 解析
   - 但需要确保库在目标环境中可用
