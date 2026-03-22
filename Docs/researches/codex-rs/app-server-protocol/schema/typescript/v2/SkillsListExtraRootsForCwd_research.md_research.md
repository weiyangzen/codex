# SkillsListExtraRootsForCwd 研究文档

## 场景与职责

`SkillsListExtraRootsForCwd` 是 Codex App Server Protocol v2 API 中 `skills/list` 方法的辅助类型，用于支持按工作目录指定额外的用户级技能扫描根目录。该类型实现了**精细化技能发现控制**，允许客户端为特定工作目录指定额外的技能搜索路径。

### 使用场景

1. **项目特定技能**：为特定项目目录指定额外的技能库位置
2. **团队共享技能**：允许从团队共享目录加载技能，而不影响全局配置
3. **临时技能加载**：在特定会话中临时加载位于非标准位置的技能
4. **多工作区支持**：VS Code 等多工作区客户端为每个文件夹指定不同的额外技能路径

## 功能点目的

### 核心功能

- **按目录定制技能扫描**：允许为每个工作目录指定不同的额外技能根目录
- **用户级作用域**：额外根目录中的技能被识别为 `user` 作用域，享有相应的权限和优先级
- **灵活的技能组织**：突破标准技能目录结构的限制，支持自定义技能存放位置

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `cwd` | `string` | 工作目录路径，指定该配置适用的目标目录 |
| `extraUserRoots` | `string[]` | 额外的用户级技能根目录列表，必须是绝对路径 |

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3080-3086
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListExtraRootsForCwd {
    pub cwd: PathBuf,
    pub extra_user_roots: Vec<PathBuf>,
}
```

### 在 SkillsListParams 中的使用

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3065-3078
pub struct SkillsListParams {
    /// When empty, defaults to the current session working directory.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub cwds: Vec<PathBuf>,

    /// When true, bypass the skills cache and re-scan skills from disk.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_reload: bool,

    /// Optional per-cwd extra roots to scan as user-scoped skills.
    #[serde(default)]
    #[ts(optional = nullable)]
    pub per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>,
}
```

### 关键处理流程

1. **请求处理与验证**：`CodexMessageProcessor::skills_list()`
   ```rust
   // codex-rs/app-server/src/codex_message_processor.rs:5385-5440
   async fn skills_list(&self, request_id: ConnectionRequestId, params: SkillsListParams) {
       let SkillsListParams { cwds, force_reload, per_cwd_extra_user_roots } = params;
       let cwds = if cwds.is_empty() { vec![self.config.cwd.clone()] } else { cwds };
       let cwd_set: HashSet<PathBuf> = cwds.iter().cloned().collect();

       let mut extra_roots_by_cwd: HashMap<PathBuf, Vec<PathBuf>> = HashMap::new();
       for entry in per_cwd_extra_user_roots.unwrap_or_default() {
           // 验证：忽略不在请求 cwd 列表中的条目
           if !cwd_set.contains(&entry.cwd) {
               warn!(
                   cwd = %entry.cwd.display(),
                   "ignoring per-cwd extra roots for cwd not present in skills/list cwds"
               );
               continue;
           }

           // 验证：extra_user_roots 必须是绝对路径
           let mut valid_extra_roots = Vec::new();
           for root in entry.extra_user_roots {
               if !root.is_absolute() {
                   self.send_invalid_request_error(
                       request_id,
                       format!("skills/list perCwdExtraUserRoots extraUserRoots paths must be absolute: {}", root.display())
                   ).await;
                   return;
               }
               valid_extra_roots.push(root);
           }
           extra_roots_by_cwd.insert(entry.cwd, valid_extra_roots);
       }
       
       // 调用技能管理器...
   }
   ```

2. **技能发现流程**：`SkillsManager::list_skills()`
   - 接收 `extra_roots_by_cwd: HashMap<PathBuf, Vec<PathBuf>>` 参数
   - 对于每个请求的 cwd，将对应的额外根目录加入扫描列表
   - 额外根目录中的技能被标记为 `SkillScope::User`

3. **缓存处理**：
   - 额外根目录配置参与缓存键计算
   - 相同的 cwd 但不同的 extra roots 会产生不同的缓存条目
   - `force_reload` 参数可以绕过缓存强制重新扫描

### 生成的 TypeScript 类型

```typescript
// GENERATED CODE! DO NOT MODIFY BY HAND!
export type SkillsListExtraRootsForCwd = { 
    cwd: string, 
    extraUserRoots: Array<string>, 
};
```

### JSON Schema（内嵌于 SkillsListParams.json）

