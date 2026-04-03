# BUILD.bazel 研究文档

## 文件信息

- **文件路径**: `codex-rs/utils/approval-presets/BUILD.bazel`
- **文件大小**: 141 bytes
- **所属 Crate**: `codex-utils-approval-presets`

## 场景与职责

### 1.1 定位与用途

此 BUILD.bazel 文件是 Bazel 构建系统的构建配置，定义了 `codex-utils-approval-presets` crate 的构建规则。该 crate 是 Codex 项目中一个轻量级的工具 crate，专门提供预定义的权限审批策略组合（Approval Presets）。

### 1.2 设计意图

- **单一职责**: 将权限预设逻辑独立成一个可复用的 crate
- **UI 无关性**: 文档明确说明 "Keep this UI-agnostic so it can be reused by both TUI and MCP server"
- **跨平台复用**: 通过独立的 crate 设计，确保 TUI 和 TUI App Server 都能共享相同的预设定义

## 功能点目的

### 2.1 Bazel 构建规则

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "approval-presets",
    crate_name = "codex_utils_approval_presets",
)
```

#### 关键配置项

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `name` | `"approval-presets"` | Bazel 目标名称，用于在构建图中引用 |
| `crate_name` | `"codex_utils_approval_presets"` | Rust crate 名称，遵循 `codex_utils_*` 命名规范 |

### 2.2 与 Cargo.toml 的关系

该 Bazel 配置与 `Cargo.toml` 形成互补：
- **Cargo.toml**: 定义 Rust 包元数据和依赖（Cargo 构建系统）
- **BUILD.bazel**: 定义 Bazel 构建规则和集成点

两者共同确保该 crate 可以在两种构建系统中正常工作。

## 具体技术实现

### 3.1 构建规则分析

`codex_rust_crate` 是项目自定义的 Bazel 宏（定义在 `//:defs.bzl`），它封装了 Rust 构建的常用模式：

```bazel
# 伪代码表示宏可能展开的内容
codex_rust_crate(name, crate_name) → 
    rust_library(
        name = name,
        crate_name = crate_name,
        srcs = glob(["src/**/*.rs"]),
        deps = [...],  # 从 Cargo.toml 解析
        ...
    )
```

### 3.2 依赖传递

该 crate 的依赖通过 `codex_rust_crate` 宏处理：
- 直接依赖：`codex-protocol`（在 Cargo.toml 中声明）
- 间接依赖：`codex-protocol` 依赖的其他 crate

### 3.3 构建输出

构建成功后生成：
- `libcodex_utils_approval_presets.rlib`（Rust 静态库）
- 可被其他 Bazel 目标通过 `@//codex-rs/utils/approval-presets` 引用

## 关键代码路径与文件引用

### 4.1 当前目录文件

| 文件路径 | 类型 | 说明 |
|----------|------|------|
| `Cargo.toml` | 配置文件 | Rust 包管理配置，定义依赖 `codex-protocol` |
| `src/lib.rs` | 源码 | 实现 `ApprovalPreset` 结构体和 `builtin_approval_presets()` 函数 |

### 4.2 被引用位置

| 文件 | 引用方式 | 用途 |
|------|----------|------|
| `codex-rs/tui/Cargo.toml` | `codex-utils-approval-presets = { path = "../utils/approval-presets" }` | TUI 模块依赖 |
| `codex-rs/tui_app_server/Cargo.toml` | `codex-utils-approval-presets = { path = "../utils/approval-presets" }` | TUI App Server 依赖 |

### 4.3 调用链

```
用户点击权限设置
    ↓
ChatWidget::open_permissions_popup()
    ↓
use codex_utils_approval_presets::ApprovalPreset;
use codex_utils_approval_presets::builtin_approval_presets;
    ↓
调用 builtin_approval_presets() 获取权限预设列表
```

## 依赖与外部交互

### 5.1 编译时依赖

```
codex-utils-approval-presets
    ↓
codex-protocol
    ↓
AskForApproval (enum) - 审批策略
SandboxPolicy (enum) - 沙盒策略
```

### 5.2 运行时交互

该 crate 是纯数据结构定义，无运行时交互：
- 无 I/O 操作
- 无网络请求
- 无状态管理
- 仅提供静态数据访问

### 5.3 与 Bazel 工作区的集成

```
workspace_root/
├── MODULE.bazel          # Bazel 模块定义
├── defs.bzl              # 自定义宏（包含 codex_rust_crate）
└── codex-rs/
    └── utils/
        └── approval-presets/
            └── BUILD.bazel   # 本文件
```

## 风险、边界与改进建议

### 6.1 潜在风险

1. **单一职责边界**：该 crate 非常简单（仅 46 行代码），但作为一个独立的 crate 存在，可能增加构建和维护开销
2. **硬编码预设**：`builtin_approval_presets()` 中定义的三种预设（read-only、auto、full-access）是编译时固定的，无法通过配置动态扩展
3. **字符串 ID 硬编码**：预设 ID 使用字符串字面量（如 `"read-only"`），在多处代码中通过字符串匹配查找，存在拼写错误风险

### 6.2 边界情况

1. **空预设列表**：如果 `builtin_approval_presets()` 返回空列表，调用方（如权限弹窗）需要正确处理空列表情况
2. **ID 冲突**：如果未来添加相同 ID 的预设，后定义的会覆盖先定义的（取决于查找逻辑）
3. **跨平台差异**：当前预设是平台无关的，但 Windows 平台有额外的沙盒配置（`WindowsSandboxLevel`），在 Windows 特定的 TUI 代码中有特殊处理

### 6.3 改进建议

1. **添加预设查找辅助函数**：
   ```rust
   impl ApprovalPreset {
       pub const READ_ONLY: &'static str = "read-only";
       pub const AUTO: &'static str = "auto";
       pub const FULL_ACCESS: &'static str = "full-access";
       
       pub fn find_by_id(id: &str) -> Option<&'static Self> {
           builtin_approval_presets().iter().find(|p| p.id == id)
       }
   }
   ```

2. **支持配置扩展**：允许从配置文件加载额外的预设，而不是完全硬编码

3. **考虑合并到 protocol crate**：由于该 crate 仅依赖 `codex-protocol` 且功能简单，可以考虑将其合并到 `codex-protocol` 中，减少 crate 数量

4. **文档增强**：在 `builtin_approval_presets()` 函数文档中增加更详细的权限矩阵说明，帮助开发者理解各预设的具体差异

### 6.4 测试覆盖

该 crate 本身没有单元测试，但下游消费者（`codex-tui` 和 `codex-tui-app-server`）的测试使用了该 crate：
- `tui/src/chatwidget/tests.rs`：使用 `builtin_approval_presets` 进行权限预设相关的快照测试
- `tui_app_server/src/chatwidget/tests.rs`：同上

### 6.5 相关文档

- `AGENTS.md` 中的 Rust 编码规范
- `codex-rs/protocol/src/protocol.rs`：`AskForApproval` 和 `SandboxPolicy` 定义
- `codex-rs/protocol/src/permissions.rs`：权限系统详细实现
