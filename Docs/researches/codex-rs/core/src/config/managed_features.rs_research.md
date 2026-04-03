# managed_features.rs 研究文档

## 场景与职责

`managed_features.rs` 实现了 Codex 特性标志（Feature Flags）的约束管理系统。它在 `Features`（原始特性集合）之上添加了一层约束验证，确保特性配置符合组织策略或管理员要求（通过 `requirements.toml` 定义）。

### 核心职责

1. **约束封装**：包装 `Features`，在构造和修改时强制执行约束
2. **固定特性管理**：支持从 `FeatureRequirementsToml` 解析的"固定"特性（pinned features）
3. **规范化处理**：自动规范化特性依赖关系（如启用 `SpawnCsv` 时自动启用 `Collab`）
4. **验证报告**：在约束冲突时提供清晰的错误信息，包括约束来源

### 使用场景

- **企业部署**：管理员通过 `requirements.toml` 强制启用/禁用特定特性
- **安全合规**：确保高风险特性（如 `WebSearchRequest`）在特定环境中被禁用
- **特性依赖**：自动处理特性间的依赖关系，避免配置不一致

---

## 功能点目的

### 1. ManagedFeatures 结构

```rust
#[derive(Debug, Clone, PartialEq)]
pub struct ManagedFeatures {
    value: ConstrainedWithSource<Features>,
    pinned_features: BTreeMap<Feature, bool>,
}
```

**字段说明**：
- `value`: 受约束的 `Features` 值，包含验证器和来源信息
- `pinned_features`: 从 requirements 解析的固定特性映射（特性 -> 必须的状态）

### 2. 约束验证流程

```rust
fn normalize_and_validate(&self, candidate: Features) -> ConstraintResult<Features> {
    // 1. 应用固定特性（覆盖用户配置）
    let normalized = normalize_candidate(candidate, &self.pinned_features);
    
    // 2. 验证是否满足 Constrained 的约束
    self.value.can_set(&normalized)?;
    
    // 3. 验证固定特性约束
    validate_pinned_features_constraint(&normalized, &self.pinned_features, self.value.source.as_ref())?;
    
    Ok(normalized)
}
```

### 3. 固定特性解析

```rust
fn parse_feature_requirements(
    feature_requirements: FeatureRequirementsToml,
    source: &RequirementSource,
) -> std::io::Result<BTreeMap<Feature, bool>> {
    let mut pinned_features = BTreeMap::new();
    for (key, enabled) in feature_requirements.entries {
        // 验证特性键名是否有效
        if let Some(feature) = canonical_feature_for_key(&key) {
            pinned_features.insert(feature, enabled);
        } else if let Some(feature) = feature_for_key(&key) {
            // 非规范键名（别名），返回错误提示使用规范键
            return Err(/* ... */);
        } else {
            // 未知特性键
            return Err(/* ... */);
        }
    }
    Ok(pinned_features)
}
```

---

## 具体技术实现

### 关键流程 1：ManagedFeatures 构造

```rust
pub(crate) fn from_configured(
    configured_features: Features,
    feature_requirements: Option<Sourced<FeatureRequirementsToml>>,
) -> std::io::Result<Self> {
    // 1. 解析 requirements 中的固定特性
    let (pinned_features, source) = match feature_requirements {
        Some(Sourced { value, source }) => {
            (parse_feature_requirements(value, &source)?, Some(source))
        }
        None => (BTreeMap::new(), None),
    };

    // 2. 规范化特性（应用固定值 + 依赖解析）
    let normalized_features = normalize_candidate(configured_features, &pinned_features);
    
    // 3. 验证固定特性约束
    validate_pinned_features(&normalized_features, &pinned_features, source.as_ref())?;
    
    // 4. 创建 ConstrainedWithSource 包装
    Ok(Self {
        value: ConstrainedWithSource::new(
            Constrained::allow_any(normalized_features), 
            source
        ),
        pinned_features,
    })
}
```

