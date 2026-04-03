# tooltips.txt 研究文档

## 场景与职责

`tooltips.txt` 是 Codex TUI 启动时显示的随机提示语文本文件。这些提示语向用户介绍 Codex CLI 的各种功能、快捷键和最佳实践，帮助用户发现和使用高级特性。

## 功能点目的

1. **用户引导**：向新用户介绍基本功能和快捷键
2. **功能发现**：帮助用户发现不明显的特性（如 `/compact`, `/fork`）
3. **社区连接**：引导用户加入 Discord 和论坛
4. **随机展示**：通过随机选择增加探索乐趣，避免重复感

## 具体技术实现

### 文件格式

纯文本文件，每行一个提示语：

```
Use /compact when the conversation gets long to summarize history and free up context.
Start a fresh idea with /new; the previous session stays in history.
...
```

### 加载和过滤机制

在 `src/tooltips.rs` 中通过 `include_str!` 编译时嵌入：

```rust
const RAW_TOOLTIPS: &str = include_str!("../tooltips.txt");

lazy_static! {
    static ref TOOLTIPS: Vec<&'static str> = RAW_TOOLTIPS
        .lines()
        .map(str::trim)
        .filter(|line| {
            if line.is_empty() || line.starts_with('#') {
                return false;
            }
            // 非 macOS/Windows 平台过滤掉 "codex app" 相关提示
            if !IS_MACOS && !IS_WINDOWS && line.contains("codex app") {
                return false;
            }
            true
        })
        .collect();
}
```

### 提示语选择逻辑

```rust
pub(crate) fn get_tooltip(plan: Option<PlanType>, fast_mode_enabled: bool) -> Option<String> {
    let mut rng = rand::rng();

    // 优先检查远程公告
    if let Some(announcement) = announcement::fetch_announcement_tip() {
        return Some(announcement);
    }

    // 80% 概率显示付费用户专属提示
    if rng.random_ratio(8, 10) {
        match plan {
            Some(PlanType::Plus | PlanType::Business | PlanType::Team | 
                 PlanType::Enterprise | PlanType::Pro) => {
                return Some(pick_paid_tooltip(&mut rng, fast_mode_enabled).to_string());
            }
            Some(PlanType::Go) | Some(PlanType::Free) => {
                return Some(FREE_GO_TOOLTIP.to_string());
            }
            _ => { /* 回退到随机提示 */ }
        }
    }

    // 20% 概率显示通用随机提示
    pick_tooltip(&mut rng).map(str::to_string)
}
```

### 提示语分类

#### 1. 命令提示（斜杠命令）
- `/compact` - 压缩对话历史
- `/new` - 开始新会话
- `/feedback` - 发送反馈
- `/model` - 切换模型
- `/permissions` - 控制确认提示
- `/review` - 代码审查
- `/skills` - 列出可用技能
- `/status` - 查看状态
- `/statusline` - 配置状态栏
- `/fork` - 分支当前对话
- `/init` - 创建 AGENTS.md
- `/mcp` - 列出 MCP 工具
- `/personality` - 自定义沟通风格
- `/rename` - 重命名线程

#### 2. 快捷键提示
- `Esc` - 返回并编辑上一条消息
- `Tab` - 自动补全斜杠命令
- `Ctrl+V` - 粘贴图片
- `!` - 执行 shell 命令

#### 3. 社区和资源
- OpenAI 开发者文档 MCP
- OpenAI Discord 社区
- Codex 社区论坛

#### 4. 应用推广
- `codex app` - 启动 Codex Desktop（macOS/Windows）

### 平台过滤

```rust
const IS_MACOS: bool = cfg!(target_os = "macos");
const IS_WINDOWS: bool = cfg!(target_os = "windows");

// 非 macOS/Windows 平台过滤 "codex app" 提示
if !IS_MACOS && !IS_WINDOWS && line.contains("codex app") {
    return false;
}
```

### 远程公告系统

```rust
const ANNOUNCEMENT_TIP_URL: &str = 
    "https://raw.githubusercontent.com/openai/codex/main/announcement_tip.toml";
```

支持从远程获取临时公告，优先级高于本地提示语。

