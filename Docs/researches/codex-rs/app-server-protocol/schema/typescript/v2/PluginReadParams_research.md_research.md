# PluginReadParams 研究文档

## 场景与职责

`PluginReadParams` 是 app-server v2 API 中 ClientRequest 的 `plugin/read` 方法的参数类型。它用于精确读取单个插件的完整详情信息，通过指定市场路径和插件名称来定位目标插件。

该类型是 Codex 插件管理系统的精确查询接口，与 `PluginListParams` 的批量发现形成互补，为客户端提供获取插件完整元数据的能力。

## 功能点目的

### 核心功能
1. **精确定位插件**：通过 `marketplace_path` 和 `plugin_name` 唯一标识一个插件
2. **获取完整详情**：返回插件的完整信息（`PluginDetail`），包括技能、应用、MCP 服务器等
3. **支持安装决策**：为安装前的详细审查提供数据

### 使用场景
- 插件详情页面加载
- 安装前的详细审查
- 获取插件包含的技能和应用列表

## 具体技术实现

### 数据结构定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (lines 3119-3126)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginReadParams {
    /// 市场路径（从 PluginListResponse 获取）
    pub marketplace_path: AbsolutePathBuf,
    /// 插件名称
    pub plugin_name: String,
}
```

### 生成的 TypeScript 类型

```typescript
// schema/typescript/v2/PluginReadParams.ts
import type { AbsolutePathBuf } from "../AbsolutePathBuf";

export type PluginReadParams = { 
    marketplacePath: AbsolutePathBuf, 
    pluginName: string, 
};
```

### 对应的响应类型

```rust
// PluginReadResponse (lines 3127-3132)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginReadResponse {
    pub plugin: PluginDetail,
}

// PluginDetail (lines 3286-3298)
pub struct PluginDetail {
    pub marketplace_name: String,
    pub marketplace_path: AbsolutePathBuf,
    pub summary: PluginSummary,        // 包含 PluginInterface
    pub description: Option<String>,   // 详细描述（Markdown）
    pub skills: Vec<SkillSummary>,     // 包含的技能
    pub apps: Vec<AppSummary>,         // 包含的应用
    pub mcp_servers: Vec<String>,      // 包含的 MCP 服务器
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行 3119-3126：`PluginReadParams` 结构体
  - 行 3127-3132：`PluginReadResponse` 响应类型

### 协议注册
```rust
// codex-rs/app-server-protocol/src/protocol/common.rs (lines 303-306)
client_request_definitions! {
    PluginRead => "plugin/read" {
        params: v2::PluginReadParams,
        response: v2::PluginReadResponse,
    },
}
```

### 与 PluginListParams 的对比
```rust
// PluginListParams - 批量发现
pub struct PluginListParams {
    pub cwds: Option<Vec<AbsolutePathBuf>>,  // 可选，多目录
    pub force_remote_sync: bool,
}

// PluginReadParams - 精确读取
pub struct PluginReadParams {
    pub marketplace_path: AbsolutePathBuf,   // 必需，单一路径
    pub plugin_name: String,                 // 必需，插件名称
}
```

### 相关类型定义
| 类型 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `PluginReadResponse` | v2.rs | 3127-3132 | 对应的响应类型 |
| `PluginDetail` | v2.rs | 3286-3298 | 插件详情 |
| `PluginSummary` | v2.rs | 3272-3284 | 插件摘要 |
| `SkillSummary` | v2.rs | 3299-3309 | 技能摘要 |
| `AppSummary` | v2.rs | 2027-2047 | 应用摘要 |

### 生成的 TypeScript 文件
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginReadParams.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginReadResponse.ts`（配对）

## 依赖与外部交互

### 内部依赖
1. **ts-rs**：TypeScript 类型导出
2. **schemars**：JSON Schema 生成
3. **serde**：驼峰命名序列化
4. **codex_utils_absolute_path**：`AbsolutePathBuf` 类型

### 典型使用流程
```
1. 调用 plugin/list 获取市场列表
    ↓
PluginListResponse {
    marketplaces: [
        PluginMarketplaceEntry {
            name: "official",
            path: "/path/to/official",  // ← 获取此路径
            plugins: [
                PluginSummary { name: "github-plugin", ... },  // ← 获取此名称
                ...
            ]
        }
    ]
}
    ↓
2. 调用 plugin/read 获取详情
    ↓
PluginReadParams {
    marketplace_path: "/path/to/official",
    plugin_name: "github-plugin",
}
    ↓
PluginReadResponse {
    plugin: PluginDetail {
        summary: ...,      // 基本信息
        skills: [...],     // 包含的技能
        apps: [...],       // 包含的应用
        mcp_servers: [...], // 包含的 MCP 服务器
    }
}
```

## 风险、边界与改进建议

### 潜在风险
1. **路径有效性**：`marketplace_path` 可能指向不存在或已删除的市场
2. **插件不存在**：`plugin_name` 可能不在指定市场中
3. **路径遍历**：恶意构造的路径可能尝试访问系统目录

### 边界情况
1. **大小写敏感**：`plugin_name` 的大小写处理（文件系统可能大小写不敏感）
2. **特殊字符**：`plugin_name` 包含特殊字符时的处理
3. **并发修改**：读取时插件被删除或修改

### 改进建议
1. **添加验证**：
   ```rust
   impl PluginReadParams {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.plugin_name.is_empty() {
               return Err(ValidationError::EmptyPluginName);
           }
           // 验证 marketplace_path 是允许的目录之一
           if !is_allowed_marketplace_path(&self.marketplace_path) {
               return Err(ValidationError::InvalidMarketplacePath);
           }
           Ok(())
       }
   }
   ```

2. **支持插件 ID**：
   ```rust
   pub struct PluginReadParams {
       // 现有字段
       pub marketplace_path: AbsolutePathBuf,
       pub plugin_name: String,
       // 新增：支持通过 ID 读取
       pub plugin_id: Option<String>,
   }
   ```

3. **添加版本参数**：
   ```rust
   pub struct PluginReadParams {
       // ... 现有字段
       pub version: Option<String>,  // 读取特定版本
   }
   ```

4. **路径标准化**：
   ```rust
   pub fn sanitize(&mut self) {
       self.marketplace_path = self.marketplace_path.canonicalize()
           .unwrap_or_else(|_| self.marketplace_path.clone());
   }
   ```

### 测试覆盖
建议测试场景：
1. 正常读取（有效路径和插件名）
2. 无效路径处理
3. 不存在的插件名处理
4. 特殊字符在插件名中的处理
5. 并发删除场景

### API 稳定性
- 此类型属于稳定 API（无 `#[experimental]` 标记）
- 作为 ClientRequest 的参数类型，变更会影响客户端
- 建议通过添加可选字段来扩展

### 与 PluginInstallParams 的关系
```rust
// PluginInstallParams 使用相同定位方式
pub struct PluginInstallParams {
    pub marketplace_path: AbsolutePathBuf,
    pub plugin_name: String,
    pub force_remote_sync: bool,
}
```
两者使用相同的定位方式，确保 UI 可以从详情页直接触发安装。
