# debug-codex.sh 深度研究文档

## 场景与职责

`debug-codex.sh` 是一个开发调试辅助脚本，用于在 VSCode 中调试 Codex CLI 时自动构建并运行最新的 Rust 代码。该脚本主要服务于以下场景：

1. **VSCode 调试集成**：作为 `chatgpt.cliExecutable` 配置，支持在 IDE 中直接调试
2. **开发迭代加速**：自动编译最新代码，无需手动构建
3. **一致性保证**：确保调试时始终使用最新版本的代码

### 使用场景

开发者可以在 VSCode 的 `settings.json` 中配置：

```json
{
  "chatgpt.cliExecutable": "/Users/<USERNAME>/code/codex/scripts/debug-codex.sh"
}
```

配置后，每次在 VSCode 中调用 Codex 扩展时，都会自动：
1. 进入 `codex-rs` 目录
2. 使用 Cargo 编译并运行 `codex` 二进制文件
3. 将所有参数传递给 `codex`

## 功能点目的

### 1. 自动构建
- **目的**：确保调试时使用的是最新代码
- **实现**：`cargo run` 会自动检测变更并重新编译

### 2. 参数透传
- **目的**：支持所有 `codex` 命令行参数
- **实现**：`"$@"` 将所有参数原样传递

### 3. 静默模式
- **目的**：减少构建输出干扰
- **实现**：`--quiet` 标志抑制 Cargo 的编译信息

## 具体技术实现

### 脚本实现

```bash
#!/bin/bash

# Set "chatgpt.cliExecutable": "/Users/<USERNAME>/code/codex/scripts/debug-codex.sh" 
# in VSCode settings to always get the latest codex-rs binary when debugging Codex Extension.

set -euo pipefail

CODEX_RS_DIR=$(realpath "$(dirname "$0")/../codex-rs")
(cd "$CODEX_RS_DIR" && cargo run --quiet --bin codex -- "$@")
```

### 关键特性分析

| 特性 | 实现 | 说明 |
|------|------|------|
| 严格错误处理 | `set -euo pipefail` | 任何错误立即退出 |
| 路径解析 | `realpath` + `dirname` | 获取脚本所在目录的绝对路径 |
| 目录切换 | `(cd ... && ...)` | 子 shell 中切换，不影响父环境 |
| 静默构建 | `--quiet` | 仅显示程序输出，隐藏编译信息 |
| 参数透传 | `"$@"` | 保留参数边界，正确处理含空格参数 |

### 执行流程

```
脚本被调用（带参数）
├── 解析脚本所在目录
├── 计算 codex-rs 目录路径（../codex-rs）
├── 进入 codex-rs 目录
├── 执行 cargo run --quiet --bin codex -- "$@"
│   ├── Cargo 检查依赖和变更
│   ├── 如有必要，重新编译
│   └── 运行 codex 二进制文件
└── 返回 codex 的退出码
```

## 关键代码路径与文件引用

### 脚本本身
- **路径**：`scripts/debug-codex.sh` (10 行)
- **Shebang**：`#!/bin/bash`

### 被调用的项目
- **Rust 项目目录**：`codex-rs/`
- **目标二进制**：`codex`（由 `codex-rs/cli` 提供）

### 相关配置
- **VSCode 设置**：用户级别的 `settings.json`
- **Cargo 配置**：`codex-rs/Cargo.toml`

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 | 版本要求 |
|------|------|----------|
| bash | 脚本执行 | 支持 `set -euo pipefail` |
| realpath | 路径解析 | GNU coreutils 或兼容实现 |
| cargo | Rust 构建 | 项目所需的 Rust 工具链 |

### 执行环境
- 需要在项目仓库中运行
- 需要 Rust 工具链已安装
- 需要 `codex-rs` 目录存在且包含有效的 Cargo 项目

### 性能特征
- **首次运行**：需要完整编译，可能耗时数分钟
- **后续运行**：仅编译变更，通常几秒到几十秒
- **无变更**：几乎立即启动

## 风险、边界与改进建议

### 已知风险

1. **编译失败阻断**
   - 风险：如果代码编译失败，调试无法开始
   - 缓解：确保提交前代码可编译

2. **Cargo 锁竞争**
   - 风险：多个进程同时运行可能导致 Cargo 锁竞争
   - 场景：同时打开多个 VSCode 窗口调试

3. **资源消耗**
   - 风险：编译过程消耗大量 CPU 和内存
   - 影响：在资源受限的机器上可能影响调试体验

4. **路径依赖**
   - 风险：脚本依赖于相对于自身的目录结构
   - 场景：如果移动脚本位置会失效

### 边界情况

1. **脚本被移动**
   - 行为：路径解析可能失败或指向错误位置
   - 建议：保持脚本在 `scripts/` 目录

2. **codex-rs 不存在**
   - 行为：`cd` 命令失败，脚本退出
   - 错误信息：`No such file or directory`

3. **参数包含特殊字符**
   - 处理：`"$@"` 正确处理含空格和引号的参数

4. **Cargo 未安装**
   - 行为：命令未找到，脚本退出

### 改进建议

1. **添加存在性检查**
   ```bash
   CODEX_RS_DIR=$(realpath "$(dirname "$0")/../codex-rs")
   if [[ ! -d "$CODEX_RS_DIR" ]]; then
       echo "Error: codex-rs directory not found at $CODEX_RS_DIR" >&2
       exit 1
   fi
   ```

2. **支持发布模式**
   ```bash
   # 建议添加环境变量控制
   CARGO_PROFILE="${CARGO_PROFILE:-dev}"
   cargo run --profile "$CARGO_PROFILE" --quiet --bin codex -- "$@"
   ```

3. **添加超时控制**
   ```bash
   # 防止编译卡住
   timeout 300 cargo run --quiet --bin codex -- "$@" || {
       echo "Compilation timed out or failed" >&2
       exit 1
   }
   ```

4. **缓存编译结果提示**
   ```bash
   # 添加编译时间统计
   echo "[debug-codex] Building codex..." >&2
   start_time=$(date +%s)
   (cd "$CODEX_RS_DIR" && cargo run --quiet --bin codex -- "$@")
   end_time=$(date +%s)
   echo "[debug-codex] Completed in $((end_time - start_time))s" >&2
   ```

5. **支持不同目标二进制**
   ```bash
   # 通过环境变量或参数选择二进制
   BINARY="${CODEX_BINARY:-codex}"
   cargo run --quiet --bin "$BINARY" -- "$@"
   ```

6. **添加帮助信息**
   ```bash
   if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
       echo "Usage: debug-codex.sh [ARGS...]"
       echo ""
       echo "Builds and runs the codex binary from codex-rs."
       echo "All arguments are passed through to codex."
       exit 0
   fi
   ```

### 替代方案

1. **预构建二进制**
   ```bash
   # 使用已编译的二进制而非每次构建
   CODEX_BIN="${CODEX_BIN:-./target/debug/codex}"
   exec "$CODEX_BIN" "$@"
   ```

2. **Watch 模式**
   ```bash
   # 使用 cargo-watch 持续编译
   cargo watch -x 'run --bin codex' -- "$@"
   ```

3. **VSCode 任务集成**
   ```json
   // .vscode/tasks.json
   {
       "label": "build-codex",
       "type": "shell",
       "command": "cargo build --bin codex",
       "options": { "cwd": "${workspaceFolder}/codex-rs" }
   }
   ```
