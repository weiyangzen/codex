# codex-rs/protocol/BUILD.bazel 研究文档

## 场景与职责

该文件是 Bazel 构建系统的构建配置，用于定义 `codex-protocol` crate 的构建规则。它位于 Rust 协议 crate 的根目录，负责声明如何编译和打包这个核心协议库。

## 功能点目的

### 1. 加载通用构建规则
```bazel
load("//:defs.bzl", "codex_rust_crate")
```
从项目根目录的 `defs.bzl` 加载自定义的 `codex_rust_crate` 宏，这是项目统一封装的 Rust crate 构建规则。

### 2. 定义 Protocol Crate
```bazel
codex_rust_crate(
    name = "protocol",
    crate_name = "codex_protocol",
    compile_data = glob(["src/prompts/**/*.md"]),
)
```

| 属性 | 值 | 说明 |
|------|-----|------|
| `name` | `protocol` | Bazel 目标名称 |
| `crate_name` | `codex_protocol` | 编译后的 crate 名称（Rust 中使用） |
| `compile_data` | `glob(["src/prompts/**/*.md"])` | 编译时数据文件，包含所有提示词模板 |

### 3. 编译数据说明
`compile_data` 使用 glob 模式匹配 `src/prompts/**/*.md`，这意味着：
- 所有 Markdown 格式的提示词模板文件会被打包到编译产物中
- 这些文件通过 `include_str!` 宏在代码中被引用（如 `BASE_INSTRUCTIONS_DEFAULT`）
- 支持按目录组织不同类别的提示词（permissions、realtime 等）

## 具体技术实现

### 构建流程
1. Bazel 解析 `BUILD.bazel` 文件
2. 调用 `codex_rust_crate` 宏生成实际的构建规则
3. 编译 Rust 源码（`src/lib.rs` 及所有子模块）
4. 将 `compile_data` 中的 Markdown 文件作为编译时资源嵌入

### 关键代码路径
- **构建定义**: `//:defs.bzl`（项目根目录的构建宏）
- **源码入口**: `src/lib.rs`
- **提示词模板**: `src/prompts/**/*.md`
  - `src/prompts/base_instructions/default.md`
  - `src/prompts/permissions/approval_policy/*.md`
  - `src/prompts/permissions/sandbox_mode/*.md`
  - `src/prompts/realtime/*.md`

## 依赖与外部交互

### 内部依赖
- `//:defs.bzl` - 项目级构建宏定义
- 同目录下的所有 Rust 源文件

### 外部依赖（通过 Cargo.toml）
该 crate 依赖以下 workspace 级别的 crate：
- `codex-execpolicy` - 执行策略
- `codex-git` - Git 操作
- `codex-utils-absolute-path` - 绝对路径工具
- `codex-utils-image` - 图像处理工具

### 被依赖方
- `codex-core` - 核心逻辑 crate
- `codex-tui` - 终端 UI crate
- `codex-app-server` - 应用服务器
- SDK 和其他客户端

## 风险、边界与改进建议

### 风险
1. **提示词文件缺失**: 如果 `src/prompts/` 目录下的 Markdown 文件被删除或重命名，会导致编译失败（`include_str!` 宏在编译时检查文件存在性）
2. **glob 模式过度匹配**: 当前模式会匹配所有子目录的 `.md` 文件，可能包含不需要的文件

### 边界
- 仅负责编译时资源打包，运行时文件访问需通过其他机制
- 不处理测试依赖（在 `Cargo.toml` 中定义）

### 改进建议
1. **显式列出关键文件**: 对于核心的提示词文件，建议显式列出而非仅依赖 glob，以提高可维护性
2. **添加验证规则**: 可在构建时添加对提示词文件内容的验证
3. **文档化提示词结构**: 在 `src/prompts/` 下添加 README 说明各子目录用途

### 相关文件引用
```
codex-rs/protocol/
├── BUILD.bazel          # 本文件
├── Cargo.toml           # Cargo 配置
├── src/
│   ├── lib.rs          # 库入口
│   └── prompts/        # 编译时嵌入的提示词模板
│       ├── base_instructions/
│       ├── permissions/
│       └── realtime/
```
