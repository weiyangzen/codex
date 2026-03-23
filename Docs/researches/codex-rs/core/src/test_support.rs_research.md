# test_support.rs 研究文档

## 场景与职责

`test_support.rs` 是 Codex Core 模块的测试支持库，为跨 crate 集成测试提供专用工具和辅助函数。该模块仅在测试上下文中可用，生产代码不应依赖此模块。

**设计原则：**
- 避免使用 crate feature 控制测试代码，减少构建配置复杂度
- 提供统一的测试辅助函数，确保跨 crate 测试一致性
- 封装内部 API，使测试能够访问受限的生产功能

**主要职责：**
1. **测试模型预设** - 提供加载自 `models.json` 的测试模型配置
2. **线程管理器测试模式** - 启用/禁用线程管理器的测试行为
3. **认证管理器构造** - 从认证配置创建测试用 AuthManager
4. **线程生命周期** - 支持带用户 Shell 覆盖的线程启动和恢复
5. **模型管理器** - 提供离线模型查询和构造功能

## 功能点目的

### 1. 测试模型预设加载

```rust
static TEST_MODEL_PRESETS: Lazy<Vec<ModelPreset>> = Lazy::new(|| {
    let file_contents = include_str!("../models.json");
    let mut response: ModelsResponse = serde_json::from_str(file_contents)
        .unwrap_or_else(|err| panic!("bundled models.json should parse: {err}"));
    response.models.sort_by(|a, b| a.priority.cmp(&b.priority));
    let mut presets: Vec<ModelPreset> = response.models.into_iter().map(Into::into).collect();
    ModelPreset::mark_default_by_picker_visibility(&mut presets);
    presets
});
```

**功能：**
- 编译时嵌入 `models.json` 文件内容
- 解析并排序模型配置
- 标记默认模型预设

**用途：** 测试中使用与生产环境一致的模型配置，避免硬编码。

### 2. 线程管理器测试模式

```rust
pub fn set_thread_manager_test_mode(enabled: bool)
pub fn set_deterministic_process_ids(enabled: bool)
```

**功能：**
- 启用线程管理器的测试模式（可能影响行为如：禁用某些优化、启用额外检查）
- 启用确定性进程 ID（用于快照测试，确保进程 ID 可预测）

**调用链：**
```
set_thread_manager_test_mode()
  └── thread_manager::set_thread_manager_test_mode_for_tests()

set_deterministic_process_ids()
  └── unified_exec::set_deterministic_process_ids_for_tests()
```

### 3. 认证管理器构造

```rust
pub fn auth_manager_from_auth(auth: CodexAuth) -> Arc<AuthManager>
pub fn auth_manager_from_auth_with_home(auth: CodexAuth, codex_home: PathBuf) -> Arc<AuthManager>
```

**功能：** 从认证配置创建 `AuthManager`，支持自定义 codex_home。

**生产限制：** `AuthManager::from_auth_for_testing` 仅在测试上下文中暴露。

### 4. 线程管理器构造

```rust
pub fn thread_manager_with_models_provider(
    auth: CodexAuth,
    provider: ModelProviderInfo,
) -> ThreadManager

pub fn thread_manager_with_models_provider_and_home(
    auth: CodexAuth,
    provider: ModelProviderInfo,
    codex_home: PathBuf,
) -> ThreadManager
```

**功能：** 使用指定的模型提供者创建线程管理器，支持自定义 codex_home。

### 5. 线程启动与恢复

```rust
pub async fn start_thread_with_user_shell_override(
    thread_manager: &ThreadManager,
    config: Config,
    user_shell_override: crate::shell::Shell,
) -> crate::error::Result<crate::NewThread>
```

**功能：** 启动新线程，允许覆盖默认 Shell 配置。

