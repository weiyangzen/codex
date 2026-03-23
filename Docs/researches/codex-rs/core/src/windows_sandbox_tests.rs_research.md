# windows_sandbox_tests.rs 研究文档

## 场景与职责

`windows_sandbox_tests.rs` 是 `windows_sandbox.rs` 的配套测试模块，负责验证 Windows 沙盒配置解析逻辑的正确性。测试覆盖：

1. **特性标志解析**：验证从 `Features` 解析 `WindowsSandboxLevel`
2. **配置优先级**：验证 profile、全局配置、legacy features 的优先级
3. **私有桌面配置**：验证 `sandbox_private_desktop` 设置解析

注意：这些测试主要验证配置解析逻辑，不涉及实际的 Windows 沙盒操作。

## 功能点目的

### 测试用例设计意图

| 测试函数 | 目的 |
|----------|------|
| `elevated_flag_works_by_itself` | 验证提升特性标志单独工作 |
| `restricted_token_flag_works_by_itself` | 验证受限令牌特性标志单独工作 |
| `no_flags_means_no_sandbox` | 验证默认无沙盒 |
| `elevated_wins_when_both_flags_are_enabled` | 验证提升优先于受限 |
| `legacy_mode_prefers_elevated` | 验证 legacy 配置中提升优先 |
| `legacy_mode_supports_alias_key` | 验证旧别名键支持 |
| `resolve_windows_sandbox_mode_prefers_profile_windows` | 验证 profile 配置优先 |
| `resolve_windows_sandbox_mode_falls_back_to_legacy_keys` | 验证 legacy 回退 |
| `resolve_windows_sandbox_mode_profile_legacy_false_blocks_top_level_legacy_true` | 验证 profile false 覆盖全局 true |
| `resolve_windows_sandbox_private_desktop_prefers_profile_windows` | 验证私有桌面 profile 优先 |
| `resolve_windows_sandbox_private_desktop_defaults_to_true` | 验证私有桌面默认 true |
| `resolve_windows_sandbox_private_desktop_respects_explicit_cfg_value` | 验证全局配置生效 |

## 具体技术实现

### 测试 1-4：特性标志解析

```rust
#[test]
fn elevated_flag_works_by_itself()
#[test]
fn restricted_token_flag_works_by_itself()
#[test]
fn no_flags_means_no_sandbox()
#[test]
fn elevated_wins_when_both_flags_are_enabled()
```

**技术点**：
- 使用 `Features::with_defaults()` 创建默认特性集
- 使用 `features.enable(Feature::WindowsSandboxElevated)` 启用特性
- 验证 `WindowsSandboxLevel::from_features()` 返回值

### 测试 5-6：Legacy 配置解析

```rust
#[test]
fn legacy_mode_prefers_elevated()
#[test]
fn legacy_mode_supports_alias_key()
```

**技术点**：
- 使用 `BTreeMap` 构造 legacy features
- 测试 `legacy_windows_sandbox_mode_from_entries()`
- 验证别名键 `enable_experimental_windows_sandbox`

### 测试 7-9：配置优先级

```rust
#[test]
fn resolve_windows_sandbox_mode_prefers_profile_windows()
#[test]
fn resolve_windows_sandbox_mode_falls_back_to_legacy_keys()
#[test]
fn resolve_windows_sandbox_mode_profile_legacy_false_blocks_top_level_legacy_true()
```

**技术点**：
- 构造 `ConfigToml` 和 `ConfigProfile`
- 测试 `resolve_windows_sandbox_mode()`
- 验证优先级：profile.windows > cfg.windows > profile.features (legacy) > cfg.features (legacy)

### 测试 10-12：私有桌面配置

```rust
#[test]
fn resolve_windows_sandbox_private_desktop_prefers_profile_windows()
#[test]
fn resolve_windows_sandbox_private_desktop_defaults_to_true()
#[test]
fn resolve_windows_sandbox_private_desktop_respects_explicit_cfg_value()
```

**技术点**：
- 构造带 `sandbox_private_desktop` 的 `WindowsToml`
- 测试 `resolve_windows_sandbox_private_desktop()`
- 验证默认值为 `true`

