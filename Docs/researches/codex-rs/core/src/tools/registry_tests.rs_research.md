# registry_tests.rs 深度研究文档

## 场景与职责

`registry_tests.rs` 是 `registry.rs` 的单元测试模块，主要验证工具注册表的命名空间查找功能。虽然代码量较小（约 50 行），但测试了工具系统中一个关键但容易被忽视的功能：带命名空间的工具处理器查找。

## 功能点目的

### 测试覆盖范围

1. **命名空间键生成验证**
   - 验证 `tool_handler_key()` 函数正确生成带命名空间的键
   - 验证普通工具名和命名空间工具名的区分

2. **处理器查找逻辑**
   - 验证无命名空间查找返回普通处理器
   - 验证带命名空间查找返回命名空间处理器
   - 验证错误命名空间返回 None

3. **处理器身份验证**
   - 使用 `Arc::ptr_eq` 验证返回的处理器与注册的是同一实例

## 具体技术实现

### 测试结构

```rust
// 测试处理器桩
struct TestHandler;

#[async_trait]
impl ToolHandler for TestHandler {
    type Output = crate::tools::context::FunctionToolOutput;

    fn kind(&self) -> ToolKind {
        ToolKind::Function
    }

    async fn handle(&self, _invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        unreachable!("test handler should not be invoked")
    }
}
```

### 核心测试用例

```rust
#[test]
fn handler_looks_up_namespaced_aliases_explicitly() {
    // 准备：创建两个处理器实例
    let plain_handler = Arc::new(TestHandler) as Arc<dyn AnyToolHandler>;
    let namespaced_handler = Arc::new(TestHandler) as Arc<dyn AnyToolHandler>;
    
    // 测试数据
    let namespace = "mcp__codex_apps__gmail";
    let tool_name = "gmail_get_recent_emails";
    let namespaced_name = tool_handler_key(tool_name, Some(namespace));
    
    // 构建注册表
    let registry = ToolRegistry::new(HashMap::from([
        (tool_name.to_string(), Arc::clone(&plain_handler)),
        (namespaced_name, Arc::clone(&namespaced_handler)),
    ]));

    // 执行查找
    let plain = registry.handler(tool_name, None);
    let namespaced = registry.handler(tool_name, Some(namespace));
    let missing_namespaced = registry.handler(tool_name, Some("mcp__codex_apps__calendar"));

    // 验证结果
    assert_eq!(plain.is_some(), true);
    assert_eq!(namespaced.is_some(), true);
    assert_eq!(missing_namespaced.is_none(), true);
    assert!(plain.as_ref().is_some_and(|handler| Arc::ptr_eq(handler, &plain_handler)));
    assert!(namespaced.as_ref().is_some_and(|handler| Arc::ptr_eq(handler, &namespaced_handler)));
}
```

### 测试场景分析

```
┌─────────────────────────────────────────────────────────────────┐
│              注册表状态（测试设置）                               │
├─────────────────────────────────────────────────────────────────┤
│ 键                                  │ 处理器                     │
├─────────────────────────────────────┼───────────────────────────┤
│ "gmail_get_recent_emails"           │ plain_handler (Arc)       │
│ "mcp__codex_apps__gmail:gmail_get_recent_emails" │ namespaced_handler │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        查找验证                                   │
├─────────────────────────────────────────────────────────────────┤
│ 查找调用                                    │ 预期结果           │
├─────────────────────────────────────────────┼────────────────────┤
│ handler("gmail_get_recent_emails", None)    │ plain_handler      │
│ handler("gmail_get_recent_emails", Some("mcp__codex_apps__gmail")) │ namespaced_handler │
│ handler("gmail_get_recent_emails", Some("mcp__codex_apps__calendar")) │ None (未找到)   │
└─────────────────────────────────────────────────────────────────┘
```

## 关键代码路径与文件引用

### 被测试代码

| 被测试项 | 定义位置 |
|----------|----------|
| `ToolRegistry::handler()` | `registry.rs:141-145` |
| `tool_handler_key()` | `registry.rs:124-130` |
| `ToolRegistry::new()` | `registry.rs:136-139` |

### 测试使用的方法

```rust
// registry.rs 中仅测试使用的代码
#[cfg(test)]
pub(crate) fn has_handler(&self, name: &str, namespace: Option<&str>) -> bool {
    self.handler(name, namespace).is_some()
}
```

注意：`has_handler` 方法虽然存在，但当前测试并未使用它，而是直接使用 `handler()` 方法。

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `super::*` | 被测试的 registry 模块 |
| `crate::tools::context::ToolInvocation` | ToolHandler trait 依赖 |
| `async_trait::async_trait` | 异步 trait 支持 |
| `pretty_assertions::assert_eq` | 更好的断言输出 |

### 测试模块声明

```rust
// registry.rs:540-542
#[cfg(test)]
#[path = "registry_tests.rs"]
mod tests;
```

## 风险、边界与改进建议

### 当前测试的局限性

1. **覆盖范围有限**
   - 仅测试了处理器查找，未测试 `dispatch_any()`
   - 未测试 `ToolRegistryBuilder`
   - 未测试 `AnyToolResult`
   - 未测试钩子分发

2. **Mock 不完整**
   - `TestHandler::handle()` 使用 `unreachable!()`
   - 未测试 `is_mutating()` 的行为
   - 未测试 `matches_kind()` 的验证逻辑

3. **并发测试缺失**
   - 未测试多线程环境下的注册表访问
   - 未测试 `Arc` 克隆的正确性

### 边界情况未覆盖

1. **空字符串命名空间**
   ```rust
   // 未测试：Some("") vs None 的区别
   handler(tool_name, Some(""))
   ```

2. **特殊字符**
   ```rust
   // 未测试：工具名包含 ':' 的情况
   handler("tool:name:with:colons", None)
   ```

3. **处理器覆盖**
   ```rust
   // 未测试：重复注册同一键的行为
   ```

### 改进建议

1. **扩展测试覆盖**
   ```rust
   // 建议添加：dispatch_any 基础测试
   #[tokio::test]
   async fn dispatch_returns_error_for_unknown_tool() {
       let registry = ToolRegistry::new(HashMap::new());
       let invocation = create_test_invocation("unknown_tool");
       let result = registry.dispatch_any(invocation).await;
       assert!(matches!(result, Err(FunctionCallError::RespondToModel(_))));
   }
   ```

2. **添加并发测试**
   ```rust
   // 建议添加：并发查找测试
   #[tokio::test]
   async fn concurrent_handler_lookup_is_safe() {
       // 使用多个任务并发查找同一处理器
   }
   ```

3. **添加边界测试**
   ```rust
   // 建议添加：空命名空间测试
   #[test]
   fn empty_namespace_differs_from_none() {
       let registry = create_test_registry();
       let with_empty = registry.handler("tool", Some(""));
       let with_none = registry.handler("tool", None);
       // 验证两者可能不同
   }
   ```

4. **集成测试建议**
   - 测试完整的工具调用流程（从路由到执行）
   - 测试 MCP 工具的实际注册和调用
   - 测试钩子分发的集成

### 相关文件引用

| 文件 | 关系 |
|------|------|
| `codex-rs/core/src/tools/registry.rs` | 被测试的主模块 |
| `codex-rs/core/src/tools/router_tests.rs` | 相关的路由层测试 |
| `codex-rs/core/src/tools/context.rs` | ToolInvocation 定义 |
