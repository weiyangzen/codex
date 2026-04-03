# SkillsListResponse 研究文档

## 1. 场景与职责

**SkillsListResponse** 是 app-server-protocol v2 协议中用于返回技能列表查询结果的响应类型。该类型在以下场景中使用：

- **技能发现响应**：返回 `skills/list` 请求的技能查询结果
- **技能管理数据提供**：为技能管理界面提供完整的数据源
- **多工作目录结果聚合**：聚合多个工作目录的技能信息
- **错误报告**：报告技能加载过程中的错误信息

该类型作为 `skills/list` RPC 方法的响应，完成了技能查询操作的闭环反馈。

## 2. 功能点目的

该类型的核心目的是：

1. **聚合多目录结果**：将多个工作目录的技能信息整合到一个响应中
2. **分离成功与失败**：区分成功加载的技能和加载失败的技能
3. **支持分页扩展**：数据结构支持未来添加分页功能
4. **提供完整元数据**：返回技能的完整元数据，支持丰富的 UI 展示

与 `SkillsListParams` 配合使用，形成完整的技能查询请求-响应循环。

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
import type { SkillsListEntry } from "./SkillsListEntry";

export type SkillsListResponse = {
  data: Array<SkillsListEntry>,
};
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListResponse {
    pub data: Vec<SkillsListEntry>,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `data` | `Vec<SkillsListEntry>` (Array<SkillsListEntry>) | 按工作目录分组的技能列表条目 |

### 序列化特性

- 使用 camelCase 命名规范进行序列化
- 数组字段使用 `Vec<SkillsListEntry>`，TypeScript 中映射为 `Array<SkillsListEntry>`
- 采用 `data` 作为字段名，符合 API 分页响应的通用模式

### 数据结构特点

1. **扁平化设计**：使用 `data` 数组而非按目录映射，保持简单性
2. **扩展友好**：未来可添加 `next_cursor`、`total` 等分页字段
3. **自包含条目**：每个 `SkillsListEntry` 包含完整的目录上下文信息

## 4. 关键代码路径与文件引用

### 定义位置
- **主定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 第 3088-3093 行

### 协议注册
- **RPC 方法注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 295-298 行
  ```rust
  SkillsList => "skills/list" {
      params: v2::SkillsListParams,
      response: v2::SkillsListResponse,
  }
  ```

### 相关文件
- **TypeScript 类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListResponse.ts`
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/SkillsListResponse.json`
- **请求类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListParams.ts`
- **条目类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListEntry.ts`

### 使用场景
- **TUI 技能列表**: `codex-rs/tui/src/chatwidget/skills.rs` - 技能展示
- **TUI App Server**: `codex-rs/tui_app_server/src/chatwidget/skills.rs` - 并行实现
- **协议层**: `codex-rs/protocol/src/protocol.rs` - `ListSkillsResponseEvent`

### 集成测试
- **技能列表测试**: `codex-rs/app-server/tests/suite/v2/skills_list.rs`
  ```rust
  let SkillsListResponse { data } = to_response(response)?;
  assert_eq!(data.len(), 1);
  assert_eq!(data[0].cwd, cwd.path().to_path_buf());
  ```

## 5. 依赖与外部交互

### 导入依赖

| 依赖类型 | 路径 | 说明 |
|----------|------|------|
| `SkillsListEntry` | `./SkillsListEntry` | 单个工作目录的技能列表条目 |

### 类型关系图

```
SkillsListResponse
    └── data: Vec<SkillsListEntry>
            ├── cwd: PathBuf
            ├── skills: Vec<SkillMetadata>
            │       ├── name: String
            │       ├── description: String
            │       ├── path: PathBuf
            │       ├── scope: SkillScope
            │       ├── enabled: bool
            │       └── ...
            └── errors: Vec<SkillErrorInfo>
                    ├── path: PathBuf
                    └── message: String
```

### 请求-响应流程

```
客户端请求 SkillsListParams
         │
         ▼
    ┌─────────────────┐
    │  服务器处理      │
    │  1. 解析 cwds   │
    │  2. 扫描技能目录 │
    │  3. 加载技能元数据│
    │  4. 处理错误     │
    └─────────────────┘
         │
         ▼
SkillsListResponse
    └── data: [
            SkillsListEntry { cwd, skills, errors },
            SkillsListEntry { cwd, skills, errors },
            ...
        ]
         │
         ▼
    客户端处理
    1. 按 cwd 分组展示
    2. 渲染技能列表
    3. 显示错误信息
```

## 6. 风险、边界与改进建议

### 潜在风险

1. **响应大小问题**
   - 风险：大量技能或大量工作目录可能导致响应过大
   - 现状：当前无分页机制
   - 建议：考虑添加分页支持或压缩响应

2. **空响应处理**
   - 风险：客户端可能无法正确处理空 `data` 数组
   - 建议：明确定义空响应的语义（无技能 vs 错误）

3. **顺序依赖**
   - 风险：客户端可能依赖 `data` 数组的顺序
   - 建议：文档中明确是否保证顺序，或添加排序字段

### 边界情况

1. **空 data 数组**
   - 当请求的工作目录都无技能时，返回空数组

2. **全部加载失败**
   - 当所有技能都加载失败时，`skills` 为空，`errors` 包含所有错误

3. **部分成功**
   - 某些目录成功，某些失败，应分别体现在各自的 `SkillsListEntry` 中

### 改进建议

1. **添加分页支持**
   ```rust
   pub struct SkillsListResponse {
       pub data: Vec<SkillsListEntry>,
       pub next_cursor: Option<String>, // 下一页游标
       pub total: usize,                // 总条目数
   }
   ```

2. **添加响应元数据**
   ```rust
   pub struct SkillsListResponse {
       pub data: Vec<SkillsListEntry>,
       pub generated_at: i64,           // 生成时间戳
       pub cache_hit: bool,             // 是否来自缓存
       pub scan_duration_ms: u64,       // 扫描耗时
   }
   ```

3. **添加统计信息**
   ```rust
   pub struct SkillsListResponse {
       pub data: Vec<SkillsListEntry>,
       pub stats: SkillsListStats,      // 统计信息
   }
   
   pub struct SkillsListStats {
       pub total_skills: usize,
       pub total_errors: usize,
       pub by_scope: HashMap<SkillScope, usize>,
   }
   ```

4. **支持增量更新**
   ```rust
   pub struct SkillsListResponse {
       pub data: Vec<SkillsListEntry>,
       pub delta: Option<SkillsListDelta>, // 增量更新信息
   }
   ```

### 测试覆盖

- **单元测试**: 验证序列化/反序列化正确性
- **集成测试**: 
  - 验证标准技能扫描响应
  - 验证额外根目录响应
  - 验证错误处理
- **边界测试**: 空响应、大量技能、多目录等场景
