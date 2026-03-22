# original_image_detail_tests.rs 深度研究文档

## 场景与职责

`original_image_detail_tests.rs` 是 `original_image_detail.rs` 的配套测试模块，提供对图像细节级别控制逻辑的单元测试覆盖。测试验证功能标志和模型支持标志的组合行为。

## 功能点目的

### 1. 功能启用完整路径测试 (`image_detail_original_feature_enables_explicit_original_without_force`)
- **目的**：验证当功能启用且模型支持时，`detail: "original"` 正常工作
- **测试场景**：
  - 启用 `ImageDetailOriginal` 功能
  - 设置模型支持 `supports_image_detail_original`
  - 验证 `can_request_original_image_detail` 返回 true
  - 验证 `normalize_output_image_detail` 正确处理 `Original` 请求
  - 验证 `None` 输入返回 `None`

### 2. 缺失条件降级测试 (`explicit_original_is_dropped_without_feature_or_model_support`)
- **目的**：验证当任一条件不满足时，请求被降级为 `None`
- **测试场景**：
  - 功能启用但模型不支持 → 返回 `None`
  - 模型支持但功能未启用 → 返回 `None`

### 3. 非原始细节级别测试 (`unsupported_non_original_detail_is_dropped`)
- **目的**：验证非 `Original` 细节级别始终返回 `None`
- **测试场景**：请求 `ImageDetail::Low` 返回 `None`

## 具体技术实现

### 测试结构

```rust
use super::*;
use crate::config::test_config;
use crate::features::Features;
use crate::models_manager::manager::ModelsManager;
use pretty_assertions::assert_eq;
```

### 测试数据构造模式

```rust
// 创建测试配置
let config = test_config();

// 创建模型信息（使用离线测试辅助函数）
let mut model_info =
    ModelsManager::construct_model_info_offline_for_tests("gpt-5-codex", &config);
model_info.supports_image_detail_original = true;

// 启用功能
let mut features = Features::with_defaults();
features.enable(Feature::ImageDetailOriginal);

// 验证
assert!(can_request_original_image_detail(&features, &model_info));
assert_eq!(
    normalize_output_image_detail(&features, &model_info, Some(ImageDetail::Original)),
    Some(ImageDetail::Original)
);
```

### 模型信息修改

```rust
// 禁用模型支持
model_info.supports_image_detail_original = false;

// 或使用默认功能（未启用 ImageDetailOriginal）
let features = Features::with_defaults();
```

## 关键代码路径与文件引用

### 测试函数清单

| 测试函数 | 行号 | 测试目标 |
|----------|------|----------|
| `image_detail_original_feature_enables_explicit_original_without_force` | 8-26 | 完整启用路径 |
| `explicit_original_is_dropped_without_feature_or_model_support` | 28-48 | 降级路径 |
| `unsupported_non_original_detail_is_dropped` | 50-63 | 非原始级别处理 |

### 被测函数覆盖

| 被测函数 | 测试覆盖 |
|----------|----------|
| `can_request_original_image_detail` | `image_detail_original_feature_*`, `explicit_original_is_dropped_*` |
| `normalize_output_image_detail` | 所有测试 |

### 辅助函数使用

| 辅助函数 | 来源 | 用途 |
|----------|------|------|
| `test_config()` | `crate::config` | 创建测试配置 |
| `ModelsManager::construct_model_info_offline_for_tests` | `crate::models_manager` | 创建离线模型信息 |
| `Features::with_defaults()` | `crate::features` | 创建默认功能集 |
| `features.enable()` | `Features` | 启用特定功能 |

## 依赖与外部交互

### 测试依赖

```rust
// 被测模块
use super::*;

// 配置
crate::config::test_config

// 功能标志
crate::features::Features

// 模型管理器
crate::models_manager::manager::ModelsManager

// 断言增强
use pretty_assertions::assert_eq;
```

### 隐式依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `ImageDetail` | codex_protocol | 细节级别枚举 |
| `Feature` | crate::features | 功能标志枚举 |

## 风险、边界与改进建议

### 当前测试覆盖 gaps

1. **所有细节级别测试缺失**
   - 没有测试 `ImageDetail::High`
   - 没有测试 `ImageDetail::Auto`
   - 没有测试 `ImageDetail::Low` 的其他场景

2. **边界条件测试缺失**
   - 没有测试空功能集
   - 没有测试模型信息默认值

3. **组合测试缺失**
   - 没有测试功能标志和模型支持的矩阵组合

4. **错误场景测试缺失**
   - 没有测试无效输入处理（虽然当前 API 不允许）

### 改进建议

1. **添加完整细节级别测试**
```rust
#[test]
fn all_detail_levels_return_none_except_original_when_enabled() {
    let config = test_config();
    let mut model_info =
        ModelsManager::construct_model_info_offline_for_tests("gpt-5-codex", &config);
    model_info.supports_image_detail_original = true;
    let mut features = Features::with_defaults();
    features.enable(Feature::ImageDetailOriginal);

    // Original 应该工作
    assert_eq!(
        normalize_output_image_detail(&features, &model_info, Some(ImageDetail::Original)),
        Some(ImageDetail::Original)
    );

    // 其他级别应该返回 None
    for detail in [ImageDetail::Low, ImageDetail::High, ImageDetail::Auto] {
        assert_eq!(
            normalize_output_image_detail(&features, &model_info, Some(detail)),
            None,
            "{:?} should return None",
            detail
        );
    }
}
```

2. **添加矩阵测试**
```rust
#[test]
fn feature_and_model_support_matrix() {
    let cases = vec![
        (true, true, true),   // 功能启用 + 模型支持 = 允许
        (true, false, false), // 功能启用 + 模型不支持 = 不允许
        (false, true, false), // 功能禁用 + 模型支持 = 不允许
        (false, false, false), // 功能禁用 + 模型不支持 = 不允许
    ];

    for (feature_enabled, model_supports, expected) in cases {
        let config = test_config();
        let mut model_info =
            ModelsManager::construct_model_info_offline_for_tests("gpt-5-codex", &config);
        model_info.supports_image_detail_original = model_supports;
        
        let mut features = Features::with_defaults();
        if feature_enabled {
            features.enable(Feature::ImageDetailOriginal);
        }

        assert_eq!(
            can_request_original_image_detail(&features, &model_info),
            expected,
            "feature={}, model_supports={}",
            feature_enabled,
            model_supports
        );
    }
}
```

3. **使用参数化测试**
   - 使用 `rstest` 简化矩阵测试

4. **提取公共辅助函数**
```rust
fn create_test_context(
    feature_enabled: bool,
    model_supports: bool,
) -> (Features, ModelInfo) {
    let config = test_config();
    let mut model_info =
        ModelsManager::construct_model_info_offline_for_tests("gpt-5-codex", &config);
    model_info.supports_image_detail_original = model_supports;
    
    let mut features = Features::with_defaults();
    if feature_enabled {
        features.enable(Feature::ImageDetailOriginal);
    }
    
    (features, model_info)
}
```

### 测试代码质量建议

1. **减少重复代码**
   - 三个测试都重复了配置和模型信息创建，可以提取辅助函数

2. **改进断言消息**
   - 添加更多上下文到断言失败消息

3. **添加文档注释**
   - 为每个测试添加更详细的说明
