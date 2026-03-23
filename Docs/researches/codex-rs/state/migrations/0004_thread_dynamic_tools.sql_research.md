# 0004_thread_dynamic_tools.sql 研究文档

## 场景与职责

本迁移创建 `thread_dynamic_tools` 表，用于存储每个会话（thread）的动态工具（Dynamic Tools）配置。动态工具是 MCP（Model Context Protocol）工具，在会话启动时定义，并在整个会话期间保持不变。

## 功能点目的

### 1. thread_dynamic_tools 表结构
创建包含以下字段的表：

| 字段 | 类型 | 说明 |
|------|------|------|
| `thread_id` | TEXT NOT NULL | 关联的会话ID |
| `position` | INTEGER NOT NULL | 工具在列表中的位置（顺序） |
| `name` | TEXT NOT NULL | 工具名称 |
| `description` | TEXT NOT NULL | 工具描述 |
| `input_schema` | TEXT NOT NULL | JSON Schema 格式的输入参数定义 |

### 2. 主键设计
- **复合主键**: `(thread_id, position)`
- **外键约束**: `thread_id` 引用 `threads(id)`，级联删除

### 3. 索引设计
- `idx_thread_dynamic_tools_thread`: 加速按会话查询工具

## 具体技术实现

### 关键流程
1. **工具持久化**: 会话启动时，将动态工具配置写入此表
2. **工具加载**: 会话恢复时，从此表读取工具配置
3. **顺序保持**: `position` 字段确保工具顺序与定义时一致

### 代码映射
在 `codex-rs/state/src/runtime/threads.rs` 中：
```rust
pub async fn persist_dynamic_tools(
    &self,
    thread_id: ThreadId,
    tools: Option<&[DynamicToolSpec]>,
) -> anyhow::Result<()> {
    // 使用 ON CONFLICT(thread_id, position) DO NOTHING
    // 确保工具只写入一次
}
```

在 `codex-rs/state/src/runtime/threads.rs` 中查询：
```rust
pub async fn get_dynamic_tools(
    &self,
    thread_id: ThreadId,
) -> anyhow::Result<Option<Vec<DynamicToolSpec>>> {
    // 按 position ASC 排序查询
}
```

## 关键代码路径与文件引用

### 工具持久化
- `codex-rs/state/src/runtime/threads.rs`:
  - `persist_dynamic_tools()`: 首次写入工具配置
  - `apply_rollout_items()`: 从 rollout 提取并持久化工具

### 工具提取
- `codex-rs/state/src/runtime/threads.rs`:
  - `extract_dynamic_tools()`: 从 `RolloutItem::SessionMeta` 提取工具

### 模型定义
- `codex-protocol/src/dynamic_tools.rs`: `DynamicToolSpec` 结构体定义

## 依赖与外部交互

### 上游依赖
- `0001_threads.sql`: 依赖 `threads` 表作为外键引用

### 下游依赖
- `0019_thread_dynamic_tools_defer_loading.sql`: 添加 `defer_loading` 字段

### 应用层交互
- `codex-rs/core/src/mcp_client.rs`: 加载和使用动态工具
- `codex-rs/tui/src/app.rs`: 会话启动时配置工具

## 风险、边界与改进建议

### 风险
1. **JSON Schema 有效性**: `input_schema` 存储为 TEXT，不验证 JSON 有效性
2. **工具重复**: 使用 `ON CONFLICT DO NOTHING`，同名工具在不同位置可能重复

### 边界情况
1. **工具更新**: 设计为只写入一次，不支持会话中更新工具
2. **空工具列表**: 应用层需处理空列表情况
3. **级联删除**: 删除会话时自动删除关联工具

### 改进建议
1. 已实施：`0019` 迁移添加了 `defer_loading` 支持延迟加载
2. 考虑添加工具版本字段（如果工具定义会演进）
3. 可为 `name` 字段添加唯一约束（如果同一会话中工具名必须唯一）
