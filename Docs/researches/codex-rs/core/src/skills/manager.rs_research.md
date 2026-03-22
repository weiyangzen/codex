# manager.rs 深度研究文档

## 场景与职责

`manager.rs` 是 Codex 核心技能系统的管理模块，负责技能的生命周期管理、缓存策略、配置协调和动态加载。它是技能子系统的核心协调器，连接配置层、插件系统和技能加载器。

### 核心职责

1. **技能管理器生命周期**：创建时处理系统技能的安装/卸载
2. **双层缓存策略**：按工作目录缓存和按配置缓存
3. **配置感知加载**：根据配置层堆栈动态计算技能根目录
4. **插件集成**：与插件管理器协调，支持插件提供的技能根
5. **额外用户根支持**：支持动态添加额外的技能搜索路径
6. **技能启用控制**：根据配置层中的 `skills.config` 设置控制技能启用/禁用

---

## 功能点目的

### 1. SkillsManager 结构体

**目的**：提供线程安全的技能管理，支持缓存和动态加载。

```rust
pub struct SkillsManager {
    codex_home: PathBuf,
    plugins_manager: Arc<PluginsManager>,
    cache_by_cwd: RwLock<HashMap<PathBuf, SkillLoadOutcome>>,
    cache_by_config: RwLock<HashMap<ConfigSkillsCacheKey, SkillLoadOutcome>>,
}
```

**设计决策**：
- 使用 `RwLock` 而非 `Mutex` 允许并发读取
- 双层缓存区分按目录缓存（快速）和按配置缓存（精确）
- `Arc<PluginsManager>` 支持多线程共享

### 2. 构造函数与系统技能管理

**目的**：初始化时处理捆绑技能的安装或清理。

```rust
pub fn new(codex_home: PathBuf, plugins_manager: Arc<PluginsManager>, bundled_skills_enabled: bool) -> Self
```

**行为**：
- `bundled_skills_enabled = false`：删除 `.system` 目录（清理过时缓存）
- `bundled_skills_enabled = true`：调用 `install_system_skills` 安装系统技能

### 3. 按配置加载 (`skills_for_config`)

**目的**：为已构建的 Config 加载技能，使用配置感知缓存。

**关键特性**：
- 缓存键基于技能根目录和禁用路径集合
- 避免角色本地和会话本地覆盖跨会话泄漏
- 同步接口（假设 Config 已构建完成）

### 4. 按工作目录加载 (`skills_for_cwd`)

**目的**：为指定工作目录加载技能，支持强制刷新。

**流程**：
1. 检查缓存（如未强制刷新）
2. 加载配置层堆栈
3. 获取插件技能根
4. 计算最终技能根列表
5. 加载技能并更新缓存

### 5. 额外用户根支持 (`skills_for_cwd_with_extra_user_roots`)

**目的**：支持动态添加额外的技能搜索路径（如 CLI 传入的 `--skill` 参数）。

**实现细节**：
- 额外根被归一化（canonicalize）和去重
- 额外根的作用域始终为 `User`
- 缓存按 cwd 存储，包含额外根的结果

### 6. 缓存清除 (`clear_cache`)

**目的**：提供显式缓存清除机制。

**使用场景**：
- 配置变更后
- 技能文件系统变更后
- 测试清理

---

## 具体技术实现

### 缓存键设计

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct ConfigSkillsCacheKey {
    roots: Vec<(PathBuf, u8)>,  // 路径 + 作用域排名
    disabled_paths: Vec<PathBuf>, // 禁用的技能路径
}
```

**作用域排名**：
- Repo = 0（最高优先级）
- User = 1
- System = 2
- Admin = 3（最低优先级）

### 禁用路径计算

```rust
fn disabled_paths_from_stack(config_layer_stack: &ConfigLayerStack) -> HashSet<PathBuf>
```

**逻辑**：
1. 遍历 User 和 SessionFlags 层（只有这些层可以控制技能启用）
2. 解析 `skills.config` 数组
3. 收集 `enabled = false` 的路径
4. 后出现的配置覆盖先出现的（会话标志可覆盖用户配置）

### 捆绑技能控制

```rust
pub(crate) fn bundled_skills_enabled_from_stack(config_layer_stack: &ConfigLayerStack) -> bool
```

**逻辑**：
1. 获取有效配置
2. 解析 `[skills.bundled]` 配置
3. 默认启用（`unwrap_or_default().enabled`）

### 技能根计算

```rust
pub(crate) fn skill_roots_for_config(&self, config: &Config) -> Vec<SkillRoot>
```

**流程**：
1. 从插件管理器获取有效技能根
2. 调用 `skill_roots()` 计算基础根目录
3. 如禁用捆绑技能，过滤掉 `SkillScope::System`

### 结果最终化

```rust
fn finalize_skill_outcome(
    mut outcome: SkillLoadOutcome,
    config_layer_stack: &ConfigLayerStack,
) -> SkillLoadOutcome
```

**操作**：
1. 设置 `disabled_paths`
2. 构建隐式调用索引（`implicit_skills_by_scripts_dir` 和 `implicit_skills_by_doc_path`）

---

## 关键代码路径与文件引用

### 主要函数调用图

```
SkillsManager::new
├── install_system_skills (bundled_skills_enabled = true)
│   └── codex_skills::install_system_skills
└── uninstall_system_skills (bundled_skills_enabled = false)
    └── remove_dir_all(.system)