```rust
pub async fn resume_thread_from_rollout_with_user_shell_override(
    thread_manager: &ThreadManager,
    config: Config,
    rollout_path: PathBuf,
    auth_manager: Arc<AuthManager>,
    user_shell_override: crate::shell::Shell,
) -> crate::error::Result<crate::NewThread>
```

**功能：** 从 rollout 文件恢复线程，支持 Shell 覆盖。

**用途：** 测试特定 Shell 行为（如 bash vs zsh），无需修改系统默认 Shell。

### 6. 模型管理器辅助

```rust
pub fn models_manager_with_provider(
    codex_home: PathBuf,
    auth_manager: Arc<AuthManager>,
    provider: ModelProviderInfo,
) -> ModelsManager

pub fn get_model_offline(model: Option<&str>) -> String
pub fn construct_model_info_offline(model: &str, config: &Config) -> ModelInfo
```

**功能：**
- 使用指定提供者创建模型管理器
- 离线获取模型标识（不依赖网络）
- 离线构造模型信息结构

### 7. 模型预设查询

```rust
pub fn all_model_presets() -> &'static Vec<ModelPreset>
```

**功能：** 返回所有测试模型预设的静态引用。

### 8. 协作模式预设

```rust
pub fn builtin_collaboration_mode_presets() -> Vec<CollaborationModeMask>
```

**功能：** 返回内置的协作模式预设列表。

## 具体技术实现

### 模块属性

```rust
//! Test-only helpers exposed for cross-crate integration tests.
//!
//! Production code should not depend on this module.
//! We prefer this to using a crate feature to avoid building multiple
//! permutations of the crate.
```

### 条件编译

虽然模块本身不使用 `#[cfg(test)]`，但所有导出函数都委托给带有 `for_testing` 或 `for_tests` 后缀的内部函数，这些内部函数在生产构建中可能不可用或行为不同。

### 依赖关系

```rust
use std::path::PathBuf;
use std::sync::Arc;
use codex_protocol::config_types::CollaborationModeMask;
use codex_protocol::openai_models::ModelInfo;
use codex_protocol::openai_models::ModelPreset;
use codex_protocol::openai_models::ModelsResponse;
use once_cell::sync::Lazy;

use crate::AuthManager;
use crate::CodexAuth;
use crate::ModelProviderInfo;
use crate::ThreadManager;
use crate::config::Config;
use crate::models_manager::collaboration_mode_presets;
use crate::models_manager::manager::ModelsManager;
use crate::thread_manager;
use crate::unified_exec;
```

## 关键代码路径与文件引用

### 核心函数

| 函数 | 行号 | 委托目标 |
|------|------|---------|
| `set_thread_manager_test_mode` | 36-38 | `thread_manager::set_thread_manager_test_mode_for_tests` |
| `set_deterministic_process_ids` | 40-42 | `unified_exec::set_deterministic_process_ids_for_tests` |
| `auth_manager_from_auth` | 44-46 | `AuthManager::from_auth_for_testing` |
| `auth_manager_from_auth_with_home` | 48-50 | `AuthManager::from_auth_for_testing_with_home` |
| `thread_manager_with_models_provider` | 52-57 | `ThreadManager::with_models_provider_for_tests` |
| `thread_manager_with_models_provider_and_home` | 59-65 | `ThreadManager::with_models_provider_and_home_for_tests` |
| `start_thread_with_user_shell_override` | 67-75 | `ThreadManager::start_thread_with_user_shell_override_for_tests` |
| `resume_thread_from_rollout_with_user_shell_override` | 77-92 | `ThreadManager::resume_thread_from_rollout_with_user_shell_override_for_tests` |
| `models_manager_with_provider` | 94-100 | `ModelsManager::with_provider_for_tests` |
| `get_model_offline` | 102-104 | `ModelsManager::get_model_offline_for_tests` |
| `construct_model_info_offline` | 106-108 | `ModelsManager::construct_model_info_offline_for_tests` |
| `all_model_presets` | 110-112 | `TEST_MODEL_PRESETS` |
| `builtin_collaboration_mode_presets` | 114-118 | `collaboration_mode_presets::builtin_collaboration_mode_presets` |

