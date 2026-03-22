# experimental_feature_list.rs 研究文档

## 场景与职责

`experimental_feature_list.rs` 是 Codex App Server v2 API 的集成测试文件，专注于**实验性功能列表（Experimental Feature List）**功能的验证。该功能允许客户端查询 Codex 支持的所有功能标志（Feature Flags）及其当前状态，包括功能的生命周期阶段（如 Beta、Stable、Deprecated 等）和启用状态。

该测试文件的核心职责包括：
1. 验证 `experimentalFeature/list` API 返回正确的功能元数据
2. 验证功能生命周期阶段（Stage）正确映射
3. 验证功能的启用状态与配置一致

## 功能点目的

### 1. 功能列表查询 (`experimental_feature_list_returns_feature_metadata_with_stage`)
- **目的**：验证 `experimentalFeature/list` API 返回完整的功能元数据
- **业务价值**：
  - 客户端可以展示可用的实验性功能给用户
  - 支持功能发现界面（如设置中的实验性功能面板）
  - 帮助用户了解功能的成熟度和风险
- **关键验证点**：
  - 功能名称（`name`）正确
  - 生命周期阶段（`stage`）正确映射（Beta、UnderDevelopment、Stable、Deprecated、Removed）
  - Beta 功能包含显示名称、描述和公告文本
  - 启用状态（`enabled`）与配置一致
  - 默认启用状态（`default_enabled`）正确

## 具体技术实现

### 核心数据结构

#### ExperimentalFeature（协议定义）
```rust
pub struct ExperimentalFeature {
    /// 配置和 CLI 中使用的稳定键名
    pub name: String,
    /// 功能标志的生命周期阶段
    pub stage: ExperimentalFeatureStage,
    /// 用户界面显示名称（仅 Beta 阶段有）
    pub display_name: Option<String>,
    /// 功能描述（仅 Beta 阶段有）
    pub description: Option<String>,
    /// 公告文本（仅 Beta 阶段有）
    pub announcement: Option<String>,
    /// 当前配置中是否启用
    pub enabled: bool,
    /// 默认是否启用
    pub default_enabled: bool,
}
```

#### ExperimentalFeatureStage（生命周期阶段枚举）
```rust
pub enum ExperimentalFeatureStage {
    Beta,              // 可供用户测试和反馈
    UnderDevelopment,  // 正在开发中，不适合广泛使用
    Stable,            // 生产就绪
    Deprecated,        // 已弃用，应避免使用
    Removed,           // 仅保留向后兼容
}
```

#### FeatureSpec（核心层定义）
```rust
pub struct FeatureSpec {
    pub id: Feature,           // 功能标识符
    pub key: &'static str,     // 配置键名
    pub stage: Stage,          // 生命周期阶段
    pub default_enabled: bool, // 默认启用状态
}

pub enum Stage {
    Experimental {
        name: &'static str,              // 显示名称
        menu_description: &'static str,  // 菜单描述
        announcement: &'static str,      // 公告文本
    },
    UnderDevelopment,
    Stable,
    Deprecated,
    Removed,
}
```

### 阶段映射逻辑

测试中的核心映射逻辑：
```rust
let (stage, display_name, description, announcement) = match spec.stage {
    Stage::Experimental { name, menu_description, announcement } => {
        (ExperimentalFeatureStage::Beta, Some(name), Some(menu_description), Some(announcement))
    }
    Stage::UnderDevelopment => (ExperimentalFeatureStage::UnderDevelopment, None, None, None),
    Stage::Stable => (ExperimentalFeatureStage::Stable, None, None, None),
    Stage::Deprecated => (ExperimentalFeatureStage::Deprecated, None, None, None),
    Stage::Removed => (ExperimentalFeatureStage::Removed, None, None, None),
};
```

### API 请求/响应

#### ExperimentalFeatureListParams（请求参数）
```rust
pub struct ExperimentalFeatureListParams {
    #[ts(optional = nullable)]
    pub cursor: Option<String>,  // 分页游标
    #[ts(optional = nullable)]
    pub limit: Option<u32>,      // 页面大小
}
```

