# BUILD.bazel 研究文档

## 场景与职责

`codex-rs/tui/BUILD.bazel` 是 Codex TUI (Terminal User Interface) 模块的 Bazel 构建配置文件。该文件定义了如何将 Rust 源代码编译为可发布的 crate，并管理测试数据、集成测试依赖和额外二进制文件的配置。

该模块是 Codex CLI 的核心交互界面，提供基于终端的聊天界面、命令输入、历史记录管理等功能。

## 功能点目的

### 1. Crate 定义与命名
- **Bazel Target 名称**: `tui`
- **Rust Crate 名称**: `codex_tui`（遵循 `codex-` 前缀约定）
- 使用 `codex_rust_crate` 宏统一处理 Rust crate 的构建配置

### 2. 编译数据管理 (`compile_data`)
```bazel
compile_data = glob(
    include = ["**"],
    exclude = [
        "**/* *",
        "BUILD.bazel",
        "Cargo.toml",
    ],
    allow_empty = True,
)
```
- 包含所有源文件和资源文件作为编译时数据
- 排除带空格的文件名和构建配置文件
- 支持空目录（`allow_empty = True`）

### 3. 测试数据配置
- **`test_data_extra`**: 包含快照测试数据和模型可用性 fixtures
  - `src/**/snapshots/**`: 308+ 个 insta 快照测试文件
  - `//codex-rs/core:model_availability_nux_fixtures`: 核心模型可用性测试数据
  
- **`integration_compile_data_extra`**: 集成测试专用编译数据
  - `src/test_backend.rs`: 测试后端实现

### 4. 额外二进制依赖 (`extra_binaries`)
- `//codex-rs/cli:codex`: 依赖 CLI 模块的 codex 二进制文件
- 用于集成测试中调用完整的 codex 命令

## 具体技术实现

### 构建宏调用链
```
codex_rust_crate (defs.bzl)
├── rust_library/rust_proc_macro: 创建库目标
├── rust_test: 创建单元测试目标
├── workspace_root_test: 包装测试以支持工作区根目录
└── rust_binary: 为每个二进制文件创建目标
```

### 关键构建流程
1. **源码收集**: 通过 `glob(["src/**/*.rs"])` 自动收集所有 Rust 源文件
2. **依赖解析**: 从 `@crates` 外部仓库解析 Cargo 依赖
3. **特性标志**: 通过 `crate_features` 传递 Cargo 特性
4. **测试包装**: 使用 `workspace_root_test` 规则确保测试在正确的目录下运行

### 路径重映射配置
在 `defs.bzl` 中配置了路径重映射，使 Bazel 构建的测试能够与 Cargo 兼容：
```bazel
rustc_flags = [
    "--remap-path-prefix=../codex-rs=",
    "--remap-path-prefix=codex-rs=",
]
```

## 关键代码路径与文件引用

### 直接关联文件
| 文件 | 用途 |
|------|------|
| `defs.bzl` | 定义 `codex_rust_crate` 宏 |
| `Cargo.toml` | Cargo 包配置和依赖定义 |
| `src/lib.rs` | 库入口点 |
| `src/main.rs` | 二进制入口点 |

### 测试相关文件
| 路径模式 | 说明 |
|----------|------|
| `src/**/snapshots/*.snap` | insta 快照测试文件 |
| `src/test_backend.rs` | 测试后端实现 |
| `tests/*.rs` | 集成测试文件 |

### 被调用方
- `codex-rs/cli/BUILD.bazel`: 依赖 TUI 库
- `codex-rs/tui_app_server`: 并行实现，共享部分逻辑

## 依赖与外部交互

### Bazel 外部依赖
- `@crates//:defs.bzl`: Cargo 依赖解析
- `@rules_rust//rust:defs.bzl`: Rust 规则定义
- `@rules_platform//platform_data:defs.bzl`: 平台数据规则

### Cargo 依赖（通过 workspace 管理）
主要依赖类别：
- **UI 框架**: `ratatui` (终端 UI)、`crossterm` (跨平台终端控制)
- **异步运行时**: `tokio` (多线程 RT)
- **序列化**: `serde`, `serde_json`
- **协议**: `codex-protocol`, `codex-app-server-protocol`
- **核心功能**: `codex-core`, `codex-client`, `codex-backend-client`

### 平台特定依赖
```toml
[target.'cfg(not(target_os = "linux"))'.dependencies]
cpal = { version = "0.15", optional = true }      # 音频输入
hound = { version = "3.5", optional = true }      # 音频格式

[target.'cfg(not(target_os = "android"))'.dependencies]
arboard = { workspace = true }                     # 剪贴板支持
```

## 风险、边界与改进建议

### 风险点
1. **平台兼容性**: 
   - Linux 平台缺少语音输入支持（`voice-input` 特性被排除）
   - Android 平台缺少剪贴板支持
   - Windows 平台有特殊的沙箱降级处理

2. **测试数据大小**: 
   - 308+ 个快照文件可能导致测试运行时间增加
   - 快照文件变更频繁，需要定期清理

3. **依赖循环风险**:
   - `extra_binaries` 依赖 `//codex-rs/cli:codex`
   - CLI 可能反向依赖 TUI 库，需要避免循环

### 边界条件
1. **空目录处理**: `allow_empty = True` 允许空源目录，但可能导致空库目标
2. **文件名限制**: 排除带空格的文件名，可能影响某些文件系统
3. **测试环境**: `INSTA_WORKSPACE_ROOT` 和 `INSTA_SNAPSHOT_PATH` 需要正确设置

### 改进建议
1. **构建优化**:
   - 考虑将快照测试数据分离到单独的 Bazel 目标
   - 使用 `bazel query` 分析依赖图，优化构建顺序

2. **平台支持**:
   - 评估 Linux 语音输入的可行性（ALSA/PulseAudio 支持）
   - 统一跨平台剪贴板实现

3. **测试改进**:
   - 添加测试数据大小检查，防止快照文件膨胀
   - 考虑使用远程缓存加速快照测试

4. **文档完善**:
   - 添加 `compile_data` 的详细说明文档
   - 记录平台特定依赖的决策原因
