# codex-rs/core/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统中 `codex-rs/core` crate 的构建定义文件。它定义了如何将 Rust 源代码编译成库、二进制文件和测试目标，同时管理编译时数据、测试数据和外部依赖的集成。

该文件位于 `codex-rs/core` 目录，是整个 core crate 的构建入口点，负责：
- 定义 Rust 库目标 (`codex-core`)
- 导出编译时所需的模板文件
- 配置模型可用性测试固件
- 设置编译数据、测试数据和额外二进制文件依赖

## 功能点目的

### 1. 模板文件导出
```bazel
exports_files([
    "templates/collaboration_mode/default.md",
    "templates/collaboration_mode/plan.md",
], visibility = ["//visibility:public"])
```
- **目的**：将协作模式模板文件导出为公共可见的编译数据
- **用途**：用于 Plan/Default 协作模式的系统提示模板
- **消费者**：TUI 和 app-server 在初始化时加载这些模板

### 2. 模型可用性测试固件
```bazel
filegroup(
    name = "model_availability_nux_fixtures",
    srcs = ["models.json", "tests/cli_responses_fixture.sse"],
    visibility = ["//visibility:public"],
)
```
- **目的**：为模型可用性 NUX（New User Experience）测试提供数据文件
- **包含**：
  - `models.json`：模型定义文件
  - `tests/cli_responses_fixture.sse`：SSE 响应测试固件

### 3. Core Crate 构建定义

使用 `codex_rust_crate` 宏（定义在 `//:defs.bzl`）来定义核心库：

| 属性 | 值 | 说明 |
|------|-----|------|
| `name` | `"core"` | Bazel 目标名 |
| `crate_name` | `"codex_core"` | Rust crate 名 |
| `compile_data` | 全局 glob + node-version.txt | 编译时数据文件 |
| `rustc_env` | `CARGO_MANIFEST_DIR=codex-rs/core` | Askama 模板路径解析 |
| `integration_compile_data_extra` | apply_patch 指令、models.json、prompt.md | 集成测试额外编译数据 |
| `test_data_extra` | config.schema.json、snapshots、AGENTS.md | 测试运行时数据 |
| `test_tags` | `["no-sandbox"]` | 禁用沙箱以支持某些测试 |
| `extra_binaries` | linux-sandbox、test_stdio_server 等 | 测试所需的外部二进制 |

## 具体技术实现

### 编译数据 (compile_data)

```bazel
compile_data = glob(
    include = ["**"],
    exclude = ["**/* *", "BUILD.bazel", "Cargo.toml"],
    allow_empty = True,
) + ["//codex-rs:node-version.txt"]
```

- 包含 `src/` 下所有文件（排除含空格的文件名）
- 排除 BUILD.bazel 和 Cargo.toml 避免冲突
- 附加 node-version.txt 用于版本追踪

### Askama 模板路径处理

```bazel
rustc_env = {
    "CARGO_MANIFEST_DIR": "codex-rs/core",
}
```

- Askama 模板引擎使用 `CARGO_MANIFEST_DIR` 解析模板路径
- 在 Bazel 沙箱环境中，需要显式设置以确保路径正确

### 集成测试数据

```bazel
integration_compile_data_extra = [
    "//codex-rs/apply-patch:apply_patch_tool_instructions.md",
    "models.json",
    "prompt.md",
]
```

- `apply_patch_tool_instructions.md`：apply_patch 工具的系统指令
- `models.json`：模型配置
- `prompt.md`：默认提示模板

### 测试数据

```bazel
test_data_extra = [
    "config.schema.json",
] + glob(["src/**/snapshots/**"]) + ["//:AGENTS.md"]
```

- `config.schema.json`：配置 JSON Schema，用于验证
- `snapshots/**`：insta 快照测试数据
- `AGENTS.md`：仓库根标记文件（某些集成测试依赖此文件作为 repo root marker）

### 额外二进制依赖

```bazel
extra_binaries = [
    "//codex-rs/linux-sandbox:codex-linux-sandbox",
    "//codex-rs/rmcp-client:test_stdio_server",
    "//codex-rs/rmcp-client:test_streamable_http_server",
    "//codex-rs/cli:codex",
]
```