#### ExperimentalFeatureListResponse（响应）
```rust
pub struct ExperimentalFeatureListResponse {
    pub data: Vec<ExperimentalFeature>,
    pub next_cursor: Option<String>,  // 下一页游标
}
```

### 测试流程

```
1. 创建临时 codex_home 目录
2. 使用 ConfigBuilder 构建配置
3. 初始化 MCP 进程
4. 发送 experimentalFeature/list 请求
5. 读取响应
6. 构建预期结果（基于 FEATURES 常量）
7. 比较实际结果和预期结果
```

## 关键代码路径与文件引用

### 协议定义
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `ExperimentalFeature`, `ExperimentalFeatureStage`, `ExperimentalFeatureListParams`, `ExperimentalFeatureListResponse` 定义 |

### 核心功能定义
| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/features.rs` | `FeatureSpec`, `Stage` 定义（推测路径，实际可能在 core 根目录） |
| `codex-rs/core/src/features/legacy.rs` | 遗留功能定义 |

### API 实现
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/message_processor.rs` | `experimentalFeature/list` 请求处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 功能列表查询实现 |

### UI 集成
| 文件 | 说明 |
|------|------|
| `codex-rs/tui/src/bottom_pane/experimental_features_view.rs` | TUI 实验性功能视图 |
| `codex-rs/tui_app_server/src/bottom_pane/experimental_features_view.rs` | TUI App Server 实验性功能视图 |
| `codex-rs/tui/src/chatwidget.rs` | 聊天组件中的功能集成 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI App Server 聊天组件 |

## 依赖与外部交互

### 内部依赖
```rust
use codex_app_server_protocol::{
    ExperimentalFeature,
    ExperimentalFeatureListParams,
    ExperimentalFeatureListResponse,
    ExperimentalFeatureStage,
    JSONRPCResponse,
    RequestId,
};
use codex_core::config::ConfigBuilder;
use codex_core::features::FEATURES;  // 功能规格常量
use codex_core::features::Stage;      // 生命周期阶段枚举
```

### 关键常量
- `FEATURES`：包含所有功能规格的静态数组
- `DEFAULT_TIMEOUT = Duration::from_secs(10)`：测试超时时间

### 测试基础设施
- **ConfigBuilder**：构建测试配置
- **McpProcess**：MCP 测试客户端
- **TempDir**：临时目录管理

## 风险、边界与改进建议

### 风险点

1. **功能列表硬编码**
   - 测试依赖 `FEATURES` 常量，如果功能列表变更，测试需要更新
   - **风险**：新功能添加时可能忘记更新预期结果
   - **建议**：考虑使用快照测试（insta）自动更新预期结果

2. **阶段映射复杂性**
   - `Stage::Experimental` 需要提取嵌套字段，其他阶段返回 None
   - **风险**：映射逻辑可能出错
   - **建议**：为每个阶段添加独立的测试用例

3. **配置状态依赖**
   - 测试使用 `config.features.enabled(spec.id)` 检查启用状态
   - **风险**：如果默认配置变更，测试可能失败
   - **建议**：在测试中显式设置功能状态

### 边界情况

1. **空功能列表**
   - 当前测试假设 `FEATURES` 不为空
   - **建议**：添加空列表边界测试

2. **分页处理**
   - 测试使用默认参数（无 cursor，无 limit）
   - **建议**：添加分页测试用例

3. **功能状态变更**
   - 测试在运行时功能状态可能变化
   - **建议**：使用固定的测试配置

### 改进建议

1. **快照测试**
   - 使用 `insta` 进行快照测试
   - 自动捕获和更新功能列表输出
   - 便于审查功能变更

2. **更全面的覆盖**
   - 为每个生命周期阶段添加独立测试
   - 测试功能启用/禁用的边界
   - 测试分页逻辑

3. **性能测试**
   - 如果功能列表很长，查询性能可能成问题
   - **建议**：添加性能基准测试

4. **文档和示例**
   - 提供功能标志的使用文档
   - 说明每个功能的用途和风险

5. **遥测集成**
   - 记录功能使用情况
   - 帮助决定功能生命周期转换（如从 Beta 到 Stable）

6. **API 版本控制**
   - 考虑在响应中添加 API 版本信息
   - 便于客户端处理协议变更
