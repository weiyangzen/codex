# discoverable.rs 研究文档

## 场景与职责

`discoverable.rs` 是 Codex 工具系统的可发现工具管理模块，负责定义和管理可动态发现和安装的工具类型。它支持两种主要的可发现工具：

1. **Connectors（连接器）**：通过 App Server 提供的应用连接器
2. **Plugins（插件）**：通过插件系统提供的功能扩展

该模块实现了工具的统一抽象，使得不同类型的可发现工具能够在 UI 和 API 层以一致的方式呈现。

## 功能点目的

### 1. 可发现工具类型枚举 (`DiscoverableToolType`)
定义可发现工具的分类：
- `Connector`：外部应用连接器（如 GitHub、Slack 等）
- `Plugin`：本地插件扩展

### 2. 可发现工具动作枚举 (`DiscoverableToolAction`)
定义对可发现工具的操作：
- `Install`：安装工具
- `Enable`：启用已安装的工具

### 3. 可发现工具枚举 (`DiscoverableTool`)
统一表示两种工具类型的包装枚举：
- `Connector(Box<AppInfo>)`：连接器工具
- `Plugin(Box<DiscoverablePluginInfo>)`：插件工具

提供统一的方法访问工具属性（ID、名称、描述、安装 URL 等）。

### 4. 插件信息结构 (`DiscoverablePluginInfo`)
封装插件的元数据：
- 基本信息：ID、名称、描述
- 能力信息：是否包含 skills、关联的 MCP 服务器、关联的应用连接器

### 5. 客户端过滤 (`filter_tool_suggest_discoverable_tools_for_client`)
根据客户端类型过滤可发现工具：
- TUI 客户端：隐藏插件类型（只显示 Connectors）
- 其他客户端：显示所有类型

## 具体技术实现

### 关键数据结构

```rust
// 可发现工具类型
#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum DiscoverableToolType {
    Connector,
    Plugin,
}

// 可发现工具动作
#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum DiscoverableToolAction {
    Install,
    Enable,
}

// 可发现工具枚举（统一抽象）
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum DiscoverableTool {
    Connector(Box<AppInfo>),
    Plugin(Box<DiscoverablePluginInfo>),
}

// 插件信息
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct DiscoverablePluginInfo {
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) description: Option<String>,
    pub(crate) has_skills: bool,
    pub(crate) mcp_server_names: Vec<String>,
    pub(crate) app_connector_ids: Vec<String>,
}
```

### 核心流程

#### 1. 工具属性访问流程
```rust
impl DiscoverableTool {
    pub(crate) fn tool_type(&self) -> DiscoverableToolType { ... }
    pub(crate) fn id(&self) -> &str { ... }
    pub(crate) fn name(&self) -> &str { ... }
    pub(crate) fn description(&self) -> Option<&str> { ... }
    pub(crate) fn install_url(&self) -> Option<&str> { ... }
}
```
通过模式匹配统一访问不同工具类型的属性。

#### 2. 类型转换流程
```rust
// AppInfo → DiscoverableTool
impl From<AppInfo> for DiscoverableTool {
    fn from(value: AppInfo) -> Self {
        Self::Connector(Box::new(value))
    }
}

// PluginCapabilitySummary → DiscoverablePluginInfo
impl From<PluginCapabilitySummary> for DiscoverablePluginInfo {
    fn from(value: PluginCapabilitySummary) -> Self {
        Self {
            id: value.config_name,
            name: value.display_name,
            description: value.description,
            has_skills: value.has_skills,
            mcp_server_names: value.mcp_server_names,
            app_connector_ids: value.app_connector_ids.into_iter()
                .map(|connector_id| connector_id.0)
                .collect(),
        }
    }
}
```

#### 3. 客户端过滤流程
```rust
pub(crate) fn filter_tool_suggest_discoverable_tools_for_client(
    discoverable_tools: Vec<DiscoverableTool>,
    app_server_client_name: Option<&str>,
) -> Vec<DiscoverableTool> {
    // TUI 客户端过滤掉 Plugin 类型
    if app_server_client_name != Some(TUI_APP_SERVER_CLIENT_NAME) {
        return discoverable_tools;
    }
    discoverable_tools.into_iter()
        .filter(|tool| !matches!(tool, DiscoverableTool::Plugin(_)))
        .collect()
}
```

### 关键代码路径