- `codex-linux-sandbox`：Linux seccomp 沙箱二进制
- `test_stdio_server`：MCP stdio 传输测试服务器
- `test_streamable_http_server`：MCP HTTP 传输测试服务器
- `codex`：CLI 二进制，用于端到端测试

## 关键代码路径与文件引用

### 上游依赖

| 文件 | 关系 | 说明 |
|------|------|------|
| `//:defs.bzl` | 导入 | `codex_rust_crate` 宏定义 |
| `//codex-rs:node-version.txt` | 编译数据 | Node.js 版本信息 |
| `//codex-rs/apply-patch:apply_patch_tool_instructions.md` | 集成编译数据 | apply_patch 工具指令 |
| `//codex-rs/linux-sandbox:codex-linux-sandbox` | 测试二进制 | Linux 沙箱 |
| `//codex-rs/rmcp-client:test_stdio_server` | 测试二进制 | MCP 测试服务器 |
| `//codex-rs/cli:codex` | 测试二进制 | CLI 工具 |

### 下游消费者

| 目标 | 关系 | 说明 |
|------|------|------|
| `//codex-rs/cli` | 依赖 | CLI crate 依赖 core |
| `//codex-rs/tui` | 依赖 | TUI crate 依赖 core |
| `//codex-rs/tui_app_server` | 依赖 | App Server 依赖 core |

### 内部文件引用

| 文件 | 用途 |
|------|------|
| `templates/collaboration_mode/default.md` | Default 协作模式模板 |
| `templates/collaboration_mode/plan.md` | Plan 协作模式模板 |
| `models.json` | 模型定义 |
| `prompt.md` | 默认提示词 |
| `config.schema.json` | 配置验证 Schema |
| `tests/cli_responses_fixture.sse` | SSE 测试固件 |

## 依赖与外部交互

### Bazel 规则依赖

1. **`codex_rust_crate` 宏**：来自 `//:defs.bzl`，封装了：
   - `rust_library`：创建 Rust 库
   - `rust_test`：创建单元测试和集成测试
   - `cargo_build_script`：处理 build.rs
   - `workspace_root_test`：确保测试在正确目录运行

2. **`filegroup` 规则**：用于分组测试固件文件

3. **`exports_files` 规则**：导出模板文件供其他目标使用

### Cargo 兼容性

- 通过 `CARGO_MANIFEST_DIR` 环境变量保持与 Cargo 的路径兼容性
- 使用 `CARGO_BIN_EXE_*` 模式暴露测试二进制路径
- 支持 `INSTA_WORKSPACE_ROOT` 和 `INSTA_SNAPSHOT_PATH` 用于快照测试

## 风险、边界与改进建议

### 已知风险

1. **TODO 注释中的测试依赖问题**（第 50-58 行）：
   - 某些集成测试依赖 `AGENTS.md` 作为 repo root marker
   - 在远程执行环境中工作目录不同，需要显式添加测试数据
   - 建议：更新测试使其不依赖文件系统标记

2. **no-sandbox 测试标签**：
   - 测试被标记为 `"no-sandbox"`，可能影响 Bazel 的缓存和远程执行
   - 原因：某些测试需要访问外部环境

### 边界情况

1. **文件路径含空格**：
   - `compile_data` glob 排除了 `"**/* *"` 模式的文件
   - 确保没有空格的文件名进入编译数据

2. **平台特定依赖**：
   - Linux 沙箱二进制仅在 Linux 平台构建
   - Windows 沙箱通过不同机制处理

### 改进建议

1. **移除 AGENTS.md 依赖**：
   ```bazel
   # 当前
   test_data_extra = ["//:AGENTS.md"]
   
   # 建议：重构测试使其使用内存中的标记或环境变量
   ```

2. **细化 compile_data**：
   - 当前使用 `glob(["**"])` 可能包含不必要的文件
   - 建议：明确列出需要的模板和数据文件

3. **文档化 extra_binaries 用途**：
   - 添加注释说明每个二进制在测试中的具体用途

4. **考虑拆分测试固件**：
   - `model_availability_nux_fixtures` 可以进一步细分
   - 使测试只依赖真正需要的数据子集
