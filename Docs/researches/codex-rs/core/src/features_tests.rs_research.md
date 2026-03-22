# features_tests.rs 研究文档

## 场景与职责

本文件是 `features.rs` 模块的单元测试文件，负责验证功能标志（Feature Flags）系统的核心行为。测试覆盖以下关键场景：

1. **功能生命周期合规性**：确保开发中功能默认禁用、稳定功能默认启用等规则
2. **功能依赖关系**：验证功能间的依赖规范化逻辑
3. **实验性功能定义**：验证实验性功能的元数据完整性
4. **旧版配置兼容**：验证别名映射正确性
5. **认证集成**：验证需要特定认证类型的功能行为

## 功能点目的

### 1. 生命周期合规性测试

**测试目标**：确保功能生命周期规则被严格遵守

| 测试函数 | 验证规则 |
|---------|---------|
| `under_development_features_are_disabled_by_default` | 所有 `UnderDevelopment` 功能必须默认禁用 |
| `default_enabled_features_are_stable` | 默认启用的功能必须是 `Stable` 或 `Removed` 状态 |
| `use_legacy_landlock_is_stable_and_disabled_by_default` | 特定功能的稳定状态验证 |
| `use_linux_sandbox_bwrap_is_removed_and_disabled_by_default` | 已移除功能的验证 |

### 2. 实验性功能验证

**测试目标**：确保实验性功能的元数据完整性

| 测试函数 | 验证内容 |
|---------|---------|
| `js_repl_is_experimental_and_user_toggleable` | JavaScript REPL 的实验性元数据 |
| `guardian_approval_is_experimental_and_user_toggleable` | Guardian Approvals 的实验性元数据 |

验证点包括：
- 菜单名称 (`experimental_menu_name`)
- 菜单描述 (`experimental_menu_description`)
- 公告文本 (`experimental_announcement`)
- 默认禁用状态

### 3. 功能依赖测试

**测试目标**：验证功能间的依赖自动处理

| 测试函数 | 验证逻辑 |
|---------|---------|
| `code_mode_only_requires_code_mode` | 启用 `CodeModeOnly` 自动启用 `CodeMode` |
| `enable_fanout_normalization_enables_multi_agent_one_way` | `SpawnCsv` 依赖 `Collab`，但反之不成立 |

### 4. 开发中功能验证

**测试目标**：确保开发中功能的正确状态

| 测试函数 | 验证功能 |
|---------|---------|
| `request_permissions_is_under_development` | `ExecPermissionApprovals` |
| `request_permissions_tool_is_under_development` | `RequestPermissionsTool` |
| `tool_suggest_is_under_development` | `ToolSuggest` |
| `image_generation_is_under_development` | `ImageGeneration` |
| `image_detail_original_feature_is_under_development` | `ImageDetailOriginal` |
| `enable_fanout_is_under_development` | `SpawnCsv` |

### 5. 旧版兼容测试

**测试目标**：验证旧配置键的别名映射

| 测试函数 | 验证内容 |
|---------|---------|
| `use_linux_sandbox_bwrap_is_a_removed_feature_key` | 旧键映射到已移除功能 |
| `collab_is_legacy_alias_for_multi_agent` | `collab` 别名映射到 `multi_agent` |

### 6. 稳定功能验证

**测试目标**：验证稳定功能的默认状态

| 测试函数 | 验证内容 |
|---------|---------|
| `multi_agent_is_stable_and_enabled_by_default` | `Collab` 功能稳定且默认启用 |

### 7. 认证集成测试

**测试目标**：验证需要特定认证类型的功能

| 测试函数 | 验证逻辑 |
|---------|---------|
| `apps_require_feature_flag_and_chatgpt_auth` | `Apps` 功能需要同时满足：功能启用 + ChatGPT 认证 |

## 具体技术实现

### 测试断言风格

使用 `pretty_assertions::assert_eq` 提供清晰的差异输出：

```rust
use pretty_assertions::assert_eq;

#[test]
fn under_development_features_are_disabled_by_default() {
    for spec in FEATURES {
        if matches!(spec.stage, Stage::UnderDevelopment) {
            assert_eq!(
                spec.default_enabled, false,
                "feature `{}` is under development and must be disabled by default",
                spec.key
            );
        }
    }
}
```

### 动态 Node 版本验证

`js_repl_is_experimental_and_user_toggleable` 测试动态读取 Node 版本：

```rust
let expected_node_version = include_str!("../../node-version.txt").trim_end();
assert_eq!(
    stage.experimental_menu_description().map(str::to_owned),
    Some(format!(
        "Enable a persistent Node-backed JavaScript REPL... Requires Node >= v{expected_node_version} installed."
    ))
);
```

### 依赖规范化验证模式

```rust
#[test]
fn code_mode_only_requires_code_mode() {
    let mut features = Features::with_defaults();
    features.enable(Feature::CodeModeOnly);
    features.normalize_dependencies();

    assert_eq!(features.enabled(Feature::CodeModeOnly), true);
    assert_eq!(features.enabled(Feature::CodeMode), true);  // 被自动启用
}
```

### 认证 Mock 测试