| 类型/函数 | 行号 | 职责 |
|-----------|------|------|
| `DiscoverableToolType` | 8-22 | 工具类型枚举定义 |
| `DiscoverableToolAction` | 24-38 | 工具动作枚举定义 |
| `DiscoverableTool` | 40-93 | 统一工具枚举及方法 |
| `DiscoverableTool::tool_type` | 47-52 | 获取工具类型 |
| `DiscoverableTool::id` | 54-59 | 获取工具 ID |
| `DiscoverableTool::name` | 61-66 | 获取工具名称 |
| `DiscoverableTool::description` | 68-73 | 获取工具描述 |
| `DiscoverableTool::install_url` | 75-81 | 获取安装 URL |
| `From<AppInfo>` | 83-87 | 连接器类型转换 |
| `From<DiscoverablePluginInfo>` | 89-93 | 插件类型转换 |
| `filter_tool_suggest_discoverable_tools_for_client` | 95-107 | 客户端过滤函数 |
| `DiscoverablePluginInfo` | 109-117 | 插件信息结构 |
| `From<PluginCapabilitySummary>` | 119-133 | 插件能力摘要转换 |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::plugins::PluginCapabilitySummary` | 插件能力摘要类型 |
| `codex_app_server_protocol::AppInfo` | 应用信息类型（连接器） |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `serde::Deserialize` | 反序列化支持 |
| `serde::Serialize` | 序列化支持 |

### 调用关系

```
ToolSpec 构建流程 (spec.rs)
    └── build_specs_with_discoverable_tools
        └── 接收 DiscoverableTool 列表
            └── filter_tool_suggest_discoverable_tools_for_client (客户端过滤)
                └── 从 AppInfo / PluginCapabilitySummary 转换
```

## 风险、边界与改进建议

### 已知风险

1. **客户端硬编码风险**
   - `TUI_APP_SERVER_CLIENT_NAME` 硬编码为 `"codex-tui"`
   - 如果客户端名称变更，过滤逻辑失效

2. **类型转换失败风险**
   - `PluginCapabilitySummary::app_connector_ids` 的转换假设 `connector_id.0` 存在
   - 如果结构变更可能导致编译错误

3. **内存分配风险**
   - 使用 `Box` 包装 `AppInfo` 和 `DiscoverablePluginInfo`
   - 大量工具时可能产生较多堆分配

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 空工具列表 | 过滤函数返回空 Vec |
| 未知客户端名称 | 不过滤，返回全部工具 |
| 插件无描述 | `description()` 返回 `None` |
| 连接器无安装 URL | `install_url()` 返回 `None` |
| 空 MCP 服务器列表 | `mcp_server_names` 为空 Vec |

### 改进建议

1. **客户端名称配置化**
   ```rust
   // 当前：硬编码
   const TUI_APP_SERVER_CLIENT_NAME: &str = "codex-tui";
   
   // 建议：从配置或特征获取
   trait ClientCapabilities {
       fn supports_discoverable_tool_type(&self, tool_type: DiscoverableToolType) -> bool;
   }
   ```

2. **添加更多工具元数据**
   ```rust
   pub(crate) struct DiscoverablePluginInfo {
       // 现有字段...
       pub(crate) version: Option<String>,
       pub(crate) author: Option<String>,
       pub(crate) tags: Vec<String>,
   }
   ```

3. **支持更多工具操作**
   ```rust
   pub(crate) enum DiscoverableToolAction {
       Install,
       Enable,
       Disable,  // 新增
       Uninstall, // 新增
       Update,    // 新增
   }
   ```

4. **性能优化**
   ```rust
   // 当前：Box 分配
   Connector(Box<AppInfo>),
   
   // 建议：使用 Arc 支持共享
   Connector(Arc<AppInfo>),
   ```

5. **添加验证逻辑**
   ```rust
   impl DiscoverableTool {
       pub(crate) fn validate(&self) -> Result<(), ValidationError> {
           // 验证 ID 非空、名称非空等
       }
   }
   ```

6. **改进过滤 API**
   ```rust
   // 当前：单一过滤函数
   pub(crate) fn filter_tool_suggest_discoverable_tools_for_client(...)
   
   // 建议：使用迭代器扩展
   pub(crate) trait DiscoverableToolFilter {
       fn for_client(self, client_name: &str) -> Self;
       fn by_type(self, tool_type: DiscoverableToolType) -> Self;
       fn search(self, query: &str) -> Self;
   }
   ```

### 设计决策说明

1. **为何使用 `Box` 而非 `Arc`**
   - 当前设计假设工具信息在单次请求中使用，不需要共享
   - 如果需要跨任务共享，可改为 `Arc`

2. **为何插件和连接器使用不同结构**
   - 两者来源不同（插件系统 vs App Server）
   - 属性不完全相同（插件有 `has_skills`，连接器有 `install_url`）

3. **为何 TUI 过滤插件**
   - TUI 当前只支持连接器类型的可视化安装
   - 插件安装通过其他渠道（如 CLI 命令）
