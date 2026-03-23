# js_repl.rs 研究文档

## 场景与职责

`js_repl.rs` 是 Codex Rust 核心库的集成测试套件，专注于验证 **JavaScript REPL (js_repl) 工具** 的功能正确性。该工具允许 Codex 在 Node.js 环境中执行 JavaScript 代码，提供了一个有状态的 JavaScript 执行环境，支持变量持久化、顶级 await 和内置工具调用。

### 核心职责
1. **验证 js_repl 工具的核心功能**：代码执行、变量持久化、错误处理
2. **测试 Node.js 版本兼容性检查**：确保工具只在兼容的 Node 版本上启用
3. **验证状态持久化语义**：失败单元格的变量绑定处理、hoisted 绑定处理
4. **测试安全限制**：递归调用防护、敏感模块导入阻止
5. **验证内置工具集成**：通过 `codex.tool()` API 调用其他工具

---

## 功能点目的

### 1. Node 版本兼容性测试 (`js_repl_is_not_advertised_when_startup_node_is_incompatible`)
- **目的**：验证当 Node.js 版本过低时，js_repl 工具不会被广告给模型
- **关键验证点**：
  - 创建模拟的旧版本 Node 脚本（输出 `v0.0.1`）
  - 验证警告事件包含 "Disabled `js_repl` for this session"
  - 验证工具列表中不包含 `js_repl` 和 `js_repl_reset`
  - 验证系统指令中不包含 JavaScript REPL 相关说明

### 2. 变量持久化与 TLA 测试 (`js_repl_persists_top_level_destructured_bindings_and_supports_tla`)
- **目的**：验证解构绑定和顶级 await (Top-Level Await) 支持
- **关键验证点**：
  - 第一个单元格：`const { context: liveContext, session } = await Promise.resolve(...)`
  - 第二个单元格：访问 `liveContext` 和 `session` 变量
  - 验证变量值在单元格间持久化

### 3. 失败单元格语义测试套件

#### 3.1 初始化绑定持久化 (`js_repl_failed_cells_commit_initialized_bindings_only`)
- **目的**：验证失败单元格中已初始化的绑定会被提交
- **测试场景**：
  - 单元格 1：`const base = 40; console.log(base);` → 成功
  - 单元格 2：`const { session } = await Promise.resolve(...); throw new Error("boom"); const late = 99;` → 失败
  - 单元格 3：`console.log(base + session, typeof late);` → 应输出 `42 undefined`
  - 验证 `late` 变量未定义（因为赋值在 throw 之后）

#### 3.2 解构绑定部分失败 (`js_repl_failed_cells_preserve_initialized_lexical_destructuring_bindings`)
- **目的**：验证解构绑定中部分失败时的绑定状态
- **测试场景**：
  - 单元格 1：`const { a, b } = { a: 1, get b() { throw new Error("boom"); } };` → 失败
  - 验证 `a` 已绑定（值为 1），`b` 未绑定（ReferenceError）

#### 3.3 链接失败保持状态 (`js_repl_link_failures_keep_prior_module_state`)
- **目的**：验证静态导入失败时保持之前的状态
- **测试场景**：
  - 单元格 1：定义 `const answer = 41;`
  - 单元格 2：`import value from "./foo";` → 失败（不支持静态导入）
  - 单元格 3：验证 `answer` 变量仍然存在

#### 3.4 Hoisted 绑定未到达不提交 (`js_repl_failed_cells_do_not_commit_unreached_hoisted_bindings`)
- **目的**：验证失败单元格中未到达的 hoisted 绑定不会被提交
- **测试场景**：
  - 单元格 1：`var early = 1; throw new Error("boom"); var late = 2; function fn() { return 1; }` → 失败
  - 验证 `early` 已提交，`late` 和 `fn` 未提交

#### 3.5 Hoisted 函数读取限制 (`js_repl_failed_cells_do_not_preserve_hoisted_function_reads_before_declaration`)
- **目的**：验证函数声明前的读取不会保留
- **测试场景**：
  - 单元格 1：`foo(); throw new Error("boom"); function foo() {}` → 失败
  - 验证 `foo` 函数在失败后不可访问

#### 3.6 到达的函数声明持久化 (`js_repl_failed_cells_preserve_functions_when_declaration_sites_are_reached`)
- **目的**：验证已执行到的函数声明会被持久化
- **测试场景**：
  - 单元格 1：`function foo() {} throw new Error("boom");` → 失败
  - 验证 `foo` 函数在失败后仍然可用

