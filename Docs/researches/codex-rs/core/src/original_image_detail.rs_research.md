# original_image_detail.rs 深度研究文档

## 场景与职责

`original_image_detail.rs` 是 Codex CLI 的图像细节级别控制模块，负责管理模型对原始分辨率图像的请求能力。该模块解决了以下核心问题：

1. **功能开关控制**：通过 Feature 标志控制 `detail: "original"` 功能的启用
2. **模型能力检测**：检查模型是否支持原始分辨率图像处理
3. **输入规范化**：根据功能和模型支持情况，规范化图像细节级别请求
4. **安全降级**：在不支持的情况下安全地降级到默认行为

## 功能点目的

### 1. 原始图像细节请求检查 (`can_request_original_image_detail`)
- **目的**：判断是否允许请求原始分辨率图像
- **条件**：
  - 功能标志 `ImageDetailOriginal` 必须启用
  - 模型必须声明支持 `supports_image_detail_original`

### 2. 图像细节级别规范化 (`normalize_output_image_detail`)
- **目的**：将用户/模型的图像细节请求转换为实际使用的值
- **行为**：
  - 如果请求 `Original` 且允许，则返回 `Some(ImageDetail::Original)`
  - 其他所有情况返回 `None`（使用模型默认）

## 具体技术实现

### 关键数据结构

```rust
// 来自 codex_protocol::models::ImageDetail
pub enum ImageDetail {
    Original,  // 原始分辨率
    Low,       // 低分辨率
    High,      // 高分辨率
    Auto,      // 自动选择
}

// 来自 crate::features::Feature
pub enum Feature {
    ImageDetailOriginal,  // 控制原始分辨率功能
    // ... 其他功能
}

// 来自 codex_protocol::openai_models::ModelInfo
pub struct ModelInfo {
    pub supports_image_detail_original: bool,
    // ... 其他字段
}
```

### 核心函数实现

```rust
/// 检查是否可以请求原始分辨率图像
pub(crate) fn can_request_original_image_detail(
    features: &Features,
    model_info: &ModelInfo,
) -> bool {
    model_info.supports_image_detail_original && features.enabled(Feature::ImageDetailOriginal)
}

/// 规范化图像细节级别输出
pub(crate) fn normalize_output_image_detail(
    features: &Features,
    model_info: &ModelInfo,
    detail: Option<ImageDetail>,
) -> Option<ImageDetail> {
    match detail {
        Some(ImageDetail::Original) if can_request_original_image_detail(features, model_info) => {
            Some(ImageDetail::Original)
        }
        Some(ImageDetail::Original) | Some(_) | None => None,
    }
}
```

### 决策矩阵

| 功能启用 | 模型支持 | 请求值 | 返回值 |
|----------|----------|--------|--------|
| true | true | Original | Some(Original) |
| true | false | Original | None |
| false | true | Original | None |
| false | false | Original | None |
| any | any | Low/High/Auto | None |
| any | any | None | None |

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 可见性 | 说明 |
|------|------|--------|------|
| `can_request_original_image_detail` | 6-11 | pub(crate) | 检查原始分辨率支持 |
| `normalize_output_image_detail` | 13-24 | pub(crate) | 规范化细节级别 |

### 依赖类型

```rust
// 功能标志
crate::features::Feature
crate::features::Features

// 协议类型
codex_protocol::models::ImageDetail
codex_protocol::openai_models::ModelInfo
```

### 调用方引用

- `crate::tools/js_repl/mod.rs` - JavaScript REPL 图像处理
- `crate::tools/handlers/view_image.rs` - 图像查看工具
- `crate::tools/spec.rs` - 工具规范定义

## 依赖与外部交互

### 上游依赖

1. **功能模块** (`crate::features`)
   - `Features` - 功能标志容器
   - `Feature::ImageDetailOriginal` - 原始分辨率功能标志

2. **协议模块** (`codex_protocol`)
   - `ImageDetail` - 图像细节级别枚举
   - `ModelInfo` - 模型信息（包含支持标志）

### 下游消费

1. **工具实现** - 在图像相关工具中调用以决定是否支持 `detail: "original"`
2. **工具规范** - 动态调整工具 schema 以包含/排除 `detail` 参数

## 风险、边界与改进建议

### 已知风险

1. **功能标志与模型支持不同步**
   - 功能标志启用但模型不支持时，功能静默禁用
   - 用户可能困惑为什么 `detail: "original"` 不起作用

2. **硬编码行为**
   - 非 `Original` 的所有细节级别都被映射为 `None`
   - 未来如果需要支持 `Low`/`High` 需要修改代码

3. **缺乏反馈**
   - 当请求被降级时，没有向用户或模型提供反馈
   - 可能导致模型困惑为什么图像质量不如预期

### 边界条件

| 场景 | 处理行为 |
|------|----------|
| `features` 为默认（无功能启用） | 返回 `None` |
| `model_info.supports_image_detail_original` 为 false | 返回 `None` |
| `detail` 为 `Some(Low)` | 返回 `None` |
| `detail` 为 `Some(High)` | 返回 `None` |
| `detail` 为 `Some(Auto)` | 返回 `None` |
| `detail` 为 `None` | 返回 `None` |

### 改进建议

1. **增强可观测性**
   - 添加日志记录，当请求被降级时记录原因
   - 向模型提供反馈，说明为什么 `detail: "original"` 不可用

2. **支持更多细节级别**
   - 扩展 `normalize_output_image_detail` 支持 `Low`/`High`/`Auto`
   - 根据模型能力和功能标志做出相应决策

3. **用户反馈**
   - 在 TUI 中显示当前图像处理模式
   - 当功能禁用时提供启用指导

4. **配置选项**
   - 添加配置项允许用户默认启用/禁用原始分辨率
   - 支持按模型类型设置默认细节级别

5. **文档完善**
   - 添加更多文档说明 `detail: "original"` 的使用场景
   - 记录哪些模型支持原始分辨率