### 关键流程 2：特性规范化

```rust
fn normalize_candidate(
    mut candidate: Features,
    pinned_features: &BTreeMap<Feature, bool>,
) -> Features {
    // 1. 应用所有固定特性（覆盖用户配置）
    for (feature, enabled) in pinned_features {
        candidate.set_enabled(*feature, *enabled);
    }
    
    // 2. 规范化依赖关系（来自 features.rs）
    candidate.normalize_dependencies();
    
    candidate
}
```

依赖规范化逻辑（在 `features.rs` 中）：
```rust
pub(crate) fn normalize_dependencies(&mut self) {
    // SpawnCsv 依赖 Collab
    if self.enabled(Feature::SpawnCsv) && !self.enabled(Feature::Collab) {
        self.enable(Feature::Collab);
    }
    // CodeModeOnly 依赖 CodeMode
    if self.enabled(Feature::CodeModeOnly) && !self.enabled(Feature::CodeMode) {
        self.enable(Feature::CodeMode);
    }
    // JsReplToolsOnly 依赖 JsRepl（否则禁用）
    if self.enabled(Feature::JsReplToolsOnly) && !self.enabled(Feature::JsRepl) {
        tracing::warn!("js_repl_tools_only requires js_repl; disabling js_repl_tools_only");
        self.disable(Feature::JsReplToolsOnly);
    }
}
```

### 关键流程 3：固定特性约束验证

```rust
fn validate_pinned_features_constraint(
    normalized_features: &Features,
    pinned_features: &BTreeMap<Feature, bool>,
    source: Option<&RequirementSource>,
) -> ConstraintResult<()> {
    let Some(source) = source else { return Ok(()); };
    
    let allowed = feature_requirements_display(pinned_features);
    
    for (feature, enabled) in pinned_features {
        // 验证规范化后的特性状态与固定要求一致
        if normalized_features.enabled(*feature) != *enabled {
            return Err(ConstraintError::InvalidValue {
                field_name: "features",
                candidate: format!("{}={}", feature.key(), normalized_features.enabled(*feature)),
                allowed,
                requirement_source: source.clone(),
            });
        }
    }
    Ok(())
}
```

### 关键流程 4：配置验证入口

```rust
pub(crate) fn validate_feature_requirements_in_config_toml(
    cfg: &ConfigToml,
    feature_requirements: Option<&Sourced<FeatureRequirementsToml>>,
) -> std::io::Result<()> {
    // 验证默认 profile
    validate_profile(
        cfg,
        /*profile_name*/ None,
        &ConfigProfile::default(),
        feature_requirements,
    )?;
    
    // 验证每个命名 profile
    for (profile_name, profile) in &cfg.profiles {
        validate_profile(cfg, Some(profile_name), profile, feature_requirements)?;
    }
    Ok(())
}
```

---

## 关键代码路径与文件引用

### 核心数据结构

| 结构/枚举 | 位置 | 用途 |
|-----------|------|------|
| `ManagedFeatures` | `managed_features.rs:23-27` | 受约束的特性集合包装器 |
| `ConstrainedWithSource<T>` | `config/src/config_requirements.rs` | 带来源信息的约束值 |
| `Constrained<T>` | `config/src/constraint.rs:51-55` | 通用约束包装器 |
| `ConstraintError` | `config/src/constraint.rs:7-27` | 约束错误枚举 |
| `FeatureRequirementsToml` | `config/src/config_requirements.rs` | 特性需求 TOML 结构 |
| `RequirementSource` | `config/src/config_requirements.rs` | 约束来源（文件/云等） |

### 核心函数

