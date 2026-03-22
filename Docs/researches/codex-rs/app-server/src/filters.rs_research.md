# filters.rs 研究文档

## 场景与职责

`filters.rs` 实现了线程来源过滤逻辑，用于处理客户端对线程列表的筛选需求。该模块负责将协议层的 `ThreadSourceKind` 过滤器转换为 Core 层的 `SessionSource` 过滤器，并处理需要后过滤的特殊来源类型（如子代理相关来源）。

## 功能点目的

### 1. 来源过滤器计算
根据客户端提供的 `source_kinds` 参数，计算：
- 允许的来源列表（用于 Core 层查询）
- 后过滤器（用于 App Server 层二次过滤）

### 2. 来源匹配
提供 `source_kind_matches` 函数，用于判断给定的 Core 层 `SessionSource` 是否匹配客户端指定的过滤器。

## 具体技术实现

### 核心函数

#### compute_source_filters
```rust
pub(crate) fn compute_source_filters(
    source_kinds: Option<Vec<ThreadSourceKind>>,
) -> (Vec<CoreSessionSource>, Option<Vec<ThreadSourceKind>>)
```

**逻辑流程**:
1. 如果 `source_kinds` 为 `None`，返回默认的交互式来源 (`INTERACTIVE_SESSION_SOURCES`)
2. 如果 `source_kinds` 为空，同样返回默认交互式来源
3. 检查是否需要后过滤（包含子代理相关来源）
4. 如需要后过滤，返回空允许列表和原始过滤器
5. 否则，将 `ThreadSourceKind` 映射为 `CoreSessionSource`

**需要后过滤的来源类型**:
- `Exec`: 执行命令来源
- `AppServer`: App Server 来源
- `SubAgent`: 子代理（通用）
- `SubAgentReview`: 子代理审查
- `SubAgentCompact`: 子代理压缩
- `SubAgentThreadSpawn`: 子代理线程派生
- `SubAgentOther`: 其他子代理
- `Unknown`: 未知来源

#### source_kind_matches
```rust
pub(crate) fn source_kind_matches(
    source: &CoreSessionSource,
    filter: &[ThreadSourceKind],
) -> bool
```

**匹配逻辑**:
| ThreadSourceKind | CoreSessionSource 匹配条件 |
|------------------|---------------------------|
| Cli | `CoreSessionSource::Cli` |
| VsCode | `CoreSessionSource::VSCode` |
| Exec | `CoreSessionSource::Exec` |
| AppServer | `CoreSessionSource::Mcp` |
| SubAgent | `CoreSessionSource::SubAgent(_)` |
| SubAgentReview | `CoreSessionSource::SubAgent(CoreSubAgentSource::Review)` |
| SubAgentCompact | `CoreSessionSource::SubAgent(CoreSubAgentSource::Compact)` |
| SubAgentThreadSpawn | `CoreSessionSource::SubAgent(CoreSubAgentSource::ThreadSpawn { .. })` |
| SubAgentOther | `CoreSessionSource::SubAgent(CoreSubAgentSource::Other(_))` |
| Unknown | `CoreSessionSource::Unknown` |

### 交互式来源常量
```rust
// 来自 codex_core::INTERACTIVE_SESSION_SOURCES
const INTERACTIVE_SESSION_SOURCES: &[CoreSessionSource] = &[
    CoreSessionSource::Cli,
    CoreSessionSource::VSCode,
];
```

## 关键代码路径与文件引用

### 定义位置
- `codex-rs/app-server/src/filters.rs`

### 类型定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`: `ThreadSourceKind`
- `codex-rs/protocol/src/protocol.rs`: `SessionSource`, `SubAgentSource`
- `codex-rs/core/src/lib.rs`: `INTERACTIVE_SESSION_SOURCES`

### 使用位置
- `codex-rs/app-server/src/codex_message_processor.rs`: 调用 `compute_source_filters` 和 `source_kind_matches`
- `codex-rs/network-proxy/src/network_policy.rs`: 使用过滤器相关逻辑

### 测试覆盖
模块包含完整的单元测试，覆盖：
- 默认过滤器行为
- 空列表处理
- 纯交互式来源过滤
- 子代理变体后过滤
- 子代理变体匹配区分

## 依赖与外部交互

### 外部依赖
```rust
use codex_app_server_protocol::ThreadSourceKind;
use codex_core::INTERACTIVE_SESSION_SOURCES;
use codex_protocol::protocol::SessionSource as CoreSessionSource;
use codex_protocol::protocol::SubAgentSource as CoreSubAgentSource;
```

### 调用时序
1. 客户端发送 `thread/list` 请求，携带 `source_kinds` 参数
2. `CodexMessageProcessor` 调用 `compute_source_filters`
3. 使用返回的允许列表查询 Core 层
4. 如有后过滤器，对结果进行额外过滤
5. 返回过滤后的线程列表

## 风险、边界与改进建议

### 当前风险
1. **后过滤性能**: 当需要后过滤时，Core 层查询范围扩大，可能返回大量数据
2. **来源映射复杂**: 子代理来源的嵌套结构增加了匹配逻辑的复杂度
3. **硬编码交互式来源**: `INTERACTIVE_SESSION_SOURCES` 在 Core 层定义，修改需要跨 crate 协调

### 边界情况
1. **空过滤器**: 空 `source_kinds` 视为"所有交互式来源"，而非"无来源"
2. **未知来源匹配**: `Unknown` 来源类型仅在显式指定时匹配
3. **子代理层级**: `SubAgentThreadSpawn` 包含父线程 ID 和深度信息，但过滤时不考虑层级

### 改进建议
1. **优化后过滤**: 考虑将更多过滤逻辑下推到 Core 层，减少数据传输
2. **添加来源统计**: 记录各来源类型的查询频率，优化索引策略
3. **统一来源模型**: 考虑合并 `ThreadSourceKind` 和 `SessionSource`，减少转换开销
4. **支持排除过滤**: 当前仅支持包含过滤，可考虑添加排除模式（如 `exclude_sources`）
5. **缓存过滤器结果**: 对于高频查询模式，可缓存过滤器计算结果