## 关键代码路径与文件引用

### 被测试代码

| 被测试项 | 定义位置 |
|----------|----------|
| `WindowsSandboxLevel::from_features` | `windows_sandbox.rs:39` |
| `legacy_windows_sandbox_mode_from_entries` | `windows_sandbox.rs:107` |
| `resolve_windows_sandbox_mode` | `windows_sandbox.rs:59` |
| `resolve_windows_sandbox_private_desktop` | `windows_sandbox.rs:78` |

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `Features` | 构造测试特性集 |
| `Feature` | 特性标志枚举 |
| `ConfigToml` | 全局配置 |
| `ConfigProfile` | Profile 配置 |
| `WindowsToml` | Windows 特定配置 |
| `WindowsSandboxModeToml` | 沙盒模式配置 |
| `FeaturesToml` | Legacy 特性配置 |
| `BTreeMap` | 构造 legacy features |
| `pretty_assertions::assert_eq` | 更好的断言输出 |

## 依赖与外部交互

### 配置数据结构

测试大量使用配置结构：

```rust
let cfg = ConfigToml {
    windows: Some(WindowsToml {
        sandbox: Some(WindowsSandboxModeToml::Unelevated),
        ..Default::default()
    }),
    ..Default::default()
};
let profile = ConfigProfile {
    windows: Some(WindowsToml {
        sandbox: Some(WindowsSandboxModeToml::Elevated),
        ..Default::default()
    }),
    ..Default::default()
};
```

### 无外部系统交互

这些测试是纯单元测试：
- 无文件系统操作
- 无网络调用
- 无 Windows API 调用

## 风险、边界与改进建议

### 当前测试覆盖的不足

1. **缺少实际设置测试**
   - 未测试 `run_windows_sandbox_setup`
   - 需要 Windows 环境

2. **缺少错误处理测试**
   - 未测试配置无效时的行为
   - 未测试设置失败的处理

3. **缺少遥测测试**
   - 未验证指标发射

4. **缺少并发测试**
   - 未测试多线程配置访问

5. **缺少边界值测试**
   - 空配置
   - 部分填充的配置

### 改进建议

1. **添加配置验证测试**
```rust
#[test]
fn handles_empty_config() {
    let cfg = ConfigToml::default();
    let profile = ConfigProfile::default();
    assert_eq!(
        resolve_windows_sandbox_mode(&cfg, &profile),
        None
    );
}
```

2. **添加冲突配置测试**
```rust
#[test]
fn handles_conflicting_legacy_and_new_config() {
    // 同时设置 legacy features 和 windows.sandbox
    // 验证行为
}
```

3. **添加平台检测测试（条件编译）**
```rust
#[cfg(target_os = "windows")]
mod windows_specific_tests {
    // 测试实际设置流程
}
```

4. **添加性能测试**
```rust
#[test]
fn config_resolution_is_fast() {
    // 多次解析配置，验证性能
}
```

### 潜在风险

1. **测试与实现耦合**
   - 测试依赖具体配置结构
   - 结构变更需要更新测试

2. **优先级逻辑复杂**
   - 多层优先级容易出错
   - 需要清晰的文档

3. **Legacy 迁移**
   - 旧配置格式需要长期支持
   - 测试需要维护

### 测试质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 覆盖率 | 高 | 配置解析逻辑覆盖良好 |
| 可读性 | 高 | 测试命名清晰，意图明确 |
| 维护性 | 中 | 依赖配置结构 |
| 可靠性 | 高 | 纯单元测试，无外部依赖 |
| 文档价值 | 高 | 测试用例展示了优先级规则 |

### 配置优先级总结（从测试推导）

```
resolve_windows_sandbox_mode 优先级：
1. profile.windows.sandbox
2. cfg.windows.sandbox
3. profile.features (legacy)
4. cfg.features (legacy)

resolve_windows_sandbox_private_desktop 优先级：
1. profile.windows.sandbox_private_desktop
2. cfg.windows.sandbox_private_desktop
3. 默认值: true
```