### 调用关系

**被调用方（上游）：**
- 集成测试（`tests/` 目录）
- 其他 crate 的测试（通过 `codex_core::test_support`）

**调用方（下游）：**
- `crate::thread_manager` - 线程管理
- `crate::unified_exec` - 进程执行
- `crate::AuthManager` - 认证管理
- `crate::ThreadManager` - 线程生命周期
- `crate::ModelsManager` - 模型管理

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `once_cell::sync::Lazy` | 延迟初始化静态变量 |
| `codex_protocol` | ModelPreset、ModelInfo、CollaborationModeMask 等类型 |

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `crate::AuthManager` | 认证管理器构造 |
| `crate::ThreadManager` | 线程管理器构造和操作 |
| `crate::ModelsManager` | 模型管理器构造和查询 |
| `crate::config::Config` | 配置类型 |
| `crate::thread_manager` | 测试模式设置 |
| `crate::unified_exec` | 确定性进程 ID |
| `crate::models_manager::collaboration_mode_presets` | 协作模式预设 |

### 资源文件

- `../models.json` - 编译时嵌入的模型配置文件

## 风险、边界与改进建议

### 已知风险

1. **生产代码误用**
   - 风险：生产代码可能意外导入 `test_support`
   - 缓解：文档明确标记，代码审查检查
   - 建议：添加 `#[doc(hidden)]` 和 lint 规则

2. **API 漂移**
   - 风险：内部 `for_testing` 函数签名变更导致测试编译失败
   - 缓解：CI 编译检查
   - 建议：添加自动化测试确保 test_support 可编译

3. **models.json 同步**
   - 风险：测试使用的 models.json 与生产环境不同步
   - 缓解：文件版本控制，CI 检查
   - 建议：添加测试验证 models.json 格式有效性

### 边界情况

1. **空模型列表**
   - `TEST_MODEL_PRESETS` 在 models.json 解析失败时会 panic
   - 这是设计上的，确保测试环境配置正确

2. **并发访问**
   - `set_thread_manager_test_mode` 和 `set_deterministic_process_ids` 设置全局状态
   - 并发测试可能互相干扰
   - 建议：使用 `serial_test` crate 或测试隔离

### 改进建议

1. **添加测试隔离**
   ```rust
   // 使用 RAII 模式确保测试状态恢复
   pub struct TestModeGuard;
   impl Drop for TestModeGuard {
       fn drop(&mut self) {
           set_thread_manager_test_mode(false);
       }
   }
   ```

2. **添加验证函数**
   ```rust
   pub fn verify_test_environment() -> Result<(), TestEnvError> {
       // 验证 models.json 可解析
       // 验证测试模式可设置
       // 验证临时目录可写
   }
   ```

3. **文档增强**
   ```rust
   /// # Panics
   /// Panics if models.json cannot be parsed.
   /// 
   /// # Example
   /// ```
   /// let presets = test_support::all_model_presets();
   /// assert!(!presets.is_empty());
   /// ```
   pub fn all_model_presets() -> &'static Vec<ModelPreset>
   ```

4. **添加更多测试辅助**
   ```rust
   // 临时配置构造
   pub fn temp_config() -> (Config, TempDir)
   
   // 模拟认证
   pub fn mock_auth() -> CodexAuth
   
   // 临时 rollout 文件
   pub fn temp_rollout() -> (PathBuf, TempDir)
   ```

5. **性能优化**
   ```rust
   // 当前每次调用都重新解析，建议缓存
   static TEST_MODEL_PRESETS: Lazy<Vec<ModelPreset>> = // 已缓存
   ```

### 测试文件

- 无直接测试文件（此模块本身就是测试支持）
- 间接测试：所有使用此模块的集成测试
