# manager_tests.rs 深度研究文档

## 场景与职责

`manager_tests.rs` 是 `manager.rs` 的配套测试文件，专注于测试 `SkillsManager` 的核心管理功能，包括缓存行为、捆绑技能控制、配置层覆盖和会话标志处理。这些测试验证技能管理器在复杂配置场景下的正确行为。

### 核心测试职责

1. **缓存行为测试**：验证按配置缓存和按工作目录缓存的正确性
2. **捆绑技能控制**：验证启用/禁用系统技能时的清理和加载行为
3. **配置层覆盖**：验证 User 层和 SessionFlags 层之间的覆盖关系
4. **额外技能根**：验证动态添加技能搜索路径的功能
5. **角色配置集成**：验证 Agent Role 配置对技能加载的影响

---

## 功能点目的

### 1. 捆绑技能清理测试

**测试**：`new_with_disabled_bundled_skills_removes_stale_cached_system_skills`

**目的**：验证禁用捆绑技能时，管理器正确清理过时的系统技能缓存。

**场景**：
- 用户之前启用了捆绑技能，`.system` 目录存在
- 用户现在禁用捆绑技能
- 期望：`.system` 目录被删除

### 2. 配置感知缓存测试

**测试**：`skills_for_config_reuses_cache_for_same_effective_config`

**目的**：验证相同有效配置的技能加载结果会被缓存复用。

**场景**：
- 第一次调用加载技能 A
- 写入新技能 B（文件系统变更）
- 第二次调用（相同 Config）应返回缓存结果（不包含 B）

**意义**：确保角色本地和会话本地覆盖不会跨会话泄漏。

### 3. 额外根缓存测试

**测试**：`skills_for_cwd_reuses_cached_entry_even_when_entry_has_extra_roots`

**目的**：验证带额外根的加载结果会被按 cwd 缓存复用。

**场景**：
- 使用额外根加载技能
- 不带额外根的调用应返回相同结果（从缓存）

### 4. 捆绑技能禁用测试

**测试**：`skills_for_config_excludes_bundled_skills_when_disabled_in_config`

**目的**：验证配置中禁用捆绑技能时，System 作用域技能被排除。

**配置**：
```toml
[skills.bundled]
enabled = false
```

### 5. 强制刷新测试

**测试**：`skills_for_cwd_with_extra_roots_only_refreshes_on_force_reload`

**目的**：验证 `force_reload` 参数正确控制缓存行为。

**场景**：
- 第一次加载（force_reload=true）使用额外根 A
- 第二次加载（force_reload=false）使用额外根 B → 返回缓存结果（A 的技能）
- 第三次加载（force_reload=true）使用额外根 B → 返回新结果（B 的技能）

### 6. 配置层覆盖测试

**测试**：
- `disabled_paths_from_stack_allows_session_flags_to_override_user_layer`
- `disabled_paths_from_stack_allows_session_flags_to_disable_user_enabled_skill`

**目的**：验证 SessionFlags 层可以覆盖 User 层的技能启用设置。

**场景**：
- User 层禁用技能，SessionFlags 层启用 → 最终启用
- User 层启用技能，SessionFlags 层禁用 → 最终禁用

### 7. 角色配置集成测试

**测试**：`skills_for_config_ignores_cwd_cache_when_session_flags_reenable_skill`

**目的**：验证 Agent Role 配置可以覆盖父配置的技能启用状态。

**场景**：
- 父配置禁用技能
- 角色配置启用同一技能
- `skills_for_config` 应返回启用的技能

---

## 具体技术实现

### 测试基础设施

```rust
fn write_user_skill(codex_home: &TempDir, dir: &str, name: &str, description: &str) {
    let skill_dir = codex_home.path().join("skills").join(dir);
    fs::create_dir_all(&skill_dir).unwrap();
    let content = format!("---\nname: {name}\ndescription: {description}\n---\n\n# Body\n");
    fs::write(skill_dir.join("SKILL.md"), content).unwrap();
}
```

### 配置构建模式

```rust
let config = ConfigBuilder::default()
    .codex_home(codex_home.path().to_path_buf())
    .harness_overrides(ConfigOverrides {
        cwd: Some(cwd.path().to_path_buf()),
        ..Default::default()
    })
    .build()
    .await
    .expect("defaults for test should always succeed");
```

### 管理器创建模式

```rust
let plugins_manager = Arc::new(PluginsManager::new(codex_home.path().to_path_buf()));
let skills_manager = SkillsManager::new(
    codex_home.path().to_path_buf(),
    plugins_manager,
    config.bundled_skills_enabled(),
);
```

### 配置层堆栈构建（用于覆盖测试）

```rust
let user_layer = ConfigLayerEntry::new(
    ConfigLayerSource::User { file: user_file },
    toml::from_str(r#"[[skills.config]]
path = "..."
enabled = false
"#)?,
);

let session_layer = ConfigLayerEntry::new(
    ConfigLayerSource::SessionFlags,
    toml::from_str(r#"[[skills.config]]
path = "..."
enabled = true
"#)?,
);

let stack = ConfigLayerStack::new(
    vec![user_layer, session_layer],
    Default::default(),
    ConfigRequirementsToml::default(),
)?;
```

### 角色配置应用

