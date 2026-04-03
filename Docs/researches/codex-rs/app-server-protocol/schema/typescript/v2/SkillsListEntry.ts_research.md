# SkillsListEntry.ts 研究文档

## 场景与职责

`SkillsListEntry.ts` 定义了技能列表条目的数据结构，用于按工作目录组织技能列表响应。这是 `skills/list` RPC 方法的响应单元，支持按目录查询和返回技能及错误信息。

## 功能点目的

该类型用于：
1. **按目录组织**：按工作目录分组返回技能
2. **错误隔离**：每个目录的错误独立报告
3. **批量查询**：支持一次查询多个工作目录
4. **状态聚合**：汇总每个目录的技能加载结果

## 具体技术实现

### 数据结构定义

```typescript
import type { SkillErrorInfo } from "./SkillErrorInfo";
import type { SkillMetadata } from "./SkillMetadata";

export type SkillsListEntry = { 
  cwd: string,                      // 工作目录路径
  skills: Array<SkillMetadata>,     // 该目录下的技能列表
  errors: Array<SkillErrorInfo>     // 加载过程中的错误
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| cwd | string | 此条目对应的工作目录路径 |
| skills | SkillMetadata[] | 在此工作目录下发现的技能列表 |
| errors | SkillErrorInfo[] | 加载此目录技能时发生的错误 |

### Rust 协议定义

在 `codex-rs/protocol/src/protocol.rs` 中：

```rust
#[derive(
    Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema, TS,
)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListEntry {
    pub cwd: String,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}
```

### 服务端构造逻辑

在 `codex-rs/app-server/src/codex_message_processor.rs` 中：

```rust
async fn handle_list_skills(
    &self,
    params: ListSkillsParams,
) -> Result<Vec<SkillsListEntry>, Error> {
    let mut entries = Vec::new();
    
    // 确定要查询的工作目录
    let cwds = if params.cwds.is_empty() {
        vec![self.session.cwd().to_path_buf()]
    } else {
        params.cwds
    };
    
    for cwd in cwds {
        let mut entry = SkillsListEntry {
            cwd: cwd.to_string_lossy().to_string(),
            skills: Vec::new(),
            errors: Vec::new(),
        };
        
        // 加载此目录的技能
        match self.skill_manager.load_skills(&cwd, params.force_reload).await {
            Ok(outcome) => {
                for skill in outcome.skills {
                    if outcome.is_skill_enabled(&skill) {
                        entry.skills.push(skill.into());
                    }
                }
                entry.errors = outcome.errors.into_iter().map(Into::into).collect();
            }
            Err(e) => {
                entry.errors.push(SkillErrorInfo {
                    path: cwd.to_string_lossy().to_string(),
                    message: e.to_string(),
                });
            }
        }
        
        entries.push(entry);
    }
    
    Ok(entries)
}
```

### 使用场景

#### 单目录查询

```typescript
const response = await api.skills.list({
  cwds: ["/home/user/project"]
});

response.data.forEach(entry => {
  console.log(`Directory: ${entry.cwd}`);
  console.log(`Skills: ${entry.skills.length}`);
  console.log(`Errors: ${entry.errors.length}`);
});
```

#### 多目录查询

```typescript
const response = await api.skills.list({
  cwds: [
    "/home/user/project1",
    "/home/user/project2",
    "/home/user/project3"
  ]
});

// 每个目录的结果独立
response.data.forEach(entry => {
  if (entry.errors.length > 0) {
    console.warn(`Errors in ${entry.cwd}:`, entry.errors);
  }
  entry.skills.forEach(skill => {
    console.log(`- ${skill.name}: ${skill.description}`);
  });
});
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListEntry.ts`

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/protocol.rs`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 核心技能实现
- 技能管理器：`codex-rs/core/src/skills/manager.rs`
- 技能模型：`codex-rs/core/src/skills/model.rs`

### 服务端集成
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 客户端消费
- TUI 应用：`codex-rs/tui_app_server/src/app.rs`
- TUI 技能助手：`codex-rs/tui/src/chatwidget/skills.rs`
- TUI App Server 技能：`codex-rs/tui_app_server/src/chatwidget/skills.rs`

### 相关类型
- SkillMetadata：`codex-rs/app-server-protocol/schema/typescript/v2/SkillMetadata.ts`
- SkillErrorInfo：`codex-rs/app-server-protocol/schema/typescript/v2/SkillErrorInfo.ts`
- SkillsListResponse：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListResponse.ts`

## 依赖与外部交互

### 上游依赖
- 技能管理器：加载和缓存技能
- 文件系统：读取技能文件

### 下游消费
- 技能列表响应：作为 SkillsListResponse.data 的数组元素
- UI 展示：按目录分组显示技能

### 响应结构

```
SkillsListResponse
  └── data: SkillsListEntry[]
        ├── cwd: string
        ├── skills: SkillMetadata[]
        └── errors: SkillErrorInfo[]
```

## 风险、边界与改进建议

### 边界情况
1. **空目录**：cwd 存在但无技能文件
2. **无效目录**：cwd 不存在或不可访问
3. **大量错误**：单个目录可能有多个错误

### 潜在风险
1. **数据量**：大量技能可能导致响应过大
2. **路径泄露**：cwd 可能包含敏感路径信息
3. **性能问题**：多个目录的查询可能影响性能

### 改进建议
1. **分页支持**：对大量技能添加分页支持
2. **过滤选项**：支持按作用域、启用状态过滤
3. **排序选项**：支持按名称、作用域排序
4. **统计信息**：添加每个目录的技能统计
5. **缓存控制**：优化缓存策略减少重复加载
6. **并行加载**：并行加载多个目录的技能
