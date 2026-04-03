# BUILD.bazel 研究文档

## 场景与职责

此 BUILD.bazel 文件位于 `codex-rs/tui_app_server/` 目录，是 Bazel 构建系统中负责定义 `codex-tui-app-server` crate 构建规则的核心配置文件。该 crate 是 Codex CLI 的终端用户界面（TUI）应用程序服务器，提供基于 Ratatui 的交互式聊天界面。

## 功能点目的

1. **定义 Rust Crate 构建目标**：使用 `defs.bzl` 中定义的 `codex_rust_crate` 宏，标准化创建库、二进制文件和测试目标
2. **管理编译时数据依赖**：通过 `compile_data` 包含模板文件和资源文件
3. **配置测试数据**：定义单元测试和集成测试所需的额外数据文件
4. **指定额外二进制依赖**：声明测试需要调用的其他 crate 的二进制文件

## 具体技术实现

### 构建规则配置

```starlark
codex_rust_crate(
    name = "tui_app_server",
    crate_name = "codex_tui_app_server",
    ...
)
```

关键参数解析：
- `name`: Bazel 目标名称，用于内部引用
- `crate_name`: 实际的 Rust crate 名称（带 `codex_` 前缀，符合 AGENTS.md 规范）

### 编译数据 (`compile_data`)

```starlark
compile_data = glob(
    include = ["**"],
    exclude = [
        "**/* *",           # 排除含空格的文件
        "BUILD.bazel",
        "Cargo.toml",
    ],
    allow_empty = True,
) + [
    "//codex-rs/core:templates/collaboration_mode/default.md",
    "//codex-rs/core:templates/collaboration_mode/plan.md",
]
```

包含的文件类型：
- `tooltips.txt` - 启动时显示的随机提示语
- `prompt_for_init_command.md` - `/init` 命令的默认提示词
- `styles.md` - TUI 样式规范文档
- 协作模式模板（从 core crate 引用）

### 测试数据 (`test_data_extra`)

```starlark
test_data_extra = glob(["src/**/snapshots/**"]) + 
    ["//codex-rs/core:model_availability_nux_fixtures"]
```

- 包含 insta 快照测试的期望输出文件
- 引用 core crate 的模型可用性 NUX 测试夹具

### 集成测试编译数据 (`integration_compile_data_extra`)

```starlark
integration_compile_data_extra = ["src/test_backend.rs"]
```

测试后端实现，用于 vt100 终端模拟测试。

### 额外二进制依赖 (`extra_binaries`)

```starlark
extra_binaries = ["//codex-rs/cli:codex"]
```

集成测试需要调用 `codex` CLI 二进制文件进行端到端测试。

## 关键代码路径与文件引用

### 相关文件

| 文件路径 | 用途 |
|---------|------|
| `defs.bzl` | 定义 `codex_rust_crate` 宏，封装 Bazel Rust 构建规则 |
| `codex-rs/core/templates/collaboration_mode/*.md` | 协作模式默认模板 |
| `src/test_backend.rs` | vt100 测试后端实现 |
| `src/**/snapshots/**` | insta 快照测试文件 |

### 构建输出

- `//codex-rs/tui_app_server:tui_app_server` - 库目标
- `//codex-rs/tui_app_server:codex-tui-app-server` - 主二进制文件
- `//codex-rs/tui_app_server:md-events-app-server` - md-events 辅助工具
- `//codex-rs/tui_app_server:tui_app_server-unit-tests-bin` - 单元测试
- `//codex-rs/tui_app_server:tui_app_server-integration-tests` - 集成测试

## 依赖与外部交互

### 依赖关系

```
tui_app_server (BUILD.bazel)
├── defs.bzl (codex_rust_crate 宏)
├── codex-rs/core (协作模式模板)
├── codex-rs/cli (测试用二进制)
└── @crates (Cargo 依赖解析)
```

### 跨 crate 引用

1. **core crate 模板引用**：`//codex-rs/core:templates/...`
   - 使用 Bazel 标签语法引用其他 crate 的输出
   - 确保模板变更时触发重新构建

2. **cli crate 二进制引用**：`//codex-rs/cli:codex`
   - 用于集成测试中调用 CLI 命令
   - 通过 `CARGO_BIN_EXE_codex` 环境变量暴露

## 风险、边界与改进建议

### 潜在风险

1. **路径变更敏感**：`glob(["**"])` 会捕获所有文件，新增非代码文件可能意外触发重建
2. **跨 crate 依赖**：core crate 模板路径变更需要同步更新此文件
3. **测试数据遗漏**：新增快照测试目录需要手动更新 `test_data_extra`

### 边界条件

1. **空格文件名排除**：`"**/* *"` 排除含空格的文件，确保 Bazel 兼容性
2. **空目录处理**：`allow_empty = True` 允许空匹配，避免构建失败

### 改进建议

1. **更精确的 glob 模式**：
   ```starlark
   # 建议：明确指定资源文件类型
   compile_data = glob([
       "*.md",
       "*.txt",
       "src/**/*.md",
   ])
   ```

2. **文档化跨 crate 依赖**：
   - 在文件顶部添加注释说明 core crate 模板依赖
   - 建立变更通知机制

3. **自动化快照目录发现**：
   - 考虑使用 Bazel aspect 自动发现快照目录
   - 或标准化快照目录命名以便 glob 匹配

4. **构建性能优化**：
   - 评估 `glob(["**"])` 在大型仓库中的性能影响
   - 考虑使用更具体的包含模式
