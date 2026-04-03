# SkillErrorInfo.ts 研究文档

## 场景与职责

`SkillErrorInfo.ts` 定义了技能错误信息的数据结构，用于在技能加载或执行过程中报告错误。这是 Codex 技能系统错误处理机制的一部分，帮助用户和开发者诊断技能相关的问题。

## 功能点目的

该类型用于：
1. **错误报告**：在技能加载失败时提供详细的错误信息
2. **问题定位**：通过路径信息帮助定位问题技能文件
3. **用户反馈**：向用户展示友好的错误描述
4. **调试支持**：为开发者提供调试信息

## 具体技术实现

### 数据结构定义

```typescript
export type SkillErrorInfo = { 
  path: string,     // 发生错误的技能文件路径
  message: string   // 错误描述信息
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| path | string | 发生错误的技能文件或目录的路径 |
| message | string | 描述错误的可读消息 |

### Rust 协议定义

在 `codex-rs/protocol/src/protocol.rs` 中：

```rust
#[derive(
    Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema, TS,
)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillErrorInfo {
    pub path: PathBuf,
    pub message: String,
}
```

### 核心技能错误类型

在 `codex-rs/core/src/skills/model.rs` 中：

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillError {
    pub path: PathBuf,
    pub message: String,
}

impl From<SkillError> for SkillErrorInfo {
    fn from(error: SkillError) -> Self {
        Self {
            path: error.path,
            message: error.message,
        }
    }
}
```

### 技能加载结果

```rust
#[derive(Debug, Clone, Default)]
pub struct SkillLoadOutcome {
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillError>,
    pub disabled_paths: HashSet<PathBuf>,
    // ...
}
```

### 错误生成场景

#### 解析错误

```rust
// skills/loader.rs
fn parse_skill_file(path: &Path) -> Result<SkillMetadata, SkillError> {
    let content = fs::read_to_string(path)
        .map_err(|e| SkillError {
            path: path.to_path_buf(),
            message: format!("Failed to read skill file: {e}"),
        })?;
    
    parse_skill_content(&content)
        .map_err(|e| SkillError {
            path: path.to_path_buf(),
            message: format!("Failed to parse skill: {e}"),
        })
}
```

#### 验证错误

```rust
fn validate_skill(skill: &SkillMetadata) -> Result<(), SkillError> {
    if skill.name.is_empty() {
        return Err(SkillError {
            path: skill.path_to_skills_md.clone(),
            message: "Skill name cannot be empty".to_string(),
        });
    }
    // ...
}
```

### 在 SkillsListEntry 中的使用

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListEntry {
    pub cwd: String,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SkillErrorInfo.ts`

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/protocol.rs`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 核心技能实现
- 技能模型：`codex-rs/core/src/skills/model.rs`
- 技能加载器：`codex-rs/core/src/skills/loader.rs`
- 加载器测试：`codex-rs/core/src/skills/loader_tests.rs`

### 服务端集成
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 相关类型
- SkillsListEntry：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListEntry.ts`

## 依赖与外部交互

### 上游依赖
- 技能加载：在加载过程中检测和报告错误
- 文件系统：读取技能文件时可能产生 I/O 错误
- 解析器：解析 SKILL.md 或 SKILL.json 时可能产生语法错误

### 下游消费
- 技能列表响应：作为 SkillsListEntry.errors 的一部分返回
- UI 展示：向用户显示加载失败的技能
- 日志记录：记录错误用于调试

### 错误类型分布

| 错误类型 | 示例 | 处理方式 |
|---------|------|---------|
| I/O 错误 | 文件不存在 | 显示路径和系统错误 |
| 解析错误 | YAML 语法错误 | 显示行号和错误详情 |
| 验证错误 | 缺少必填字段 | 显示字段名和期望格式 |
| 依赖错误 | 依赖的工具未找到 | 显示依赖名和安装建议 |

## 风险、边界与改进建议

### 边界情况
1. **路径长度**：非常长的路径可能在 UI 中显示不完整
2. **多错误**：一个技能文件可能有多个错误
3. **级联错误**：一个错误可能导致后续错误

### 潜在风险
1. **信息泄露**：错误消息可能包含敏感路径信息
2. **用户体验**：技术错误消息对普通用户不友好
3. **错误泛滥**：大量错误可能淹没有效信息

### 改进建议
1. **错误分级**：添加错误级别（警告/错误/严重）
2. **错误代码**：添加机器可读的错误代码
3. **修复建议**：在错误消息中包含修复建议
4. **错误聚合**：合并相关错误，避免重复报告
5. **本地化**：支持多语言错误消息
6. **错误历史**：记录错误历史，支持查看已修复的错误
