# SkillsListExtraRootsForCwd 研究文档

## 1. 场景与职责

**SkillsListExtraRootsForCwd** 是 app-server-protocol v2 协议中用于指定每个工作目录额外用户技能根目录的参数类型。该类型在以下场景中使用：

- **扩展技能扫描范围**：允许客户端为特定工作目录指定额外的技能扫描路径
- **自定义技能来源**：支持从非标准位置加载用户技能
- **多项目技能共享**：在不同项目间共享通用技能

## 2. 功能点目的

该类型的主要目的是：

1. **灵活的技能定位**：允许客户端指定额外的技能搜索路径
2. **按目录配置**：为每个工作目录独立配置额外的技能根目录
3. **支持技能复用**：使多个项目能够共享相同的技能集合

### 与其他类型的关系

- **父容器**：作为 `SkillsListParams.per_cwd_extra_user_roots` 数组的元素
- **请求参数**：与 `SkillsListParams` 一起使用，扩展技能列表查询能力
- **技能扫描**：传递给技能管理器，用于扩展技能扫描范围

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type SkillsListExtraRootsForCwd = { 
    cwd: string, 
    extraUserRoots: Array<string>, 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListExtraRootsForCwd {
    pub cwd: PathBuf,
    pub extra_user_roots: Vec<PathBuf>,
}
```

位于：`codex-rs/app-server-protocol/src/protocol/v2.rs:3083-3086`

### 关键流程

1. **客户端构造请求**：客户端为需要额外技能的工作目录构造 `SkillsListExtraRootsForCwd`
2. **参数验证**：服务器验证 `extra_user_roots` 中的路径是否为绝对路径
3. **按目录分组**：服务器按 `cwd` 将额外根目录分组
4. **技能扫描**：技能管理器使用额外根目录扩展技能扫描范围

### 代码示例

```rust
async fn skills_list(&self, request_id: ConnectionRequestId, params: SkillsListParams) {
    let SkillsListParams { cwds, force_reload, per_cwd_extra_user_roots } = params;
    let cwds = if cwds.is_empty() { vec![self.config.cwd.clone()] } else { cwds };
    let cwd_set: HashSet<PathBuf> = cwds.iter().cloned().collect();

    let mut extra_roots_by_cwd: HashMap<PathBuf, Vec<PathBuf>> = HashMap::new();
    for entry in per_cwd_extra_user_roots.unwrap_or_default() {
        // 验证 cwd 是否在请求列表中
        if !cwd_set.contains(&entry.cwd) {
            warn!(cwd = %entry.cwd.display(), "ignoring per-cwd extra roots for cwd not present in skills/list cwds");
            continue;
        }

        let mut valid_extra_roots = Vec::new();
        for root in entry.extra_user_roots {
            // 验证路径必须为绝对路径
            if !root.is_absolute() {
                self.send_invalid_request_error(
                    request_id,
                    format!("skills/list perCwdExtraUserRoots extraUserRoots paths must be absolute: {}", root.display())
                ).await;
                return;
            }
            valid_extra_roots.push(root);
        }
        extra_roots_by_cwd.entry(entry.cwd).or_default().extend(valid_extra_roots);
    }

    // ... 使用 extra_roots_by_cwd 进行技能扫描
}
```

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs:3083-3086`
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListExtraRootsForCwd.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/SkillsListExtraRootsForCwd.json`

### 服务端实现
- **请求处理**：`codex-rs/app-server/src/codex_message_processor.rs:5399-5427`

### 父类型定义
- **SkillsListParams**：`codex-rs/app-server-protocol/src/protocol/v2.rs:3065-3078`

### 测试覆盖
- **集成测试**：`codex-rs/app-server/tests/suite/v2/skills_list.rs`
  - `skills_list_includes_skills_from_per_cwd_extra_user_roots`：验证额外根目录的技能被正确包含
  - `skills_list_rejects_relative_extra_user_roots`：验证拒绝相对路径
  - `skills_list_ignores_per_cwd_extra_roots_for_unknown_cwd`：验证忽略未知 cwd 的配置

## 5. 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `ts-rs` | TypeScript 类型生成 |
| `PathBuf` | 路径表示 |

### 数据流

```
客户端
    │
    ├── 构造 SkillsListParams ────────────────────────▶
    │   └── per_cwd_extra_user_roots: [
    │           SkillsListExtraRootsForCwd {
    │               cwd: "/project/a",
    │               extra_user_roots: ["/shared/skills"]
    │           }
    │       ]
    │
    │                                                    服务器
    │                                                    ├── 解析参数
    │                                                    ├── 验证路径为绝对路径
    │                                                    ├── 按 cwd 分组
    │                                                    └── 传递给技能管理器
    │
    ◀── 返回 SkillsListResponse ────────────────────────
        └── data: [
                SkillsListEntry {
                    cwd: "/project/a",
                    skills: [..., /* 包含 /shared/skills 中的技能 */],
                    errors: []
                }
            ]
```

### 技能扫描扩展

```rust
let outcome = skills_manager
    .skills_for_cwd_with_extra_user_roots(
        &cwd,           // 工作目录
        &config,        // 配置
        force_reload,   // 是否强制刷新
        extra_roots     // 额外根目录（来自 SkillsListExtraRootsForCwd）
    )
    .await;
```

## 6. 风险、边界与改进建议

### 潜在风险

1. **路径安全问题**：如果允许相对路径，可能导致路径遍历攻击
2. **性能影响**：过多的额外根目录可能导致技能扫描变慢
3. **缓存复杂性**：额外根目录增加了缓存管理的复杂性

### 边界情况

1. **路径不存在**：指定的额外根目录可能不存在
2. **权限问题**：可能无法读取某些额外根目录
3. **重复技能**：多个根目录可能包含同名技能

### 当前验证

当前实现已包含以下验证：

1. **绝对路径检查**：`extra_user_roots` 中的路径必须为绝对路径
2. **cwd 存在性检查**：忽略不在请求列表中的 cwd 配置

### 改进建议

1. **添加路径存在性验证**：在请求时验证路径是否存在
   ```rust
   pub struct SkillsListExtraRootsForCwd {
       pub cwd: PathBuf,
       pub extra_user_roots: Vec<PathBuf>,
       pub validate_exists: Option<bool>, // 是否验证路径存在
   }
   ```

2. **支持路径别名**：允许使用别名引用常用技能目录
   ```rust
   pub struct SkillsListExtraRootsForCwd {
       pub cwd: PathBuf,
       pub extra_user_roots: Vec<PathBuf>,
       pub aliases: Option<HashMap<String, PathBuf>>, // 路径别名
   }
   ```

3. **添加优先级配置**：控制额外根目录的优先级
   ```rust
   pub struct ExtraUserRoot {
       pub path: PathBuf,
       pub priority: Option<i32>, // 优先级，数值越高越优先
   }
   
   pub struct SkillsListExtraRootsForCwd {
       pub cwd: PathBuf,
       pub extra_user_roots: Vec<ExtraUserRoot>,
   }
   ```

4. **支持排除模式**：允许排除某些子目录
   ```rust
   pub struct SkillsListExtraRootsForCwd {
       pub cwd: PathBuf,
       pub extra_user_roots: Vec<PathBuf>,
       pub exclude_patterns: Option<Vec<String>>, // 排除模式，如 ["test_*", "*.bak"]
   }
   ```

5. **添加递归控制**：控制是否递归扫描子目录
   ```rust
   pub struct ExtraUserRoot {
       pub path: PathBuf,
       pub recursive: Option<bool>, // 是否递归扫描，默认 true
       pub max_depth: Option<usize>, // 最大递归深度
   }
   ```

6. **缓存控制**：允许客户端控制额外根目录的缓存行为
   ```rust
   pub struct SkillsListExtraRootsForCwd {
       pub cwd: PathBuf,
       pub extra_user_roots: Vec<PathBuf>,
       pub cache_behavior: Option<ExtraRootCacheBehavior>,
   }
   
   pub enum ExtraRootCacheBehavior {
       UseCache,      // 使用缓存
       Refresh,       // 刷新缓存
       NoCache,       // 不使用缓存
   }
   ```
