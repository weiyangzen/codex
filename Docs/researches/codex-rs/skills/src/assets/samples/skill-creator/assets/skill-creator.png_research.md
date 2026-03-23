# skill-creator.png 研究文档

## 场景与职责

`skill-creator.png` 是 skill-creator 技能的**大图标资源文件**，用于在 Codex 系统的 UI 界面中提供高分辨率的技能视觉标识。与小图标（`skill-creator-small.svg`）配合使用，满足不同场景下的展示需求。

**具体应用场景：**
1. **技能详情页** - 在技能信息面板、详情弹窗中展示
2. **技能选择器** - 在技能网格、卡片视图中作为缩略图
3. **欢迎/引导页面** - 在首次使用 skill-creator 时的引导界面
4. **文档展示** - 在相关文档或帮助页面中作为视觉元素

## 功能点目的

### 1. 高分辨率展示
- 提供 100x100 像素的位图图标，比小图标（20x20）具有更多细节
- 适用于需要清晰展示技能标识的场景

### 2. 视觉层次
- 与小图标形成大小对比，适应不同 UI 组件的显示需求
- 在详情视图中提供更丰富的视觉信息

### 3. 品牌一致性
- 与 `skill-creator-small.svg` 保持相同的设计语言（魔法棒/编辑主题）
- 确保用户在不同界面中都能识别 skill-creator 技能

## 具体技术实现

### 文件格式与规格

| 属性 | 值 |
|------|-----|
| 格式 | PNG (Portable Network Graphics) |
| 尺寸 | 100 x 100 像素 |
| 颜色深度 | 8-bit/color RGBA |
| 交错 | non-interlaced |
| 文件大小 | 1563 bytes |

### PNG 技术特性

**RGBA 颜色模式：**
- 支持透明度（Alpha 通道），可无缝叠加在各种背景上
- 8-bit 色深提供 256 级透明度，边缘平滑

**Non-interlaced：**
- 非交错格式，文件更小，加载更快
- 适合小尺寸图标，渐进加载收益不明显

### 嵌入与分发机制

与小图标相同，该文件通过 `include_dir` crate 在编译时嵌入：

```rust
// codex-rs/skills/src/lib.rs
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");

pub fn install_system_skills(codex_home: &Path) -> Result<(), SystemSkillsError> {
    // ... 解压逻辑
    write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest_system)?;
}
```

**指纹验证机制：**
- 使用 `embedded_system_skills_fingerprint()` 计算所有嵌入资源的哈希
- 通过 `SYSTEM_SKILLS_MARKER_FILENAME` 文件缓存指纹
- 避免不必要的重复解压操作

### 配置引用

在 `agents/openai.yaml` 中声明图标路径：

```yaml
interface:
  display_name: "Skill Creator"
  short_description: "Create or update a skill"
  icon_small: "./assets/skill-creator-small.svg"
  icon_large: "./assets/skill-creator.png"
```

## 关键代码路径与文件引用

### 当前文件
- **路径**: `codex-rs/skills/src/assets/samples/skill-creator/assets/skill-creator.png`
- **研究文档**: `/home/sansha/Github/codex/Docs/researches/codex-rs/skills/src/assets/samples/skill-creator/assets/skill-creator.png_research.md`

### 相关文件

| 文件路径 | 关系 | 说明 |
|---------|------|------|
| `agents/openai.yaml` | 配置引用 | 声明图标路径 `icon_large: "./assets/skill-creator.png"` |
| `skill-creator-small.svg` | 配对文件 | 小图标版本（20x20 SVG） |
| `SKILL.md` | 文档 | skill-creator 技能的主文档 |
| `codex-rs/skills/src/lib.rs` | 嵌入逻辑 | 系统技能嵌入与安装逻辑 |
| `codex-rs/core/src/skills/loader.rs` | 运行时加载 | 解析 `icon_large` 路径 |
| `codex-rs/core/src/skills/model.rs` | 数据模型 | `SkillInterface.icon_large: Option<PathBuf>` |
| `codex-rs/protocol/src/protocol.rs` | 协议定义 | `SkillInterface` 结构体定义 |
| `codex-rs/tui/src/chatwidget/skills.rs` | UI 使用 | TUI 技能列表渲染 |

### 代码引用链

```
UI 层 (TUI/App Server)
    ↓
SkillInterface.icon_large: Option<PathBuf>
    ↓ (解析自)
agents/openai.yaml::interface.icon_large
    ↓ (指向)
./assets/skill-creator.png
    ↓ (编译时嵌入)
include_dir!($CARGO_MANIFEST_DIR/src/assets/samples)
    ↓ (运行时解压)
CODEX_HOME/skills/.system/skill-creator/assets/skill-creator.png
```