#### 3.7 变量写入持久化 (`js_repl_failed_cells_preserve_prior_binding_writes_without_new_bindings`)
- **目的**：验证失败单元格中对已有绑定的写入会被持久化
- **测试场景**：
  - 单元格 1：`let x = 1;`
  - 单元格 2：`x = 2; throw new Error("boom");` → 失败
  - 验证 `x` 的值为 2（写入已持久化）

#### 3.8 Var 持久化边界 (`js_repl_failed_cells_var_persistence_boundaries`)
- **目的**：验证各种 var 绑定场景的边界行为
- **测试用例**：
  - 声明前赋值：`x = 5; ...; var x;` → 应提交
  - 短路逻辑赋值：`x &&= 1; y ||= 2; ...; var x, y, z;` → 仅提交已赋值的
  - 嵌套作用域写入：`{ let x = 1; x = 2; } ...; var x;` → 不应提交
  - 嵌套赋值：`x = (y = 1); ...; var x, y;` → 仅 `x` 提交
  - Var 解构失败：`var { a, b } = { a: 1, get b() { throw ... } };` → 都不提交

#### 3.9 循环变量提交 (`js_repl_failed_cells_commit_non_empty_loop_vars_but_skip_empty_loops`)
- **目的**：验证 for-of 循环变量的提交行为
- **测试场景**：
  - `for (var item of [2]) {} for (var emptyItem of []) {} throw new Error("boom");`
  - 验证 `item` 已提交（值为 2），`emptyItem` 未提交

### 4. 函数 toString 稳定性 (`js_repl_keeps_function_toString_stable`)
- **目的**：验证函数 toString 输出不包含内部标记
- **关键验证点**：
  - 函数定义 `function foo() { return 1; }`
  - 验证 `foo.toString()` 输出原始代码
  - 验证输出不包含 `__codexInternalMarkCommittedBindings`

### 5. globalThis 阴影支持 (`js_repl_allows_globalthis_shadowing_with_instrumented_bindings`)
- **目的**：验证允许用户代码遮蔽 globalThis
- **测试场景**：
  - `const globalThis = {}; const value = 1;`
  - 验证代码正常执行

### 6. 内置工具调用 (`js_repl_can_invoke_builtin_tools`)
- **目的**：验证通过 `codex.tool()` API 调用其他工具
- **测试场景**：
  - `await codex.tool("list_mcp_resources", {})`
  - 验证输出包含 `function_call_output`

### 7. 递归调用防护 (`js_repl_tool_call_rejects_recursive_js_repl_invocation`)
- **目的**：验证防止 js_repl 递归调用自身
- **测试场景**：
  - 尝试 `await codex.tool("js_repl", "console.log('recursive')")`
  - 验证错误消息包含 "js_repl cannot invoke itself"

### 8. 安全限制测试

#### 8.1 process 全局隐藏 (`js_repl_does_not_expose_process_global`)
- **目的**：验证 `process` 全局对象不可访问
- **验证**：`typeof process === "undefined"`

#### 8.2 路径助手 (`js_repl_exposes_codex_path_helpers`)
- **目的**：验证 `codex.cwd` 和 `codex.homeDir` 可用
- **验证**：路径助手返回正确的字符串值

#### 8.3 敏感模块导入阻止 (`js_repl_blocks_sensitive_builtin_imports`)
- **目的**：验证阻止导入敏感 Node.js 模块
- **测试场景**：
  - `await import("node:process")`
  - 验证错误消息包含 "Importing module ... is not allowed"

---

## 具体技术实现

### 测试基础设施

#### 辅助函数

```rust
// 运行单个 js_repl 调用
async fn run_js_repl_turn(
    server: &MockServer,
    prompt: &str,
    calls: &[(&str, &str)],
) -> Result<ResponseMock>

// 运行 js_repl 调用序列
async fn run_js_repl_sequence(
    server: &MockServer,
    prompt: &str,
    calls: &[(&str, &str)],
) -> Result<Vec<ResponseMock>>

// 断言 js_repl 调用成功
fn assert_js_repl_ok(req: &ResponsesRequest, call_id: &str, expected_output: &str)

// 断言 js_repl 调用失败
fn assert_js_repl_err(req: &ResponsesRequest, call_id: &str, expected_output: &str)
```

#### 旧版本 Node 模拟

```rust
fn write_too_old_node_script(dir: &Path) -> Result<std::path::PathBuf> {
    #[cfg(unix)]
    {
        let path = dir.join("old-node.sh");
        fs::write(&path, "#!/bin/sh\necho v0.0.1\n")?;
        let mut permissions = fs::metadata(&path)?.permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&path, permissions)?;
        Ok(path)
    }
}
```

### js_repl 工具实现架构