```rust
let mut child_config = parent_config.clone();
child_config.agent_roles.insert(
    "custom".to_string(),
    AgentRoleConfig {
        description: None,
        config_file: Some(role_path),
        nickname_candidates: None,
    },
);
apply_role_to_config(&mut child_config, Some("custom")).await?;
```

---

## 关键代码路径与文件引用

### 测试覆盖的管理器函数

| 函数 | 测试用例 |
|------|----------|
| `SkillsManager::new` | `new_with_disabled_bundled_skills_removes_stale_cached_system_skills` |
| `skills_for_config` | `skills_for_config_reuses_cache_for_same_effective_config`, `skills_for_config_excludes_bundled_skills_when_disabled_in_config`, `skills_for_config_ignores_cwd_cache_when_session_flags_reenable_skill` |
| `skills_for_cwd` | `skills_for_cwd_reuses_cached_entry_even_when_entry_has_extra_roots` |
| `skills_for_cwd_with_extra_user_roots` | `skills_for_cwd_with_extra_roots_only_refreshes_on_force_reload` |
| `disabled_paths_from_stack` | `disabled_paths_from_stack_allows_session_flags_to_override_user_layer`, `disabled_paths_from_stack_allows_session_flags_to_disable_user_enabled_skill` |
| `normalize_extra_user_roots` | `normalize_extra_user_roots_is_stable_for_equivalent_inputs` |

### 依赖文件

| 文件 | 用途 |
|------|------|
| `manager.rs` | 被测试的主要实现 |
| `loader.rs` | 底层技能加载 |
| `../config.rs` | `ConfigBuilder`, `ConfigOverrides`, `AgentRoleConfig` |
| `../config_loader.rs` | `ConfigLayerEntry`, `ConfigLayerStack` |
| `../plugins/manager.rs` | `PluginsManager` |
| `../agent/role.rs` | `apply_role_to_config` |

### 测试结构

```
manager_tests.rs
├── 辅助函数
│   └── write_user_skill
├── 捆绑技能测试
│   └── new_with_disabled_bundled_skills_removes_stale_cached_system_skills
├── 缓存行为测试
│   ├── skills_for_config_reuses_cache_for_same_effective_config
│   ├── skills_for_cwd_reuses_cached_entry_even_when_entry_has_extra_roots
│   └── skills_for_cwd_with_extra_roots_only_refreshes_on_force_reload
├── 配置控制测试
│   ├── skills_for_config_excludes_bundled_skills_when_disabled_in_config
│   ├── disabled_paths_from_stack_allows_session_flags_to_override_user_layer
│   └── disabled_paths_from_stack_allows_session_flags_to_disable_user_enabled_skill
└── 角色集成测试
    └── skills_for_config_ignores_cwd_cache_when_session_flags_reenable_skill
```

---

## 依赖与外部交互

### 内部依赖

```rust
use crate::config::ConfigBuilder;
use crate::config::ConfigOverrides;
use crate::config_loader::ConfigLayerEntry;
use crate::config_loader::ConfigLayerStack;
use crate::config_loader::ConfigRequirementsToml;
use crate::plugins::PluginsManager;
```

### 测试特定依赖

| 类型 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建隔离的临时文件系统 |
| `std::sync::Arc` | 共享插件管理器 |
| `pretty_assertions::assert_eq` | 更好的断言失败输出 |

### 配置层来源

| 来源 | 用途 |
|------|------|
| `ConfigLayerSource::User` | 模拟用户配置文件 |
| `ConfigLayerSource::SessionFlags` | 模拟会话级覆盖 |

---

## 风险、边界与改进建议

### 当前风险

1. **测试隔离性**：
   - 部分测试共享全局状态（如 `disabled_paths_from_stack` 测试）
   - 并行执行可能产生竞争条件

2. **平台差异**：
   - `#[cfg_attr(windows, ignore)]` 标记的测试在 Windows 上跳过
   - 路径分隔符和绝对路径格式在不同平台行为不同

3. **配置复杂性**：
   - 测试需要理解复杂的配置层堆栈概念
   - 配置覆盖规则容易出错

### 边界情况

1. **缓存键稳定性**：
   - `normalize_extra_user_roots_is_stable_for_equivalent_inputs` 验证路径规范化的一致性
   - 重复路径和不同顺序的输入应产生相同输出

2. **配置层优先级**：
   - 后出现的 SessionFlags 层覆盖先出现的 User 层
   - 这是通过 `HashMap::insert` 的行为实现的

3. **角色配置应用**：
   - 角色配置通过修改现有 Config 应用
   - 需要克隆父配置以避免副作用

### 改进建议

1. **测试覆盖率**：
   - 添加测试验证缓存过期策略
   - 测试多线程并发访问场景
   - 测试插件动态加载/卸载对缓存的影响

2. **测试可读性**：
   - 使用 builder 模式创建测试配置
   - 提取重复的 ConfigBuilder 设置到辅助函数
   - 使用表格驱动测试减少重复代码

3. **错误场景**：
   - 测试无效配置的处理
   - 测试插件管理器失败时的回退行为
   - 测试文件系统权限问题

4. **性能测试**：
   - 添加大配置层堆栈的性能基准
   - 测试大量技能时的缓存性能

5. **文档**：
   - 为每个测试添加更详细的注释说明测试意图
   - 建立测试数据工厂模式
   - 添加配置层交互的可视化文档
