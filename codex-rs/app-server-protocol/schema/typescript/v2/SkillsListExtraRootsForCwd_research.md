# SkillsListExtraRootsForCwd 研究文档

## 1. 场景与职责

**SkillsListExtraRootsForCwd** 是 app-server-protocol v2 协议中用于指定特定工作目录的额外用户技能根目录的配置类型。该类型在以下场景中使用：

- **自定义技能路径**：允许用户为特定工作目录指定额外的技能搜索路径
- **项目特定技能**：支持项目级别的自定义技能，不放入标准技能目录
- **技能开发测试**：技能开发者可以指定开发中的技能路径进行测试
- **多技能源管理**：从多个来源（如本地开发、共享库）加载技能

该类型作为 `SkillsListParams.per_cwd_extra_user_roots` 的数组元素，支持为不同工作目录配置不同的额外技能根目录。

## 2. 功能点目的

该类型的核心目的是：

1. **按目录定制技能源**：允许为特定工作目录指定额外的技能搜索路径
2. **支持开发工作流**：技能开发者可以在不安装到标准位置的情况下测试技能
3. **灵活的技能组织**：支持从多个来源加载技能，如共享技能库、项目特定技能等
4. **隔离性保证**：额外根目录仅对指定的工作目录生效，不影响其他目录

与 `SkillsListParams` 配合使用，实现灵活的技能发现机制。

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type SkillsListExtraRootsForCwd = {
  cwd: string,
  extraUserRoots: Array<string>,
};
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListExtraRootsForCwd {
    pub cwd: PathBuf,
    pub extra_user_roots: Vec<PathBuf>,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `cwd` | `PathBuf` (string) | 目标工作目录路径 |
| `extra_user_roots` | `Vec<PathBuf>` (Array<string>) | 额外的用户技能根目录列表 |

### 序列化特性

- 使用 camelCase 命名规范（`extraUserRoots`）
- 路径字段使用 `PathBuf` 类型，支持跨平台路径处理
- 数组字段使用 `Vec<PathBuf>`，TypeScript 中映射为 `Array<string>`

### 使用示例

```typescript
const params: SkillsListParams = {
  cwds: ["/home/user/project"],
  force_reload: false,
  perCwdExtraUserRoots: [
    {
      cwd: "/home/user/project",
      extraUserRoots: [
        "/home/user/custom-skills",
        "/shared/team-skills"
      ]
    }
  ]
};
```

## 4. 关键代码路径与文件引用

### 定义位置
- **主定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 第 3080-3086 行

### 相关文件
- **TypeScript 类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListExtraRootsForCwd.ts`
- **父类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListParams.ts`

### 使用场景
- **技能列表请求**: 作为 `SkillsListParams.per_cwd_extra_user_roots` 的数组元素
- **集成测试**: `codex-rs/app-server/tests/suite/v2/skills_list.rs`

### 测试覆盖
测试文件展示了该类型的使用方式：
```rust
SkillsListExtraRootsForCwd {
    cwd: cwd.path().to_path_buf(),
    extra_user_roots: vec![extra_root.path().to_path_buf()],
}
```

## 5. 依赖与外部交互

### 导入依赖

该类型本身无外部类型依赖，但作为 `SkillsListParams` 的组成部分参与以下交互：

### 父类型关系

```
SkillsListParams
    ├── cwds: Vec<PathBuf>
    ├── force_reload: bool
    └── per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>
            └── SkillsListExtraRootsForCwd
                    ├── cwd: PathBuf
                    └── extra_user_roots: Vec<PathBuf>
```

### 数据流

```
客户端请求
    │
    ├── 标准技能目录扫描
    │
    └── 额外根目录扫描 (per_cwd_extra_user_roots)
            │
            ├── SkillsListExtraRootsForCwd
            │       ├── cwd: 匹配请求的工作目录
            │       └── extra_user_roots: 扫描这些路径
            │
            └── 合并到 SkillsListEntry
```

### 匹配逻辑

服务器在处理 `SkillsListParams` 时：
1. 遍历 `cwds` 中的每个工作目录
2. 查找 `per_cwd_extra_user_roots` 中匹配的 `cwd`
3. 将匹配的 `extra_user_roots` 纳入技能扫描范围

## 6. 风险、边界与改进建议

### 潜在风险

1. **路径验证不足**
   - 风险：相对路径可能导致安全问题或意外行为
   - 现状：测试显示服务器会拒绝相对路径并返回错误
   - 建议：客户端也应进行路径验证

2. **循环引用**
   - 风险：`extra_user_roots` 可能包含 `cwd` 本身或其子目录，导致循环
   - 建议：服务器应检测并处理循环引用

3. **性能影响**
   - 风险：过多的额外根目录可能导致扫描时间过长
   - 建议：限制额外根目录数量或提供超时机制

### 边界情况

1. **路径不存在**
   - 额外根目录路径不存在时应优雅处理，不应导致整个请求失败

2. **权限不足**
   - 无权限访问的额外根目录应被跳过，并记录警告

3. **重复路径**
   - 同一额外根目录多次出现时应去重

4. **不匹配的 cwd**
   - `per_cwd_extra_user_roots` 中的 `cwd` 不在 `cwds` 中时，应被忽略（测试已验证）

### 改进建议

1. **添加路径验证元数据**
   ```rust
   pub struct SkillsListExtraRootsForCwd {
       pub cwd: PathBuf,
       pub extra_user_roots: Vec<PathBuf>,
       pub require_absolute: bool, // 强制要求绝对路径
   }
   ```

2. **支持递归选项**
   ```rust
   pub struct ExtraRootConfig {
       pub path: PathBuf,
       pub recursive: bool, // 是否递归搜索子目录
       pub max_depth: Option<usize>, // 最大递归深度
   }
   
   pub struct SkillsListExtraRootsForCwd {
       pub cwd: PathBuf,
       pub extra_user_roots: Vec<ExtraRootConfig>,
   }
   ```

3. **支持排除模式**
   ```rust
   pub struct SkillsListExtraRootsForCwd {
       pub cwd: PathBuf,
       pub extra_user_roots: Vec<PathBuf>,
       pub exclude_patterns: Vec<String>, // 排除匹配的技能
   }
   ```

4. **添加优先级控制**
   - 允许指定额外根目录中技能的优先级，处理与标准技能的冲突

### 测试覆盖

- **单元测试**: 验证序列化/反序列化正确性
- **集成测试**: 
  - 验证额外根目录技能被正确加载
  - 验证相对路径被拒绝
  - 验证不匹配的 cwd 被忽略
- **边界测试**: 空列表、大量路径、无效路径等场景
