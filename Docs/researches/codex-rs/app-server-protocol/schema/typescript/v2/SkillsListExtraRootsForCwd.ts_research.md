# SkillsListExtraRootsForCwd.ts 研究文档

## 场景与职责

`SkillsListExtraRootsForCwd.ts` 定义了按工作目录指定额外技能根目录的数据结构，用于在查询技能时指定每个工作目录的额外用户级技能扫描路径。这是 Codex 技能系统的高级配置功能，支持灵活的技能发现机制。

## 功能点目的

该类型用于：
1. **额外根目录**：为特定工作目录指定额外的技能扫描路径
2. **项目特定技能**：支持项目级别的额外技能配置
3. **动态发现**：在运行时动态指定技能搜索路径
4. **灵活组织**：允许非标准位置的技能组织

## 具体技术实现

### 数据结构定义

```typescript
export type SkillsListExtraRootsForCwd = { 
  cwd: string,              // 工作目录路径
  extraUserRoots: Array<string>  // 额外的用户级技能根目录
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| cwd | string | 此配置对应的工作目录 |
| extraUserRoots | string[] | 为此工作目录额外扫描的用户级技能根目录路径 |

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListExtraRootsForCwd {
    pub cwd: String,
    pub extra_user_roots: Vec<String>,
}
```

### 在 SkillsListParams 中的使用

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListParams {
    /// 工作目录列表，为空时使用当前会话工作目录
    #[ts(optional = nullable)]
    pub cwds: Option<Vec<String>>,
    
    /// 是否绕过缓存重新扫描
    #[serde(default)]
    pub force_reload: bool,
    
    /// 每个工作目录的额外用户级技能根目录
    #[ts(optional = nullable)]
    pub per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>,
}
```

### 使用场景

#### 项目特定技能

```typescript
const params: SkillsListParams = {
  cwds: ["/home/user/project"],
  perCwdExtraUserRoots: [
    {
      cwd: "/home/user/project",
      extraUserRoots: [
        "/home/user/project/.codex/custom-skills",
        "/home/user/shared-team-skills"
      ]
    }
  ]
};

const response = await api.skills.list(params);
```

### 服务端处理逻辑

```rust
async fn load_skills_with_extra_roots(
    &self,
    cwd: &Path,
    extra_roots: &[PathBuf],
) -> SkillLoadOutcome {
    let mut all_roots = Vec::new();
    
    // 标准技能根目录
    all_roots.extend(get_standard_skill_roots(cwd));
    
    // 额外的用户级根目录
    for root in extra_roots {
        if root.exists() {
            all_roots.push(root.clone());
        }
    }
    
    // 加载所有根目录的技能
    self.skill_loader.load_from_roots(&all_roots).await
}
```

### 优先级处理

额外根目录的技能优先级：
1. 标准系统技能（最低）
2. 标准管理员技能
3. 标准用户技能
4. 额外用户根目录技能（最高）

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListExtraRootsForCwd.ts`

### Rust 协议定义
- V2 协议：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 服务端实现
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 测试覆盖
- 技能列表测试：`codex-rs/app-server/tests/suite/v2/skills_list.rs`

### 相关类型
- SkillsListParams：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListParams.ts`

## 依赖与外部交互

### 上游依赖
- 客户端配置：从客户端配置或用户输入获取额外根目录
- 文件系统：验证额外根目录的存在性

### 下游消费
- 技能加载器：将额外根目录纳入技能扫描

### 配置层级

```
标准技能根目录
    ↓
额外用户根目录 (SkillsListExtraRootsForCwd)
    ↓
合并扫描
    ↓
SkillsListEntry
```

## 风险、边界与改进建议

### 边界情况
1. **无效路径**：extraUserRoots 中的路径可能不存在
2. **重复路径**：可能与标准根目录重复
3. **循环引用**：额外根目录可能指向包含 cwd 的父目录

### 潜在风险
1. **安全风险**：额外根目录可能包含恶意技能
2. **性能影响**：大量额外根目录可能影响加载性能
3. **路径遍历**：需要防范路径遍历攻击

### 改进建议
1. **路径验证**：验证额外根目录的合法性和安全性
2. **去重处理**：自动去除重复的根目录
3. **缓存策略**：为额外根目录提供独立的缓存控制
4. **权限检查**：验证用户对额外根目录的访问权限
5. **递归限制**：限制额外根目录的嵌套深度
6. **配置持久化**：支持将常用额外根目录保存到配置