## 关键代码路径与文件引用

### 调用链

```
tooltips.txt
    ↓ (编译时嵌入)
src/tooltips.rs::RAW_TOOLTIPS
    ↓ (lazy_static 过滤)
src/tooltips.rs::TOOLTIPS
    ↓ (运行时选择)
src/tooltips.rs::get_tooltip()
    ↓
启动时显示在 UI 中
```

### 相关文件

| 文件 | 职责 |
|------|------|
| `src/tooltips.rs` | 提示语加载、过滤、选择逻辑 |
| `src/lib.rs` | 调用 `tooltips::announcement::prewarm()` 预热公告缓存 |
| `BUILD.bazel` | `compile_data` 包含 tooltips.txt |
| `announcement_tip.toml` (远程) | 临时公告配置 |

### 预热机制

```rust
// src/lib.rs::run_ratatui_app()
tooltips::announcement::prewarm();

// src/tooltips.rs
pub(crate) fn prewarm() {
    let _ = thread::spawn(|| ANNOUNCEMENT_TIP.get_or_init(init_announcement_tip_in_thread));
}
```

在 TUI 启动时后台线程预取远程公告，避免阻塞 UI。

## 依赖与外部交互

### 运行时依赖

| 依赖 | 用途 |
|------|------|
| `rand` | 随机提示语选择 |
| `lazy_static` | 静态初始化过滤后的提示语列表 |
| `reqwest` | 远程公告获取 |
| `chrono` | 公告日期验证 |
| `regex-lite` | 版本正则匹配 |

### 外部服务

```
GitHub Raw (announcement_tip.toml)
    ↓
reqwest::blocking::Client
    ↓
解析 TOML 公告配置
    ↓
日期/版本/目标应用匹配
    ↓
显示匹配的公告
```

### 公告 TOML 格式

```toml
[[announcements]]
content = "New feature announcement"
from_date = "2024-01-01"
to_date = "2024-12-31"
version_regex = "^1\\.\\d+\\.\\d+$"
target_app = "cli"
```

## 风险、边界与改进建议

### 潜在风险

1. **网络依赖**：远程公告获取失败时无优雅降级（已实现：返回 None）
2. **内容过时**：本地提示语可能随功能迭代而过时
3. **平台差异**：Linux 用户看不到 Desktop 应用相关提示，可能错过功能

### 边界条件

1. **空文件处理**：`TOOLTIPS.is_empty()` 检查，返回 None
2. **网络超时**：`Duration::from_millis(2000)` 2秒超时
3. **代理绕过**：`no_proxy()` 避免 macOS 系统配置崩溃 (#8912)

### 改进建议

1. **动态提示语更新**：
   ```rust
   // 建议：定期同步远程提示语
   pub async fn sync_tooltips() -> Result<Vec<String>> {
       fetch_remote_tooltips().await
   }
   ```

2. **用户偏好学习**：
   ```rust
   // 建议：根据用户使用模式推荐相关提示
   if user_uses_feature_x_less_than(3) {
       prioritize_tooltip_about_feature_x();
   }
   ```

3. **提示语分类标签**：
   ```
   # tooltips.txt
   [beginner] Use /compact when the conversation gets long...
   [advanced] Use /fork to branch the current chat...
   [shortcut] Press Tab to autocomplete slash commands...
   ```

4. **国际化支持**：
   ```
   tooltips/
   ├── en.txt
   ├── zh.txt
   └── ja.txt
   ```

5. **提示语效果追踪**：
   ```rust
   // 建议：追踪用户看到提示后是否使用了相关功能
   telemetry::track("tooltip_shown", &tooltip_id);
   telemetry::track("feature_used_after_tooltip", &feature_id);
   ```

6. **A/B 测试框架**：
   ```rust
   // 建议：支持测试不同提示语的效果
   if experiment::is_in_group("new_onboarding_tips") {
       show_experimental_tooltips();
   }
   ```

7. **用户禁用选项**：
   ```toml
   # config.toml
   [ui]
   show_tooltips = false
   ```

8. **提示语搜索**：
   ```
   > /tips search "compact"
   Found: "Use /compact when the conversation gets long..."
   ```
