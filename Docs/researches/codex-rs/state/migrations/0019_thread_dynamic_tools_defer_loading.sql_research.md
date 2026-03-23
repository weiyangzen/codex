# 0019_thread_dynamic_tools_defer_loading.sql 研究文档

## 场景与职责

本迁移为 `thread_dynamic_tools` 表添加 `defer_loading` 字段，支持动态工具的延迟加载。这优化了 MCP 工具的加载性能，只在需要时才加载工具定义。

## 功能点目的

### 1. 添加 defer_loading 字段
- **字段**: `defer_loading INTEGER`
- **约束**: `NOT NULL DEFAULT 0`
- **用途**: 标记工具是否延迟加载

### 使用场景
- **性能优化**: 大量工具时避免一次性全部加载
- **按需加载**: 只在工具被调用时加载详细定义
- **内存管理**: 减少初始内存占用

## 具体技术实现

### 关键流程

#### 工具持久化
写入工具时记录延迟加载标记：
```rust
pub async fn persist_dynamic_tools(
    &self,
    thread_id: ThreadId,
    tools: Option<&[DynamicToolSpec]>,
) -> anyhow::Result<()> {
    for (idx, tool) in tools.iter().enumerate() {
        sqlx::query(
            r#"
INSERT INTO thread_dynamic_tools (
    thread_id,
    position,
    name,
    description,
    input_schema,
    defer_loading  -- 新增字段
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(thread_id, position) DO NOTHING
            "#,
        )
        .bind(thread_id.as_str())
        .bind(position)
        .bind(tool.name.as_str())
        .bind(tool.description.as_str())
        .bind(input_schema)
        .bind(tool.defer_loading)  // 绑定延迟加载标记
        .execute(&mut *tx)
        .await?;
    }
}
```

#### 工具加载
查询时包含延迟加载标记：
```rust
pub async fn get_dynamic_tools(
    &self,
    thread_id: ThreadId,
) -> anyhow::Result<Option<Vec<DynamicToolSpec>>> {
    let rows = sqlx::query(
        r#"
SELECT name, description, input_schema, defer_loading
FROM thread_dynamic_tools
WHERE thread_id = ?
ORDER BY position ASC
        "#,
    )
    .bind(thread_id.to_string())
    .fetch_all(self.pool.as_ref())
    .await?;
    
    for row in rows {
        tools.push(DynamicToolSpec {
            name: row.try_get("name")?,
            description: row.try_get("description")?,
            input_schema,
            defer_loading: row.try_get("defer_loading")?,  // 读取标记
        });
    }
}
```

### 代码映射
在 `codex-protocol/src/dynamic_tools.rs` 中：
```rust
pub struct DynamicToolSpec {
    pub name: String,
    pub description: String,
    pub input_schema: Value,
    pub defer_loading: bool,  // 新增字段
}
```

## 关键代码路径与文件引用

### 工具管理
- `codex-rs/state/src/runtime/threads.rs`:
  - `persist_dynamic_tools()`: 持久化工具时写入标记
  - `get_dynamic_tools()`: 查询时读取标记

### 协议定义
- `codex-protocol/src/dynamic_tools.rs`:
  - `DynamicToolSpec`: 工具定义包含延迟加载标记

### MCP 客户端
- `codex-rs/core/src/mcp_client.rs`: 根据标记决定加载策略

## 依赖与外部交互

### 上游依赖
- `0004_thread_dynamic_tools.sql`: 基础 thread_dynamic_tools 表

### 下游依赖
- 无直接下游依赖

### 应用层交互
- MCP 服务器声明工具时指定是否延迟加载
- 客户端根据标记优化工具加载

## 风险、边界与改进建议

### 风险
1. **加载失败**: 延迟加载时可能遇到网络或服务器问题
2. **用户体验**: 首次调用延迟加载工具可能有延迟

### 边界情况
1. **全部延迟**: 所有工具都标记为延迟加载
2. **混合模式**: 部分延迟、部分立即加载
3. **加载超时**: 延迟加载超时处理

### 改进建议
1. 考虑添加延迟加载的超时配置
2. 可为延迟加载工具添加预加载机制
3. 考虑添加工具加载状态缓存
4. 添加延迟加载失败的回退策略