### 跨平台协议定义

**Rust 结构体** (`codex-rs/core/src/skills/model.rs`):
```rust
pub struct SkillInterface {
    pub display_name: String,
    pub short_description: String,
    pub icon_small: Option<PathBuf>,
    pub icon_large: Option<PathBuf>,
    // ...
}
```

**TypeScript 定义** (`app-server-protocol/src/protocol/v2.rs`):
```rust
pub struct SkillInterface {
    pub icon_small: Option<PathBuf>,
    pub icon_large: Option<PathBuf>,
    // ...
}
```

**Python 生成代码** (`sdk/python/src/codex_app_server/generated/v2_all.py`):
```python
class SkillInterface(BaseModel):
    icon_large: Annotated[str | None, Field(alias="iconLarge")] = None
    icon_small: Annotated[str | None, Field(alias="iconSmall")] = None
```

## 依赖与外部交互

### 编译时依赖
- **`include_dir` crate**: 编译时资源嵌入
- **`build.rs`**: 监控资源变更，触发重新编译

### 运行时依赖
- **文件系统 I/O**: 解压到用户目录
- **PNG 解码器**: UI 层需要支持 PNG 渲染
- **图像缓存**: 建议 UI 层缓存解码后的图像数据

### 与其他组件的交互

| 组件 | 交互方式 | 说明 |
|------|---------|------|
| TUI | 图像协议 | 通过 iTerm2/Sixel 等协议显示 |
| App Server | HTTP 响应 | 可作为静态资源提供 |
| Python SDK | 类型定义 | 通过 `v2_all.py` 暴露给 Python |

### 同类资源对比

| 技能 | 小图标 | 大图标 | 尺寸 |
|------|--------|--------|------|
| skill-creator | `skill-creator-small.svg` | `skill-creator.png` | 20x20 / 100x100 |
| skill-installer | `skill-installer-small.svg` | `skill-installer.png` | 20x20 / 100x100 |
| openai-docs | `openai-small.svg` | `openai.png` | 20x20 / 100x100 |

## 风险、边界与改进建议

### 潜在风险

1. **位图缩放失真**
   - PNG 为位图格式，缩放会失真
   - 如果在高 DPI 屏幕上显示大于 100x100，会出现模糊
   - **缓解**: 考虑提供 `@2x` 版本（200x200）或改用 SVG

2. **文件大小**
   - 1563 bytes 对于 100x100 PNG 合理，但大量技能累积会增加二进制体积
   - **监控**: 单个图标不应超过 10KB

3. **透明度兼容性**
   - RGBA 格式在某些旧版终端或图像库中可能不支持
   - **边界**: 主要面向现代终端和 UI 框架

4. **路径安全问题**
   - 与 SVG 相同，`icon_large` 路径需要验证防止目录遍历
   - **缓解**: `loader.rs` 中的路径解析应限制在技能目录内

### 边界条件

| 边界 | 说明 |
|------|------|
| 尺寸限制 | 大图标 100x100 是约定俗成的标准，不宜过大 |
| 格式限制 | PNG 为位图，缩放会失真 |
| 颜色限制 | RGBA 8-bit，满足大多数 UI 需求 |
| 路径限制 | 必须位于 `./assets/` 子目录下 |

### 改进建议

1. **高 DPI 支持**
   - 添加 `skill-creator@2x.png`（200x200）版本
   - 在 `openai.yaml` 中扩展格式支持多分辨率：
     ```yaml
     icon_large: ["./assets/skill-creator.png", "./assets/skill-creator@2x.png"]
     ```

2. **格式优化**
   - 考虑使用 WebP 格式替代 PNG，体积可减少 20-30%
   - 或考虑使用 SVG 作为大图标，完全避免缩放问题

3. **验证增强**
   - 在 `quick_validate.py` 中添加：
     - PNG 格式验证（魔数检查）
     - 尺寸验证（确保 100x100）
     - 文件大小检查（防止意外的大文件）

4. **动态生成**
   - 考虑在编译时从 SVG 自动生成 PNG，确保两者一致性
   - 使用 `resvg` 或类似工具进行高质量渲染

5. **缓存策略**
   - UI 层应缓存解码后的图像数据，避免重复 IO
   - 可考虑内存映射（mmap）大图标文件

6. **文档完善**
   - 在 `references/openai_yaml.md` 中补充图标资源规范：
     - 推荐尺寸（小图标 20x20，大图标 100x100）
     - 推荐格式（小图标 SVG，大图标 PNG）
     - 设计指南（主题一致性、可识别性）
