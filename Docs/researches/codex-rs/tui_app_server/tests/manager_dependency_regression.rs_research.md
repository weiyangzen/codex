# manager_dependency_regression.rs 研究文档

## 场景与职责

`manager_dependency_regression.rs` 是一个架构守卫测试（architectural guard test），用于防止 `tui_app_server` 的源代码引入对 `AuthManager` 和 `ThreadManager` 的直接依赖。这是回归测试，确保代码架构的层次边界不被破坏。

该测试体现了项目的架构设计原则：**tui_app_server 不应直接访问 manager 级别的 "escape hatches"（逃生舱口）**，而应通过更高层次的抽象进行交互。

## 功能点目的

1. **架构边界守卫**：确保运行时源代码不直接依赖 `AuthManager` 和 `ThreadManager`
2. **回归检测**：防止未来代码变更意外引入被禁止的依赖模式
3. **代码审查自动化**：将架构规则编码为可自动执行的测试

## 具体技术实现

### 核心测试逻辑

```rust
#[test]
fn tui_app_server_runtime_source_does_not_depend_on_manager_escape_hatches() {
    let src_dir = codex_utils_cargo_bin::find_resource!("src")
        .unwrap_or_else(|err| panic!("failed to resolve src runfile: {err}"));
    let sources = rust_sources_under(&src_dir);
    let forbidden = [
        "AuthManager",
        "ThreadManager",
        "auth_manager(",
        "thread_manager(",
    ];

    let violations: Vec<String> = sources
        .iter()
        .flat_map(|path| {
            let contents = fs::read_to_string(path)
                .unwrap_or_else(|err| panic!("failed to read {}: {err}", path.display()));
            let path_display = path.display().to_string();
            forbidden
                .iter()
                .filter(move |needle| contents.contains(**needle))
                .map(move |needle| format!("{path_display} contains `{needle}`"))
        })
        .collect();

    assert!(
        violations.is_empty(),
        "unexpected manager dependency regression(s):\n{}",
        violations.join("\n")
    );
}
```

### 辅助函数

```rust
fn rust_sources_under(dir: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    let entries =
        fs::read_dir(dir).unwrap_or_else(|err| panic!("failed to read {}: {err}", dir.display()));
    for entry in entries {
        let entry = entry.unwrap_or_else(|err| panic!("failed to read dir entry: {err}"));
        let path = entry.path();
        if path.is_dir() {
            files.extend(rust_sources_under(&path));
        } else if path.extension().is_some_and(|ext| ext == "rs") {
            files.push(path);
        }
    }
    files.sort();
    files
}
```

### 禁止模式列表

| 禁止模式 | 说明 |
|----------|------|
| `AuthManager` | 认证管理器类型名 |
| `ThreadManager` | 线程/会话管理器类型名 |
| `auth_manager(` | 认证管理器函数调用 |
| `thread_manager(` | 线程管理器函数调用 |

## 关键代码路径与文件引用

### 被守卫的代码

| 路径 | 说明 |
|------|------|
| `codex-rs/tui_app_server/src/` | 被扫描的源代码目录 |
| `codex-rs/app-server/src/` | 可能定义 Manager 类型的位置 |

### 相关架构组件

```
codex-rs/
├── app-server/src/          # 定义 AuthManager, ThreadManager
│   ├── auth_manager.rs
│   └── thread_manager.rs
├── tui_app_server/src/      # 被测试守卫的代码
│   ├── lib.rs
│   ├── app.rs
│   └── ...
└── tui_app_server/tests/
    └── manager_dependency_regression.rs  # 本测试
```

### 运行时资源定位

测试使用 `codex_utils_cargo_bin::find_resource!` 宏来定位源代码目录，该宏支持：
- **Cargo 构建**：通过 `CARGO_MANIFEST_DIR` 定位
- **Bazel 构建**：通过 runfiles 系统定位

## 依赖与外部交互

### 依赖的 crates

| crate | 用途 |
|-------|------|
| `std::fs` | 文件系统遍历和读取 |
| `std::path` | 路径处理 |
| `codex_utils_cargo_bin` | 运行时资源定位（Cargo/Bazel 兼容）|

### 测试执行流程

1. 使用 `find_resource!("src")` 定位源代码目录
2. 递归遍历所有 `.rs` 文件
3. 对每个文件内容检查禁止模式
4. 收集所有违规项并生成错误报告
5. 断言无违规，否则测试失败

## 风险、边界与改进建议

### 当前风险

1. **字符串匹配局限**：简单的字符串匹配可能产生误报（如注释中的提及）或漏报（如动态生成的代码）
2. **重构敏感性**：如果 Manager 类型重命名，测试需要同步更新
3. **性能考虑**：随着代码库增长，全量文件扫描可能变慢

### 边界情况

1. **测试代码豁免**：测试位于 `tests/` 目录，不在扫描范围内
2. **生成代码**：如果 `src/` 包含生成的代码，可能需要排除
3. **宏展开**：宏展开后的代码可能包含禁止模式，但当前测试只检查源码

### 改进建议

1. **语义分析增强**：考虑使用 `syn` crate 进行 AST 级别的依赖分析，而非字符串匹配
2. **允许列表**：添加注释标记（如 `// arch-allow: AuthManager`）用于特殊情况豁免
3. **性能优化**：
   - 添加文件修改时间缓存
   - 使用并行扫描
   - 限制扫描深度或排除特定子目录
4. **错误信息改进**：
   - 显示违规代码的上下文行号
   - 提供修复建议文档链接
5. **扩展守卫规则**：
   - 考虑添加更多架构层级的依赖规则
   - 支持正则表达式匹配更复杂的模式

### 架构意义

该测试反映了项目的分层架构设计：

```
┌─────────────────────────────────────┐
│  TUI App Server (UI Layer)          │
│  - 不应直接访问 Manager              │
├─────────────────────────────────────┤
│  App Server Protocol (API Layer)    │
│  - 定义通信协议                      │
├─────────────────────────────────────┤
│  App Server (Business Logic Layer)  │
│  - AuthManager, ThreadManager        │
│  - 核心业务逻辑                      │
└─────────────────────────────────────┘
```

这种设计确保了 UI 层与业务逻辑层的解耦，便于独立测试和替换实现。