```rust
#[test]
fn apps_require_feature_flag_and_chatgpt_auth() {
    let mut features = Features::with_defaults();
    assert!(!features.apps_enabled_for_auth(None));  // 功能未启用

    features.enable(Feature::Apps);
    assert!(!features.apps_enabled_for_auth(None));  // 无认证

    let api_key_auth = CodexAuth::from_api_key("test-api-key");
    assert!(!features.apps_enabled_for_auth(Some(&api_key_auth)));  // API Key 认证

    let chatgpt_auth = CodexAuth::create_dummy_chatgpt_auth_for_testing();
    assert!(features.apps_enabled_for_auth(Some(&chatgpt_auth)));  // ChatGPT 认证
}
```

## 关键代码路径与文件引用

### 被测试的核心方法

| 测试函数 | 被测方法/属性 |
|---------|--------------|
| `*_features_are_disabled_by_default` | `FeatureSpec::default_enabled` |
| `js_repl_is_experimental_*` | `Feature::info()`, `Stage::experimental_*` |
| `code_mode_only_requires_code_mode` | `Features::normalize_dependencies()` |
| `collab_is_legacy_alias_for_multi_agent` | `feature_for_key()` |
| `apps_require_feature_flag_and_chatgpt_auth` | `Features::apps_enabled_for_auth()` |

### 测试覆盖的功能枚举

测试直接引用的 `Feature` 变体：
- `Feature::UseLegacyLandlock`
- `Feature::UseLinuxSandboxBwrap`
- `Feature::JsRepl`
- `Feature::CodeModeOnly`
- `Feature::CodeMode`
- `Feature::GuardianApproval`
- `Feature::ExecPermissionApprovals`
- `Feature::RequestPermissionsTool`
- `Feature::ToolSuggest`
- `Feature::ImageGeneration`
- `Feature::ImageDetailOriginal`
- `Feature::Collab`
- `Feature::SpawnCsv`
- `Feature::Apps`

### 核心常量引用

```rust
// 测试遍历所有功能定义
for spec in FEATURES { ... }

// 动态包含 Node 版本文件
include_str!("../../node-version.txt")
```

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|-----|------|
| `pretty_assertions::assert_eq` | 清晰的断言差异输出 |
| `super::*` | 被测模块的所有公开项 |

### 被测模块依赖

| 依赖 | 用途 |
|-----|------|
| `auth.rs` | `CodexAuth` 类型用于认证测试 |
| `features/legacy.rs` | `feature_for_key()` 函数 |

### 测试数据文件

| 文件 | 用途 |
|-----|------|
| `codex-rs/node-version.txt` | JavaScript REPL 的 Node 版本要求 |

## 风险、边界与改进建议

### 当前风险点

1. **硬编码功能列表**：测试直接引用功能变体，新增功能时需要手动添加测试
2. **Node 版本文件依赖**：`node-version.txt` 路径硬编码，文件移动会导致测试失败
3. **认证 Mock 依赖**：`create_dummy_chatgpt_auth_for_testing()` 是测试专用方法

### 边界情况覆盖

| 边界情况 | 覆盖状态 |
|---------|---------|
| 功能生命周期规则 | ✅ 完全覆盖 |
| 功能依赖规范化 | ✅ 覆盖主要依赖 |
| 实验性功能元数据 | ⚠️ 仅覆盖 2 个示例 |
| 旧版别名映射 | ⚠️ 仅覆盖 2 个示例 |
| 认证集成 | ✅ 覆盖正负例 |

### 改进建议

1. **自动化生命周期测试**：
   当前测试遍历 `FEATURES` 常量，这是好的实践。建议增加：
   ```rust
   #[test]
   fn all_experimental_features_have_complete_metadata() {
       for spec in FEATURES {
           if let Stage::Experimental { name, menu_description, .. } = &spec.stage {
               assert!(!name.is_empty(), "{}: missing name", spec.key);
               assert!(!menu_description.is_empty(), "{}: missing description", spec.key);
           }
       }
   }
   ```

2. **所有别名覆盖测试**：
   ```rust
   #[test]
   fn all_legacy_aliases_resolve_correctly() {
       for key in legacy_feature_keys() {
           assert!(feature_for_key(key).is_some(), "alias {} should resolve", key);
       }
   }
   ```

3. **依赖循环检测测试**：
   ```rust
   #[test]
   fn no_circular_dependencies() {
       // 验证依赖图中无环
   }
   ```

4. **平台特定功能测试**：
   ```rust
   #[cfg(windows)]
   #[test]
   fn powershell_utf8_is_stable_on_windows() {
       assert_eq!(Feature::PowershellUtf8.stage(), Stage::Stable);
       assert_eq!(Feature::PowershellUtf8.default_enabled(), true);
   }
   ```

5. **遥测指标测试**：
   当前未测试 `emit_metrics` 方法，建议增加 mock 遥测验证

### 测试组织建议

当前所有测试在一个文件中，当功能数量增长时，可考虑按类别拆分：
- `features_lifecycle_tests.rs`
- `features_dependencies_tests.rs`
- `features_compat_tests.rs`
- `features_auth_tests.rs`
