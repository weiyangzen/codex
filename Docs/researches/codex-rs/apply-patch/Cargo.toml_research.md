# Cargo.toml 研究文档

## 场景与职责

此 Cargo.toml 文件定义了 `codex-apply-patch` Rust crate 的元数据、编译配置和依赖关系。它是 Rust 生态系统的标准配置文件，与 BUILD.bazel 一起支持双构建系统（Cargo 和 Bazel）。

## 功能点目的

### 1. 包元数据
```toml
[package]
name = "codex-apply-patch"
version.workspace = true
edition.workspace = true
license.workspace = true
```

| 字段 | 说明 |
|------|------|
| `name` | Crate 名称，使用 kebab-case（短横线） |
| `version.workspace` | 从工作区继承版本号 |
| `edition.workspace` | 从工作区继承 Rust 版本（如 2021） |
| `license.workspace` | 从工作区继承许可证信息 |

### 2. 库目标配置
```toml
[lib]
name = "codex_apply_patch"
path = "src/lib.rs"
```
定义库目标，crate 名称使用 snake_case（下划线），这是 Rust 的命名惯例。

### 3. 二进制目标配置
```toml
[[bin]]
name = "apply_patch"
path = "src/main.rs"
```
定义可执行文件目标，名称为 `apply_patch`，入口文件为 `src/main.rs`。

### 4. 代码检查配置
```toml
[lints]
workspace = true
```
从工作区继承 lint 规则配置。

### 5. 依赖项

#### 运行时依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `anyhow` | workspace | 错误处理和传播 |
| `similar` | workspace | 文本差异计算（unified diff） |
| `thiserror` | workspace | 自定义错误类型定义 |
| `tree-sitter` | workspace | Bash 脚本解析（用于提取 heredoc） |
| `tree-sitter-bash` | workspace | Bash 语法支持 |

#### 开发依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `assert_cmd` | workspace | CLI 测试断言 |
| `assert_matches` | workspace | 模式匹配断言 |
| `codex-utils-cargo-bin` | workspace | 测试时定位二进制文件 |
| `pretty_assertions` | workspace | 美观的测试差异输出 |
| `tempfile` | workspace | 临时目录/文件创建 |

## 具体技术实现

### 双目标构建
此 crate 同时生成：
1. **库** (`codex_apply_patch`)：供其他 crate 调用补丁逻辑
2. **二进制** (`apply_patch`)：独立 CLI 工具

```rust
// src/main.rs - 简单的入口转发
pub fn main() -> ! {
    codex_apply_patch::main()
}
```

### 依赖使用场景

#### similar - 差异计算
```rust
// src/lib.rs
use similar::TextDiff;
let text_diff = TextDiff::from_lines(&original_contents, &new_contents);
let unified_diff = text_diff.unified_diff().context_radius(context).to_string();
```

#### tree-sitter - Bash 解析
```rust
// src/invocation.rs
use tree_sitter::Parser;
use tree_sitter_bash::LANGUAGE as BASH;
// 用于从 shell 脚本中提取 heredoc 形式的补丁内容
```

## 关键代码路径与文件引用

```
codex-rs/apply-patch/
├── Cargo.toml              # 本文件
├── BUILD.bazel             # Bazel 构建配置
├── apply_patch_tool_instructions.md  # 工具说明文档
└── src/
    ├── lib.rs              # 库入口（核心逻辑）
    ├── main.rs             # 二进制入口（简单转发）
    ├── parser.rs           # 补丁格式解析
    ├── invocation.rs       # 调用方式解析（shell/heredoc）
    ├── seek_sequence.rs    # 文本匹配算法
    └── standalone_executable.rs  # 独立可执行文件逻辑
```

## 依赖与外部交互

### 工作区依赖
所有依赖都使用 `workspace = true`，版本在根目录 `Cargo.toml` 中统一管理：
- 路径：`codex-rs/Cargo.toml`
- 章节：`[workspace.dependencies]`

### 内部依赖关系
```
codex-apply-patch
    ↑
    ├── codex-core (使用库功能)
    ├── codex-arg0 (通过 arg0 分发调用)
    └── codex-exec (执行补丁操作)
```

### 测试依赖
- `tests/all.rs` - 测试入口
- `tests/suite/cli.rs` - CLI 集成测试
- `tests/suite/tool.rs` - 工具行为测试
- `tests/suite/scenarios.rs` - 场景测试（使用 fixtures）

## 风险、边界与改进建议

### 风险
1. **版本漂移**：工作区依赖版本变更可能影响此 crate 的兼容性
2. **tree-sitter 版本**：tree-sitter 的 C 库绑定可能引入平台相关构建问题
3. **双构建系统维护**：Cargo.toml 和 BUILD.bazel 需要保持同步

### 边界
- 不支持 Windows 上的某些功能（如 `codex-utils-cargo-bin` 的某些用法）
- `tree-sitter-bash` 仅用于解析 Unix shell 脚本，PowerShell/Cmd 支持有限

### 改进建议
1. **功能标志**：考虑添加 `cli` 和 `library` 功能标志，允许仅编译库部分
2. **最小化依赖**：如果可能，考虑用更轻量的方案替代 tree-sitter（如简单正则）
3. **文档依赖**：添加 `[[package.metadata.docs.rs]]` 配置优化文档构建
4. **版本锁定**：考虑为关键依赖（如 tree-sitter）指定最小版本约束