| 函数 | 位置 | 用途 |
|------|------|------|
| `from_configured` | `managed_features.rs:30-51` | 从配置构造 ManagedFeatures |
| `normalize_and_validate` | `managed_features.rs:57-66` | 规范化并验证特性候选 |
| `can_set` | `managed_features.rs:68-70` | 检查是否可以设置特性 |
| `set` | `managed_features.rs:72-75` | 设置特性（带验证） |
| `set_enabled` | `managed_features.rs:77-81` | 启用/禁用单个特性 |
| `normalize_candidate` | `managed_features.rs:112-121` | 应用固定特性并规范化 |
| `validate_pinned_features_constraint` | `managed_features.rs:123-148` | 验证固定特性约束 |
| `parse_feature_requirements` | `managed_features.rs:167-195` | 解析特性需求 TOML |
| `explicit_feature_settings_in_config` | `managed_features.rs:197-257` | 提取显式特性设置 |
| `validate_explicit_feature_settings_in_config_toml` | `managed_features.rs:259-295` | 验证配置中的显式设置 |
| `validate_feature_requirements_in_config_toml` | `managed_features.rs:297-334` | 验证所有 profile 的特性配置 |

### 与 Features 的交互

```rust
// managed_features.rs 依赖 features.rs
use crate::features::Feature;
use crate::features::FeatureOverrides;
use crate::features::Features;
use crate::features::canonical_feature_for_key;
use crate::features::feature_for_key;

// Features 的关键方法
impl Features {
    pub fn enabled(&self, f: Feature) -> bool;
    pub fn set_enabled(&mut self, f: Feature, enabled: bool) -> &mut Self;
    pub(crate) fn normalize_dependencies(&mut self);
    pub fn from_config(cfg: &ConfigToml, config_profile: &ConfigProfile, overrides: FeatureOverrides) -> Self;
}
```

---

## 依赖与外部交互

### 直接依赖

```rust
// 标准库
use std::collections::BTreeMap;

// 内部 crate - codex-config
use codex_config::Constrained;
use codex_config::ConstrainedWithSource;
use codex_config::ConstraintError;
use codex_config::ConstraintResult;
use codex_config::FeatureRequirementsToml;
use codex_config::RequirementSource;
use codex_config::Sourced;

// 内部 crate - core
use crate::config::ConfigToml;
use crate::config::profile::ConfigProfile;
use crate::features::Feature;
use crate::features::FeatureOverrides;
use crate::features::Features;
use crate::features::canonical_feature_for_key;
use crate::features::feature_for_key;
```

### 依赖关系图

```
                    ┌─────────────────┐
                    │  requirements   │
                    │     .toml       │
                    └────────┬────────┘
                             │
                             ▼
┌──────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Features   │◄───│ ManagedFeatures │◄───│  Constrained<T> │
│  (原始集合)   │    │  (约束包装器)    │    │  (约束基础设施)  │
└──────────────┘    └─────────────────┘    └─────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  ConstraintError │
                    │   (错误报告)     │
                    └─────────────────┘
```

### 被调用方

| 调用方 | 位置 | 用途 |
|--------|------|------|
| `Config::load_config_with_layer_stack` | `config/mod.rs` | 加载配置时验证特性约束 |
| `validate_feature_requirements_in_config_toml` | `managed_features.rs:297` | 配置验证入口 |
| `ConfigService` | `config/service.rs` | 配置服务层 |

---

## 风险、边界与改进建议

### 已知风险

1. **约束验证时机**
   - 当前在构造和修改时验证，但直接修改底层 `Features` 可能绕过约束
   - `ManagedFeatures` 通过 `Deref` 暴露 `&Features`，但修改需通过 `set_enabled`

2. **错误信息清晰度**
   - 约束冲突时返回 `ConstraintError::InvalidValue`，但字段名固定为 `"features"`
   - 建议：包含具体的特性键名和 profile 上下文

3. **性能考虑**
   - 每次 `set_enabled` 都触发完整的规范化和验证流程
   - 批量修改时可能有性能开销

4. **测试覆盖**
   - 文件内无内联测试（依赖外部集成测试）
   - 建议：添加单元测试覆盖约束验证逻辑