#### 核心模块
- **`codex-rs/core/src/tools/js_repl/mod.rs`**：js_repl 管理器实现
- **`codex-rs/core/src/tools/js_repl/kernel.js`**：Node.js 内核脚本
- **`codex-rs/core/src/tools/handlers/js_repl.rs`**：工具处理器实现

#### 状态持久化机制

js_repl 使用 JavaScript 代码插桩（instrumentation）来跟踪绑定：

1. **绑定标记**：在代码执行前插入 `__codexInternalMarkCommittedBindings` 调用
2. **状态捕获**：执行后捕获全局对象的快照
3. **状态恢复**：后续单元格执行前恢复之前的状态

#### 失败单元格语义

```javascript
// 伪代码示例
const state = captureState();
try {
    await executeCell(code);
    commitState(state);
} catch (error) {
    // 只提交已初始化的绑定
    commitPartialState(state, initializedBindings);
    throw error;
}
```

### Feature 标志控制

js_repl 通过 `Feature::JsRepl` 标志控制：

```rust
// 在测试中启用
config.features.enable(Feature::JsRepl).expect("test config should allow feature update");

// 处理器中检查
if !session.features().enabled(Feature::JsRepl) {
    return Err(FunctionCallError::RespondToModel("js_repl is disabled by feature flag".to_string()));
}
```

---

## 关键代码路径与文件引用

### 测试文件
- **当前文件**：`codex-rs/core/tests/suite/js_repl.rs` (712 行)

### 实现文件
- **`codex-rs/core/src/tools/js_repl/mod.rs`**：js_repl 管理器
- **`codex-rs/core/src/tools/js_repl/mod_tests.rs`**：单元测试
- **`codex-rs/core/src/tools/js_repl/kernel.js`**：Node.js 内核脚本
- **`codex-rs/core/src/tools/handlers/js_repl.rs`**：工具处理器
- **`codex-rs/core/src/tools/handlers/js_repl_tests.rs`**：处理器单元测试

### 依赖的协议定义
- **`codex-rs/protocol/src/protocol.rs`**：EventMsg、工具调用协议

### 依赖的测试支持库
- **`codex-rs/core/tests/common/responses.rs`**：Mock 响应生成
- **`codex-rs/core/tests/common/test_codex.rs`**：TestCodex 构建器

### Feature 定义
- **`codex-rs/core/src/features.rs`**：`Feature::JsRepl` 定义

---

## 依赖与外部交互

### 外部依赖
1. **Node.js**：必须安装兼容版本的 Node.js（通过 `CODEX_JS_REPL_NODE_PATH` 环境变量可配置）
2. **wiremock**：HTTP Mock 服务器
3. **tokio**：异步运行时
4. **tempfile**：临时目录管理

### 内部依赖
1. **codex_core**：核心库（Session、TurnContext、Features 等）
2. **codex_protocol**：协议类型
3. **core_test_support**：测试支持库

### 环境变量
- `CODEX_JS_REPL_NODE_PATH`：自定义 Node.js 可执行路径
- `CODEX_SANDBOX_NETWORK_DISABLED`：网络禁用标志（触发测试跳过）

---

## 风险、边界与改进建议

### 已知风险

1. **Node.js 版本依赖**：
   - 测试需要特定版本的 Node.js
   - 版本不兼容时工具被静默禁用

2. **平台限制**：
   - 使用 `#![allow(clippy::expect_used, clippy::unwrap_used)]` 放宽了错误处理检查
   - Unix/Windows 平台差异（旧版本 Node 模拟脚本）

3. **状态持久化复杂性**：
   - JavaScript 绑定语义复杂（hoisting、解构、循环变量等）
   - 测试覆盖了多种边界情况，但仍可能有遗漏

### 边界情况

1. **循环变量处理**：
   - 非空循环的变量被提交
   - 空循环的变量不被提交

2. **解构部分失败**：
   - 成功部分的绑定被提交
   - 失败部分的绑定不存在

3. **嵌套作用域**：
   - 块级作用域内的写入不提升到 var 声明

### 改进建议

1. **增加测试覆盖**：
   - 测试 Symbol 类型的持久化
   - 测试 ES 模块动态导入 (`import()`) 的行为
   - 测试异步错误（Promise 拒绝）的处理

2. **性能优化**：
   - 大状态对象的序列化性能
   - 频繁单元格执行的内存使用

3. **安全增强**：
   - 增加对 `eval` 的限制
   - 增加对 `Function` 构造器的限制
   - 增加执行时间限制

4. **错误诊断**：
   - 提供更详细的执行错误信息
   - 添加调试模式输出内部状态

5. **文档改进**：
   - 提供 js_repl 状态持久化语义的详细文档
   - 添加常见用例示例
