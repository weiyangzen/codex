# openai.png 研究文档

## 场景与职责

`openai.png` 是 OpenAI Docs Skill 的大尺寸图标文件，用于在 Codex CLI 的 TUI（终端用户界面）和 App Server 中作为 OpenAI 文档 Skill 的主要视觉标识。与小图标 (`openai-small.svg`) 配合使用，该文件在需要更大尺寸展示的 UI 场景中使用，如 Skill 详情页、插件市场展示、欢迎界面等。

该文件位于 `codex-rs/skills/src/assets/samples/openai-docs/assets/` 目录下，是 `codex-rs/skills` crate 的编译时嵌入资源的一部分，随系统内置 Skill 一起分发。

## 功能点目的

1. **主视觉标识**：在 Skill 详情、插件市场、设置页面等需要大尺寸图标的场景展示
2. **品牌展示**：作为 OpenAI 品牌的视觉代表，增强用户对 Skill 功能的认知
3. **多尺寸适配**：与 `icon_small` 形成大小图标组合，适应不同 UI 组件的显示需求
4. **视觉层次**：在复杂的 UI 界面中提供清晰的视觉锚点，帮助用户快速定位 OpenAI 相关功能

## 具体技术实现

### 文件格式与规格

- **格式**：PNG（便携式网络图形）
- **尺寸**：100×100 像素（通过 `file` 命令确认）
- **颜色深度**：8-bit/color RGB（24位真彩色）
- **压缩**：非交错式 (non-interlaced)
- **文件大小**：1429 字节

### 文件属性验证

```bash
$ file openai.png
PNG image data, 100 x 100, 8-bit/color RGB, non-interlaced
```

### 引用方式

在 `agents/openai.yaml` 中通过相对路径引用：

```yaml
interface:
  display_name: "OpenAI Docs"
  short_description: "Reference official OpenAI docs, including upgrade guidance"
  icon_small: "./assets/openai-small.svg"
  icon_large: "./assets/openai.png"
  default_prompt: "Look up official OpenAI docs, load relevant GPT-5.4 upgrade references when applicable, and answer with concise, cited guidance."
```

### 资源加载与处理流程

1. **编译时嵌入**：
   - 通过 `include_dir::include_dir!` 宏将 `src/assets/samples` 目录嵌入到二进制中
   - 位于 `codex-rs/skills/src/lib.rs:12`

2. **运行时安装**：
   - `install_system_skills()` 函数在 Codex 启动时执行
   - 计算嵌入目录的指纹 (fingerprint) 与磁盘标记文件比对
   - 若指纹不匹配或标记不存在，将嵌入资源解压到 `CODEX_HOME/skills/.system/openai-docs/assets/`

3. **路径解析**：
   - `codex-core/src/skills/loader.rs` 中的 `resolve_asset_path()` 处理图标路径
   - 验证规则：
     - 必须是相对路径（禁止绝对路径）
     - 必须位于 `assets/` 子目录下
     - 禁止包含 `..` 父目录引用（防止路径遍历）
   - 解析后的绝对路径存储在 `SkillInterface.icon_large` 字段中

4. **UI 渲染**：
   - TUI 使用 `ratatui` 的图像渲染能力显示 PNG
   - App Server 通过 HTTP API 提供图标资源访问

## 关键代码路径与文件引用

### 定义与配置
- `codex-rs/skills/src/assets/samples/openai-docs/agents/openai.yaml:5` - 图标路径配置
- `codex-rs/skills/src/assets/samples/openai-docs/assets/openai.png` - 本文件

### 资源管理
- `codex-rs/skills/src/lib.rs:12` - 系统 Skill 目录嵌入声明
  ```rust
  const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
  ```
- `codex-rs/skills/src/lib.rs:47-78` - `install_system_skills()` 安装逻辑
- `codex-rs/skills/src/lib.rs:87-99` - `embedded_system_skills_fingerprint()` 指纹计算
- `codex-rs/skills/src/lib.rs:120-154` - `write_embedded_dir()` 资源写入

### 路径解析与验证
- `codex-rs/core/src/skills/loader.rs:783-829` - `resolve_asset_path()` 核心解析逻辑
  ```rust
  fn resolve_asset_path(skill_dir: &Path, field: &'static str, path: Option<PathBuf>) -> Option<PathBuf>
  ```
- `codex-rs/core/src/skills/loader.rs:706-707` - Skill 接口图标字段处理
  ```rust
  icon_small: resolve_asset_path(skill_dir, "interface.icon_small", interface.icon_small),
  icon_large: resolve_asset_path(skill_dir, "interface.icon_large", interface.icon_large),
  ```
