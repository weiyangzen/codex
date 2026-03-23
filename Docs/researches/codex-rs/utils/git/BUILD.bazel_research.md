# codex-rs/utils/git/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统对 `codex-git` crate 的构建配置。该文件位于 `codex-rs/utils/git/` 目录下，负责定义 Rust 库目标，使 Bazel 能够正确编译和链接 `codex-git` 库。

此 crate 是 Codex 项目的 Git 工具库，提供补丁应用、工作树快照（ghost commits）等核心功能，被多个上层模块依赖（如 `codex-core`、`codex-chatgpt`）。

## 功能点目的

该 BUILD 文件的核心目的是：

1. **声明 Rust 库目标**：使用项目自定义的 `codex_rust_crate` 宏定义一个可复用的 Rust 库
2. **统一构建配置**：继承项目根目录的 `defs.bzl` 中定义的构建规则，确保与其他 crate 一致的编译选项
3. **指定 crate 名称**：将内部名称 `"git"` 映射到外部 crate 名称 `"codex_git"`，符合 Rust 命名规范

## 具体技术实现

### 构建规则引用

```bazel
load("//:defs.bzl", "codex_rust_crate")
```

从项目根目录的 `defs.bzl` 加载自定义宏 `codex_rust_crate`。该宏封装了 Rust 库目标的创建逻辑，包括：
- 自动检测 `Cargo.toml` 依赖
- 配置编译器选项
- 设置 crate 元数据

### 目标定义

```bazel
codex_rust_crate(
    name = "git",
    crate_name = "codex_git",
)
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"git"` | Bazel 目标名称，用于在 BUILD 文件中引用 |
| `crate_name` | `"codex_git"` | 生成的 Rust crate 名称，符合 `snake_case` 规范 |

### 隐式依赖处理

`codex_rust_crate` 宏会自动处理以下依赖（定义在 `Cargo.toml` 中）：
- `once_cell` - 延迟初始化
- `regex` - 正则表达式解析
- `schemars` - JSON Schema 生成
- `serde` - 序列化/反序列化
- `tempfile` - 临时文件管理
- `thiserror` - 错误处理
- `ts-rs` - TypeScript 类型生成
- `walkdir` - 目录遍历

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/git/BUILD.bazel` - 本构建配置文件

### 相关源文件（由 Bazel 编译）
- `codex-rs/utils/git/src/lib.rs` - 库入口，导出公共 API
- `codex-rs/utils/git/src/apply.rs` - 补丁应用逻辑（~847 行）
- `codex-rs/utils/git/src/ghost_commits.rs` - Ghost commit 快照功能（~1785 行）
- `codex-rs/utils/git/src/branch.rs` - 分支操作（~256 行）
- `codex-rs/utils/git/src/operations.rs` - Git 命令封装（~239 行）
- `codex-rs/utils/git/src/errors.rs` - 错误定义（~35 行）
- `codex-rs/utils/git/src/platform.rs` - 平台相关代码（~37 行）

### 上游依赖
- `//:defs.bzl` - 项目级 Bazel 宏定义

### 下游使用者
- `codex-rs/core/BUILD.bazel` - 核心模块依赖
- `codex-rs/chatgpt/BUILD.bazel` - ChatGPT CLI 依赖

## 依赖与外部交互

### Bazel 构建依赖
```
//:defs.bzl
```

### Cargo.toml 定义的 Rust 依赖
- `once_cell` (workspace) - 用于 `Lazy` 静态正则表达式编译
- `regex` (^1) - 解析 `git apply` 输出
- `schemars` (workspace) - 为 `GhostCommit` 等结构生成 JSON Schema
- `serde` (workspace) - 序列化支持
- `tempfile` (workspace) - 临时补丁文件
- `thiserror` (workspace) - 错误派生宏
- `ts-rs` (workspace) - TypeScript 绑定生成
- `walkdir` (workspace) - 目录遍历

### 运行时外部依赖
- `git` 可执行文件 - 所有功能都通过 shell out 到系统 git 实现

## 风险、边界与改进建议

### 风险点

1. **git 版本兼容性**：代码依赖系统安装的 git，不同版本输出格式可能有差异
   - 缓解：`apply.rs` 中使用了大量正则表达式匹配，已覆盖常见输出格式

2. **Bazel/Cargo 双构建系统**：项目同时支持 Bazel 和 Cargo 构建，需保持两者同步
   - 缓解：`codex_rust_crate` 宏从 `Cargo.toml` 读取依赖，减少重复配置

3. **平台限制**：`platform.rs` 仅支持 Unix 和 Windows
   - 其他平台会在编译时报错（`compile_error!`）

### 边界条件

1. **空仓库处理**：`ghost_commits.rs` 支持无 HEAD 的仓库（新初始化仓库）
2. **大文件处理**：默认忽略 >10MiB 的未跟踪文件，>200 文件的目录
3. **路径逃逸防护**：`operations.rs` 中的 `normalize_relative_path` 阻止 `../` 攻击

### 改进建议

1. **添加构建测试**：在 CI 中验证 Bazel 和 Cargo 构建结果一致
   ```bazel
   # 可考虑添加的测试目标
   rust_test(
       name = "git_test",
       crate = ":git",
   )
   ```

2. **文档生成**：利用 `schemars` 和 `ts-rs` 依赖，在构建时生成 API 文档

3. **特性门控**：考虑为不同功能（apply/ghost/symlink）添加 Cargo features，减少编译体积

4. **git 版本检测**：在运行时检测 git 版本，对已知不兼容版本发出警告
