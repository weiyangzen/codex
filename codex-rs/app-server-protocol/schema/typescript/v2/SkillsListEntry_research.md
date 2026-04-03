# SkillsListEntry 研究文档

## 1. 场景与职责

**SkillsListEntry** 是 app-server-protocol v2 协议中表示单个工作目录下技能列表的结构化数据类型。该类型在以下场景中使用：

- **技能发现与展示**：向客户端展示特定工作目录下可用的技能列表
- **技能管理界面**：为技能管理 UI 提供数据源，支持启用/禁用操作
- **错误处理与诊断**：收集和报告技能加载过程中的错误信息
- **多工作目录支持**：支持为多个工作目录分别列出技能

该类型是 `SkillsListResponse` 的核心组成部分，每个 entry 对应一个工作目录的技能集合。

## 2. 功能点目的

该类型的核心目的是：

1. **按工作目录组织技能**：将技能按工作目录分组，支持不同目录下不同的技能集
2. **分离成功与失败**：区分成功加载的技能和加载失败的技能，提供完整的诊断信息
3. **支持技能元数据访问**：提供技能的完整元数据，包括名称、描述、路径、启用状态等

与 `SkillsListParams` 配合使用，实现灵活的技能查询和展示。

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
import type { SkillErrorInfo } from "./SkillErrorInfo";
import type { SkillMetadata } from "./SkillMetadata";

export type SkillsListEntry = {
  cwd: string,
  errors: Array<SkillErrorInfo>,
  skills: Array<SkillMetadata>,
};
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListEntry {
    pub cwd: PathBuf,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `cwd` | `PathBuf` (string) | 工作目录路径，这些技能关联的上下文目录 |
| `skills` | `Vec<SkillMetadata>` | 成功加载的技能元数据列表 |
| `errors` | `Vec<SkillErrorInfo>` | 技能加载错误的列表 |

### 序列化特性

- 使用 camelCase 命名规范进行序列化
- `cwd` 使用 `PathBuf` 类型，支持跨平台路径处理
- 数组字段使用 `Vec<T>`，TypeScript 中映射为 `Array<T>`

## 4. 关键代码路径与文件引用

### 定义位置
- **主定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 第 3221-3228 行

### 依赖类型定义
- **SkillMetadata**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 第 3145-3164 行
- **SkillErrorInfo**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 第 3213-3219 行

### 相关文件
- **TypeScript 类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListEntry.ts`
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/SkillsListEntry.json`
- **响应类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListResponse.ts`

### 使用场景
- **TUI 技能列表**: `codex-rs/tui/src/chatwidget/skills.rs` - 技能展示和管理
- **TUI App Server**: `codex-rs/tui_app_server/src/chatwidget/skills.rs` - 并行实现
- **核心技能模型**: `codex-rs/core/src/codex.rs` - 技能管理核心逻辑
- **协议层**: `codex-rs/protocol/src/protocol.rs` - 技能列表事件

### 集成测试
- **技能列表测试**: `codex-rs/app-server/tests/suite/v2/skills_list.rs`

## 5. 依赖与外部交互

### 导入依赖

| 依赖类型 | 路径 | 说明 |
|----------|------|------|
| `SkillMetadata` | `./SkillMetadata` | 技能元数据结构 |
| `SkillErrorInfo` | `./SkillErrorInfo` | 技能错误信息结构 |

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

### 数据流

```
技能扫描
    │
    ├── 成功加载 ──> SkillMetadata ──┐
    │                                ├──> SkillsListEntry
    ├── 加载失败 ──> SkillErrorInfo ─┘           │
                                               ▼
                                        SkillsListResponse
                                               │
                                               ▼
                                           客户端展示
```

## 6. 风险、边界与改进建议

### 潜在风险

1. **空列表处理**
   - 风险：`skills` 和 `errors` 都为空时，客户端可能无法正确处理
   - 建议：明确定义空列表的语义（表示无技能或扫描未完成）

2. **大列表性能**
   - 风险：单个目录下技能过多可能导致响应过大
   - 建议：考虑分页或流式传输支持

3. **路径一致性**
   - 风险：`cwd` 路径格式不一致可能导致客户端处理困难
   - 建议：服务器应规范化路径格式（绝对路径、统一分隔符）

### 边界情况

1. **无效工作目录**
   - 当 `cwd` 不存在或无权限访问时，应返回适当的错误信息

2. **重复技能**
   - 同一技能可能在多个作用域（User/Repo）中出现，需要去重或标记

3. **部分加载失败**
   - 某些技能加载失败不应影响其他技能的加载

### 改进建议

1. **添加统计信息**
   ```rust
   pub struct SkillsListEntry {
       pub cwd: PathBuf,
       pub skills: Vec<SkillMetadata>,
       pub errors: Vec<SkillErrorInfo>,
       pub total_count: usize, // 发现的技能总数
       pub loaded_count: usize, // 成功加载数
   }
   ```

2. **添加扫描元数据**
   ```rust
   pub struct SkillsListEntry {
       pub cwd: PathBuf,
       pub skills: Vec<SkillMetadata>,
       pub errors: Vec<SkillErrorInfo>,
       pub scanned_at: i64, // 扫描时间戳
       pub cache_hit: bool, // 是否来自缓存
   }
   ```

3. **支持作用域分组**
   ```rust
   pub struct SkillsListEntry {
       pub cwd: PathBuf,
       pub user_skills: Vec<SkillMetadata>,
       pub repo_skills: Vec<SkillMetadata>,
       pub system_skills: Vec<SkillMetadata>,
       pub errors: Vec<SkillErrorInfo>,
   }
   ```

4. **添加警告信息**
   - 除了错误，还应支持警告（如过时的技能格式）

### 测试覆盖

- **单元测试**: 验证序列化/反序列化正确性
- **集成测试**: 验证技能列表扫描流程
- **边界测试**: 空目录、无权限、大量技能等场景
- **错误测试**: 验证错误信息正确传递