### 边界情况

| 场景 | 当前行为 | 风险 |
|------|----------|------|
| 固定特性与依赖冲突 | 固定值优先，依赖自动调整 | 可能产生意外副作用 |
| 未知特性键 | 返回 `InvalidData` 错误 | 配置加载失败 |
| 非规范特性键（别名） | 返回错误，提示使用规范键 | 用户体验稍差 |
| 空固定特性列表 | 视为无约束，允许任意配置 | 符合预期 |
| 多个 profile 部分冲突 | 每个 profile 独立验证 | 可能产生不一致行为 |

### 改进建议

1. **添加批量修改 API**
   ```rust
   impl ManagedFeatures {
       pub fn set_multiple(&mut self, changes: &[(Feature, bool)]) -> ConstraintResult<()> {
           // 先验证所有变更，再批量应用
           let mut candidate = self.get().clone();
           for (feature, enabled) in changes {
               candidate.set_enabled(*feature, *enabled);
           }
           self.set(candidate)
       }
   }
   ```

2. **改进错误信息**
   ```rust
   // 当前
   ConstraintError::InvalidValue {
       field_name: "features",
       candidate: "web_search_request=true",
       allowed: "[web_search_request=false]",
       requirement_source: RequirementSource::File("/path/to/requirements.toml".into()),
   }
   
   // 建议
   ConstraintError::InvalidValue {
       field_name: "features.web_search_request",
       profile: Some("enterprise"),
       candidate: "true",
       allowed: "false (required by organizational policy)",
       requirement_source: RequirementSource::File("/etc/codex/requirements.toml".into()),
   }
   ```

3. **添加单元测试模块**
   ```rust
   #[cfg(test)]
   mod tests {
       use super::*;
       
       #[test]
       fn pinned_feature_enforced() {
           let requirements = FeatureRequirementsToml {
               entries: [("web_search_request".to_string(), false)].into(),
           };
           let sourced = Sourced {
               value: requirements,
               source: RequirementSource::Unknown,
           };
           
           let features = Features::with_defaults();
           let managed = ManagedFeatures::from_configured(features, Some(sourced))
               .expect("valid");
           
           assert!(!managed.enabled(Feature::WebSearchRequest));
           
           // 尝试启用应失败
           let result = managed.can_set({
               let mut f = managed.get().clone();
               f.enable(Feature::WebSearchRequest);
               f
           });
           assert!(result.is_err());
       }
   }
   ```

4. **优化依赖规范化**
   - 当前 `normalize_dependencies` 在 `features.rs` 中硬编码
   - 建议：使用声明式依赖图，支持更复杂的依赖关系
   ```rust
   // 建议的依赖声明
   const FEATURE_DEPENDENCIES: &[(Feature, Feature, DependencyKind)] = &[
       (Feature::SpawnCsv, Feature::Collab, DependencyKind::Requires),
       (Feature::CodeModeOnly, Feature::CodeMode, DependencyKind::Requires),
       (Feature::JsReplToolsOnly, Feature::JsRepl, DependencyKind::Requires),
   ];
   ```

5. **支持特性组**
   - 允许 requirements.toml 定义特性组，一次性约束多个相关特性
   ```toml
   [feature_groups.ai_capabilities]
   features = ["web_search_request", "image_generation", "js_repl"]
   default = false
   allowed = [false]  # 完全禁用 AI 特性组
   ```

### 代码质量指标

| 指标 | 当前状态 | 建议 |
|------|----------|------|
| 文档注释 | 良好 | 为公开 API 添加更多示例 |
| 单元测试 | 缺失 | 添加内联测试模块 |
| 错误处理 | 良好 | 改进错误信息的上下文 |
| 性能优化 | 一般 | 添加批量操作 API |
| 可扩展性 | 良好 | 考虑声明式依赖定义 |
