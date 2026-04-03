# SkillsListResponse.ts 研究文档

## 场景与职责

`SkillsListResponse.ts` 定义了技能列表查询的响应数据结构，用于 `skills/list` RPC 方法的返回。这是 Codex 技能系统查询接口的核心响应类型，包含按工作目录组织的技能列表。

## 功能点目的

该类型用于：
1. **结果返回**：返回查询的技能列表和错误信息
2. **按目录组织**：按工作目录分组返回技能
3. **错误报告**：报告每个目录加载过程中的错误
4. **批量响应**：支持一次返回多个目录的技能

## 具体技术实现

### 数据结构定义

```typescript
import type { SkillsListEntry } from "./SkillsListEntry";

export type SkillsListResponse = { 
  data: Array<SkillsListEntry>  // 按工作目录组织的技能列表
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| data | SkillsListEntry[] | 按工作目录分组的技能列表条目 |

### SkillsListEntry 结构

```typescript
type SkillsListEntry = {
  cwd: string;              // 工作目录
  skills: SkillMetadata[];  // 该目录下的技能
  errors: SkillErrorInfo[]; // 加载错误
};
```

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListResponse {
    pub data: Vec<SkillsListEntry>,
}
```

### 服务端构造逻辑

在 `codex-rs/app-server/src/codex_message_processor.rs` 中：

```rust
async fn handle_skills_list(
    &self,
    params: SkillsListParams,
) -> Result<SkillsListResponse, Error> {
    let cwds = params.get_cwds_or_default(self.session.cwd());
    let mut entries = Vec::new();
    
    for cwd in cwds {
        let entry = self.load_skills_for_cwd(&cwd, params.force_reload).await?;
        entries.push(entry);
    }
    
    Ok(SkillsListResponse { data: entries })
}

async fn load_skills_for_cwd(
    &self,
    cwd: &Path,
    force_reload: bool,
) -> Result<SkillsListEntry, Error> {
    let outcome = if force_reload {
        self.skill_manager.reload_skills(cwd).await?
    } else {
        self.skill_manager.get_skills(cwd).await?
    };
    
    Ok(SkillsListEntry {
        cwd: cwd.to_string_lossy().to_string(),
        skills: outcome.skills.into_iter().map(Into::into).collect(),
        errors: outcome.errors.into_iter().map(Into::into).collect(),
    })
}
```

### 使用场景

#### 基本响应处理

```typescript
const response = await api.skills.list({ cwds: ["/home/user/project"] });

response.data.forEach(entry => {
  console.log(`Directory: ${entry.cwd}`);
  
  // 处理技能
  entry.skills.forEach(skill => {
    console.log(`  ✓ ${skill.name}: ${skill.description}`);
  });
  
  // 处理错误
  entry.errors.forEach(error => {
    console.error(`  ✗ Error in ${error.path}: ${error.message}`);
  });
});
```

#### 多目录响应

```typescript
const response = await api.skills.list({
  cwds: ["/project1", "/project2", "/project3"]
});

// 汇总统计
const totalSkills = response.data.reduce((sum, e) => sum + e.skills.length, 0);
const totalErrors = response.data.reduce((sum, e) => sum + e.errors.length, 0);

console.log(`Total skills: ${totalSkills}`);
console.log(`Total errors: ${totalErrors}`);
```

#### 错误处理

```typescript
const response = await api.skills.list({ cwds: ["/project"] });

const entry = response.data[0];
if (entry.errors.length > 0) {
  console.warn(`Failed to load some skills in ${entry.cwd}:`);
  entry.errors.forEach(err => {
    console.warn(`  - ${err.path}: ${err.message}`);
  });
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListResponse.ts`

### Rust 协议定义
- V2 协议：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- 通用协议：`codex-rs/app-server-protocol/src/protocol/common.rs`

### 服务端实现
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 客户端消费
- TUI 应用：`codex-rs/tui_app_server/src/app.rs`
- TUI 应用服务器：`codex-rs/tui_app_server/src/app_server_session.rs`
- TUI 技能助手：`codex-rs/tui/src/chatwidget/skills.rs`
- TUI App Server 技能：`codex-rs/tui_app_server/src/chatwidget/skills.rs`

### 测试覆盖
- 技能列表测试：`codex-rs/app-server/tests/suite/v2/skills_list.rs`

### 相关类型
- SkillsListEntry：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListEntry.ts`
- SkillsListParams：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListParams.ts`

## 依赖与外部交互

### 上游依赖
- 技能管理器：加载和提供技能数据
- 文件系统：读取技能文件

### 下游消费
- UI 展示：显示技能列表和错误
- 技能选择：用户从列表中选择技能

### 响应流程

```
SkillsListParams
    ↓
技能管理器加载
    ↓
SkillsListResponse
    └── data: SkillsListEntry[]
          ├── cwd
          ├── skills: SkillMetadata[]
          └── errors: SkillErrorInfo[]
```

## 风险、边界与改进建议

### 边界情况
1. **空结果**：data 可能为空数组（无查询目录）
2. **空条目**：SkillsListEntry 的 skills 和 errors 都可能为空
3. **大量数据**：大量技能可能导致响应过大

### 潜在风险
1. **数据一致性**：响应时技能可能已被修改
2. **序列化成本**：大量技能的序列化可能耗时
3. **网络传输**：大响应可能导致网络延迟

### 改进建议
1. **分页支持**：对大量技能添加分页
2. **增量更新**：支持增量更新减少数据传输
3. **字段选择**：支持客户端指定需要的字段
4. **压缩传输**：对大响应启用压缩
5. **缓存控制**：添加缓存控制头部
6. **订阅模式**：支持订阅技能变更而非轮询