```json
{
  "definitions": {
    "SkillsListExtraRootsForCwd": {
      "properties": {
        "cwd": { "type": "string" },
        "extraUserRoots": {
          "items": { "type": "string" },
          "type": "array"
        }
      },
      "required": ["cwd", "extraUserRoots"],
      "type": "object"
    }
  }
}
```

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3080-3086` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListExtraRootsForCwd.ts` | 生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/SkillsListParams.json` | JSON Schema（内嵌定义） |

### 服务端实现

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs:5398-5420` | 验证和处理逻辑 |

### 测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/skills_list.rs:30-65` | 基础功能测试 |
| `codex-rs/app-server/tests/suite/v2/skills_list.rs:67-99` | 相对路径拒绝测试 |
| `codex-rs/app-server/tests/suite/v2/skills_list.rs:101-138` | 未知 cwd 忽略测试 |
| `codex-rs/app-server/tests/suite/v2/skills_list.rs:140-220` | 缓存行为测试 |

## 依赖与外部交互

### 上游依赖

1. **SkillsListParams**：作为 `per_cwd_extra_user_roots` 字段的元素类型
2. **路径验证**：依赖 Rust 标准库的 `Path::is_absolute()` 进行路径验证
3. **技能管理器**：将验证后的路径映射传递给 `SkillsManager`

### 下游影响

1. **技能发现范围**：直接影响哪些目录被扫描以发现技能
2. **技能作用域**：额外根目录中的技能被赋予 `User` 作用域
3. **缓存键计算**：配置变化会导致缓存失效和重新扫描

### 关联类型

```
SkillsListParams
└── per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>
    ├── cwd: PathBuf
    └── extra_user_roots: Vec<PathBuf>
```

## 风险、边界与改进建议

### 潜在风险

1. **路径遍历风险**：虽然要求绝对路径，但仍需确保路径不会指向敏感系统目录
2. **性能影响**：大量额外根目录可能导致扫描性能下降
3. **缓存膨胀**：不同的 extra roots 组合会产生大量缓存条目

### 边界情况

1. **空 extraUserRoots**：允许存在，但不会产生实际效果
2. **重复 cwd**：如果数组中有多个相同 cwd 的条目，后出现的会覆盖先出现的
3. **非存在路径**：指向不存在的目录时，技能管理器会如何处理？（当前可能静默忽略）
4. **相对路径请求**：会被明确拒绝，返回 `INVALID_PARAMS_ERROR_CODE` 错误

### 测试覆盖

集成测试覆盖了以下场景：

```rust
// 1. 基本功能：从额外根目录加载技能
#[tokio::test]
async fn skills_list_includes_skills_from_per_cwd_extra_user_roots() -> Result<()>

// 2. 安全验证：拒绝相对路径
#[tokio::test]
async fn skills_list_rejects_relative_extra_user_roots() -> Result<()>

// 3. 作用域隔离：忽略与请求 cwd 不匹配的条目
#[tokio::test]
async fn skills_list_ignores_per_cwd_extra_roots_for_unknown_cwd() -> Result<()>

// 4. 缓存行为：验证 force_reload 对额外根目录的影响
#[tokio::test]
async fn skills_list_uses_cached_result_until_force_reload() -> Result<()>
```

### 改进建议

1. **添加路径存在性验证**：在请求阶段验证 extra roots 是否存在
   ```rust
   for root in entry.extra_user_roots {
       if !root.exists() {
           return Err(JSONRPCErrorError {
               code: INVALID_PARAMS_ERROR_CODE,
               message: format!("Extra root path does not exist: {}", root.display()),
               data: None,
           });
       }
   }
   ```

2. **限制根目录数量**：防止客户端请求过多额外根目录导致性能问题
   ```rust
   const MAX_EXTRA_ROOTS_PER_CWD: usize = 10;
   if entry.extra_user_roots.len() > MAX_EXTRA_ROOTS_PER_CWD {
       return Err(/* ... */);
   }
   ```

3. **添加递归深度限制**：防止扫描过深的目录结构

4. **支持通配符/模式匹配**：允许使用 glob 模式指定多个技能目录
   ```rust
   pub struct SkillsListExtraRootsForCwd {
       pub cwd: PathBuf,
       pub extra_user_roots: Vec<PathBuf>,
       pub patterns: Vec<String>,  // 新增：glob 模式
   }
   ```

5. **添加作用域覆盖选项**：允许指定额外根目录中技能的作用域
   ```rust
   pub struct SkillsListExtraRootsForCwd {
       pub cwd: PathBuf,
       pub extra_user_roots: Vec<PathBuf>,
       pub scope_override: Option<SkillScope>,  // 可选的作用域覆盖
   }
   ```

6. **响应中包含实际扫描的目录**：在 `SkillsListEntry` 中添加 `scanned_roots` 字段，便于调试
