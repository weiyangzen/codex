# ignore_external_methods.rs 研究文档

## 场景与职责

本文件是 `argument_comment_lint` 工具的 UI 测试用例，用于验证 lint 规则对**外部 crate 方法**的忽略行为。

核心场景：当调用标准库或第三方 crate 的方法时，即使使用字面量参数，lint 也不应产生警告。这是因为：
1. 外部 crate 的源代码不可控
2. 标准库方法的参数名可能不稳定
3. 强制注释外部方法调用会增加无意义的负担

## 功能点目的

验证以下场景不会产生 lint 警告：
1. 调用标准库方法（如 `str::starts_with`, `str::find`）时使用字面量
2. 调用标准库方法时使用字符字面量
3. 调用标准库方法时使用数组和字符串字面量

### 测试场景覆盖
- `str::starts_with('{')` - 字符字面量
- `str::find("type")` - 字符串字面量
- `array.join("\n")` - 字符串字面量

## 具体技术实现

### 测试代码分析

```rust
#![warn(uncommented_anonymous_literal_argument)]

fn main() {
    let line = "{\"type\":\"response_item\"}";
    let _ = line.starts_with('{');
    let _ = line.find("type");
    let parts = ["type", "response_item"];
    let _ = parts.join("\n");
}
```

测试要点：
1. **`starts_with('{')`**：字符字面量作为参数
2. **`find("type")`**：字符串字面量作为参数
3. **`join("\n")`**：字符串字面量作为分隔符

所有这些都是标准库方法调用，**都不应该**触发 `uncommented_anonymous_literal_argument` 警告。

### 外部 Crate 过滤逻辑

在 `src/lib.rs` 第 158-164 行：

```rust
fn check_call<'tcx>(...) {
    let Some(def_id) = fn_def_id(cx, call) else {
        return;
    };
    if !def_id.is_local() && !is_workspace_crate_name(cx.tcx.crate_name(def_id.krate).as_str())
    {
        return;
    }
    // ...
}
```

关键逻辑：
1. `def_id.is_local()`：检查定义是否在本地 crate
2. `is_workspace_crate_name(...)`：检查是否属于项目 workspace
3. 如果两者都不满足，直接返回，不进行检查

### Workspace Crate 白名单

在 `src/lib.rs` 第 253-259 行：

```rust
fn is_workspace_crate_name(name: &str) -> bool {
    name.starts_with("codex_")
        || matches!(
            name,
            "app_test_support" | "core_test_support" | "mcp_test_support"
        )
}
```

被允许的 crate 名称模式：
- 以 `codex_` 开头的所有 crate（如 `codex_core`, `codex_tui`）
- 特定的测试支持 crate

这意味着：
- `std` - ❌ 被忽略
- `tokio` - ❌ 被忽略
- `codex_core` - ✅ 会被检查

### 为什么标准库方法被豁免

1. **API 稳定性**：标准库参数名虽然稳定，但强制注释每个 `find("...")` 调用过于繁琐
2. **语义明确**：`starts_with('{')` 的语义已经很清晰
3. **跨版本兼容**：参数名可能在不同 Rust 版本间变化
4. **开发者体验**：减少无意义的警告噪音

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tools/argument-comment-lint/ui/ignore_external_methods.rs` | 本测试文件 |
| `tools/argument-comment-lint/src/lib.rs:158-164` | 外部 crate 过滤逻辑 |
| `tools/argument-comment-lint/src/lib.rs:253-259` | Workspace crate 白名单 |
| `tools/argument-comment-lint/src/lib.rs:267-273` | 白名单函数的单元测试 |

## 依赖与外部交互

### Rustc API
- `rustc_hir::def_id::DefId::is_local()`：检查定义是否本地
- `rustc_middle::ty::TyCtxt::crate_name()`：获取 crate 名称

### Clippy Utils
- `fn_def_id`：从表达式解析函数定义 ID

## 风险、边界与改进建议

### 当前边界
1. **仅检查本地和 workspace crate**：第三方依赖完全豁免
2. **Crate 名称硬编码**：`codex_` 前缀和特定名称写死在代码中
3. **无配置选项**：无法通过配置自定义哪些 crate 需要检查

### 潜在风险
1. **内部依赖**：如果 workspace 依赖了另一个使用 `codex_` 前缀的外部 crate，会被错误地检查
2. **Crate 重命名**：通过 `Cargo.toml` 重命名的 crate 可能无法被正确识别
3. **测试覆盖**：单元测试只测试了 `is_workspace_crate_name` 函数，未测试完整的过滤逻辑

### 改进建议
1. **配置化**：通过 `clippy.toml` 或自定义配置文件允许项目定义自己的 crate 白名单
2. **元数据检测**：使用 `Cargo.toml` 的 `workspace.members` 信息自动识别 workspace crate
3. **属性标记**：提供 `#[allow(argument_comment_lint)]` 属性，允许在特定函数上禁用
4. **分层策略**：
   - 本地代码：强制要求注释
   - Workspace 代码：警告级别
   - 外部 crate：完全忽略
5. **文档说明**：在 lint 文档中明确说明哪些代码会被检查

### 测试扩展建议
- 添加对第三方 crate（如 `serde`）的测试
- 测试 `codex_` 前缀 crate 确实会被检查
- 测试宏生成的代码是否被正确处理