skills_for_config
├── skill_roots_for_config
│   ├── plugins_manager.plugins_for_config
│   └── skill_roots
└── finalize_skill_outcome
    ├── disabled_paths_from_stack
    └── build_implicit_skill_path_indexes

skills_for_cwd_with_extra_user_roots
├── cached_outcome_for_cwd
├── load_config_layers_state
├── plugins_manager.plugins_for_config_with_force_reload
├── skill_roots
├── load_skills_from_roots
└── finalize_skill_outcome
```

### 依赖文件

| 文件 | 用途 |
|------|------|
| `loader.rs` | `load_skills_from_roots`, `skill_roots` |
| `model.rs` | `SkillLoadOutcome`, `SkillMetadata`, `SkillError` |
| `system.rs` | `install_system_skills`, `uninstall_system_skills` |
| `invocation_utils.rs` | `build_implicit_skill_path_indexes` |
| `../config_loader.rs` | `load_config_layers_state`, `ConfigLayerStack` |
| `../plugins/manager.rs` | `PluginsManager` |
| `../config.rs` | `Config`, `SkillsConfig` |

### 配置键

| 配置路径 | 类型 | 说明 |
|----------|------|------|
| `skills.bundled.enabled` | bool | 是否启用捆绑技能 |
| `skills.config` | array | 技能启用/禁用覆盖 |
| `skills.config[].path` | string | 技能路径 |
| `skills.config[].enabled` | bool | 是否启用 |

---

## 依赖与外部交互

### 内部模块依赖

```rust
use crate::config::Config;
use crate::config::types::SkillsConfig;
use crate::config_loader::{CloudRequirementsLoader, ConfigLayerStack, LoaderOverrides, load_config_layers_state};
use crate::plugins::PluginsManager;
use crate::skills::{SkillLoadOutcome, build_implicit_skill_path_indexes};
use crate::skills::loader::{SkillRoot, load_skills_from_roots, skill_roots};
use crate::skills::system::{install_system_skills, uninstall_system_skills};
```

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_app_server_protocol::ConfigLayerSource` | 配置层来源识别 |
| `codex_protocol::protocol::SkillScope` | 技能作用域枚举 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径处理 |
| `tracing::{info, warn}` | 日志记录 |

### 并发模型

- 使用 `std::sync::RwLock` 保护缓存
- `read()` 失败时使用 `PoisonError::into_inner()` 恢复
- 插件管理器通过 `Arc` 共享

---

## 风险、边界与改进建议

### 当前风险

1. **缓存一致性**：
   - 文件系统变更不会自动使缓存失效
   - 用户需要手动调用 `clear_cache()` 或重启进程

2. **错误处理**：
   - 配置加载错误被转换为 `SkillLoadOutcome` 中的错误，可能导致静默失败
   - 路径规范化失败使用原始路径回退，可能引发不一致行为

3. **路径安全**：
   - `dunce::canonicalize` 在 Windows 上行为可能与 Unix 不同
   - 符号链接处理依赖底层 `loader.rs` 实现

### 边界情况

1. **缓存键冲突**：
   - 不同配置可能产生相同的缓存键（如果根目录和禁用路径相同）
   - 角色本地覆盖可能导致意外的缓存命中

2. **并发访问**：
   - `RwLock` 在写操作时阻塞所有读操作
   - 缓存清除和加载同时进行可能导致短暂不一致

3. **插件动态变更**：
   - 插件技能根变更需要 `force_reload = true` 才能生效
   - 插件卸载后缓存中可能保留过时的技能引用

### 改进建议

1. **缓存改进**：
   - 实现基于文件系统监视的自动缓存失效（使用 `notify` crate）
   - 添加缓存统计信息（命中率、条目数）用于调试
   - 考虑使用 `dashmap` 替代 `RwLock<HashMap>` 提高并发性能

2. **错误处理**：
   - 区分可恢复错误和致命错误
   - 添加结构化错误类型替代字符串错误
   - 实现错误上下文链，便于调试

3. **配置管理**：
   - 支持热重载配置而不重启
   - 添加配置变更事件订阅机制
   - 实现配置验证和预览功能

4. **性能优化**：
   - 并行加载多个技能根目录
   - 延迟加载技能内容（只在需要时读取 SKILL.md）
   - 使用 `moka` 等高性能缓存库

5. **可观测性**：
   - 添加详细的 span 跟踪（`#[tracing::instrument]`）
   - 暴露技能加载指标（加载时间、数量、错误率）
   - 添加技能加载日志，便于排查问题

6. **API 改进**：
   - 考虑使用 `async fn` 统一同步和异步接口
   - 添加流式技能加载接口（用于大型技能集）
   - 支持技能搜索和过滤 API