- `codex-rs/core/src/skills/loader.rs:717-718` - 图标存在性检查
- `codex-rs/core/src/skills/model.rs:59-60` - Skill 接口模型定义
  ```rust
  pub icon_small: Option<PathBuf>,
  pub icon_large: Option<PathBuf>,
  ```

### 使用位置
- `codex-rs/tui/src/chatwidget/skills.rs:172` - TUI Skill 列表大图标显示
- `codex-rs/tui_app_server/src/chatwidget/skills.rs:172` - TUI App Server Skill 列表
- `codex-rs/app-server/src/codex_message_processor.rs:7559` - App Server 消息处理中的图标传递
- `codex-rs/app-server/src/codex_message_processor.rs:7600` - Skill 信息响应
- `codex-rs/protocol/src/protocol.rs:2964` - 协议定义

### 协议接口
- `codex-rs/app-server-protocol/src/protocol/v2.rs:3177` - V2 协议 SkillInterface 定义
  ```rust
  pub icon_large: Option<PathBuf>,
  ```

## 依赖与外部交互

### 内部依赖

| 组件 | 路径 | 职责 |
|------|------|------|
| skills crate | `codex-rs/skills/src/lib.rs` | 编译时嵌入和运行时安装 |
| core/loader | `codex-rs/core/src/skills/loader.rs` | Skill 加载和路径解析验证 |
| core/model | `codex-rs/core/src/skills/model.rs` | Skill 数据结构定义 |
| tui | `codex-rs/tui/src/chatwidget/skills.rs` | TUI 界面图标渲染 |
| app-server | `codex-rs/app-server/src/codex_message_processor.rs` | HTTP API 图标服务 |
| protocol | `codex-rs/protocol/src/protocol.rs` | 跨组件协议定义 |

### 外部依赖

- **OpenAI 品牌资产**：PNG 图像基于 OpenAI 官方品牌标识设计
- **PNG 解码库**：TUI 和 App Server 依赖系统或 Rust 生态的 PNG 解码能力
- **文件系统**：运行时依赖 `CODEX_HOME` 环境变量确定安装位置

### 相关 Skill 配置

在 `skill-creator` Skill 的参考文档中定义了图标配置规范：
- `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md:11-12`
  ```yaml
  icon_small: "./assets/small-400px.png"
  icon_large: "./assets/large-logo.svg"
  ```

## 风险、边界与改进建议

### 风险

1. **文件大小**：PNG 为位图格式，100×100 像素虽不大，但若 Skill 数量增多，总体资源占用会增加。当前 1429 字节在可接受范围内。

2. **分辨率适配**：固定 100×100 像素在高 DPI 显示器上可能显得模糊，缺乏多倍图 (@2x, @3x) 支持。

3. **路径安全**：`resolve_asset_path()` 已实施严格验证：
   - 绝对路径被拒绝并记录警告
   - 包含 `..` 的路径被拒绝
   - 非 `assets/` 目录下的路径被拒绝
   这防止了路径遍历攻击，但配置错误会导致图标无法显示。

4. **格式兼容性**：PNG 格式通用性好，但在某些终端（如纯文本终端）无法显示，需要 TUI 具备图像渲染能力。

### 边界

- **尺寸限制**：100×100 像素是大图标的标准尺寸，适用于详情页、卡片等场景
- **格式限制**：PNG 为位图，缩放会失真。对于需要频繁缩放的场景，SVG 更合适（如 `icon_small`）
- **颜色空间**：8-bit RGB，不支持透明通道（虽然 PNG 支持，但此文件未使用）
- **更新机制**：资源更新需要重新编译 `codex-rs/skills` crate 并发布新版本

### 改进建议

1. **多分辨率支持**：
   - 提供 `openai@2x.png` (200×200) 和 `openai@3x.png` (300×300)
   - 在 YAML 中支持数组格式：`icon_large: ["./assets/openai.png", "./assets/openai@2x.png"]`

2. **格式优化**：
   - 考虑使用 WebP 格式减少文件大小
   - 或使用有损 PNG 压缩进一步减小体积

3. **动态主题适配**：
   - 提供暗色/亮色版本：`openai-dark.png` / `openai-light.png`
   - 在 YAML 中增加主题感知配置

4. **验证与测试**：
   - 添加 CI 检查确保 PNG 文件格式正确、尺寸符合规范
   - 添加测试验证图标文件在嵌入-解压-加载流程中完整性保持

5. **文档完善**：
   - 在 `skill-creator` 文档中补充图标设计规范
   - 明确推荐尺寸、格式、命名约定
   - 提供图标模板或生成工具

6. **懒加载优化**：
   - 当前所有系统 Skill 资源在启动时全部解压
   - 可考虑按需解压，仅在 Skill 首次被访问时解压其资源
