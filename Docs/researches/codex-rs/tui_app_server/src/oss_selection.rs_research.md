# oss_selection.rs 深入研究

## 场景与职责

`oss_selection.rs` 是 Codex TUI 中负责**开源模型(OSS)提供商选择**的模块。当用户使用 `--oss` 标志启动但未配置具体提供商时，显示交互式UI让用户选择使用 LM Studio 还是 Ollama。

### 核心场景

1. **OSS模式启动**：用户使用 `codex --oss` 启动，需要选择本地AI服务器
2. **自动检测**：自动检测本地 LM Studio 和 Ollama 服务器的运行状态
3. **自动选择**：如果只有一个服务器运行，自动选择该服务器
4. **交互选择**：如果多个或未检测到服务器，显示TUI选择界面
5. **偏好保存**：记住用户选择，下次自动使用

### 支持的提供商

| 提供商 | 协议ID | 默认端口 | 描述 |
|--------|--------|----------|------|
| LM Studio | `lmstudio` | 1234 | 本地LM Studio服务器 |
| Ollama (Responses) | `ollama` | 11434 | Ollama Responses API |
| Ollama (Chat) | `ollama-chat` | 11434 | Ollama Chat API |

## 功能点目的

### 1. 提供商选项结构

```rust
#[derive(Clone)]
struct ProviderOption {
    name: String,
    status: ProviderStatus,
}

#[derive(Clone)]
enum ProviderStatus {
    Running,      // 运行中（绿色●）
    NotRunning,   // 未运行（红色○）
    Unknown,      // 未知（黄色?）
}
```

### 2. 选择选项配置

```rust
struct SelectOption {
    label: Line<'static>,           // 显示标签（带下划线快捷键）
    description: &'static str,      // 描述文本
    key: KeyCode,                   // 快捷键
    provider_id: &'static str,      // 提供商ID
}

static OSS_SELECT_OPTIONS: LazyLock<Vec<SelectOption>> = LazyLock::new(|| {
    vec![
        SelectOption {
            label: Line::from(vec!["L".underlined(), "M Studio".into()]),
            description: "Local LM Studio server (default port 1234)",
            key: KeyCode::Char('l'),
            provider_id: LMSTUDIO_OSS_PROVIDER_ID,  // "lmstudio"
        },
        SelectOption {
            label: Line::from(vec!["O".underlined(), "llama".into()]),
            description: "Local Ollama server (Responses API, default port 11434)",
            key: KeyCode::Char('o'),
            provider_id: OLLAMA_OSS_PROVIDER_ID,    // "ollama"
        },
    ]
});
```

### 3. 主选择部件

```rust
pub struct OssSelectionWidget<'a> {
    select_options: &'a Vec<SelectOption>,
    confirmation_prompt: Paragraph<'a>,
    selected_option: usize,     // 当前选中索引
    done: bool,                 // 是否完成
    selection: Option<String>, // 选择的提供商ID
}
```

### 4. 状态检测

```rust
async fn check_lmstudio_status() -> ProviderStatus {
    match check_port_status(DEFAULT_LMSTUDIO_PORT).await {
        Ok(true) => ProviderStatus::Running,
        Ok(false) => ProviderStatus::NotRunning,
        Err(_) => ProviderStatus::Unknown,
    }
}

async fn check_ollama_status() -> ProviderStatus {
    match check_port_status(DEFAULT_OLLAMA_PORT).await {
        Ok(true) => ProviderStatus::Running,
        Ok(false) => ProviderStatus::NotRunning,
        Err(_) => ProviderStatus::Unknown,
    }
}

async fn check_port_status(port: u16) -> io::Result<bool> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(2))
        .build()?;
    let url = format!("http://localhost:{port}");
    match client.get(&url).send().await {
        Ok(response) => Ok(response.status().is_success()),
        Err(_) => Ok(false),
    }
}
```

**检测逻辑**：
- 2秒超时
- 检查 `http://localhost:{port}` 是否返回成功状态
- 连接失败视为未运行

### 5. 自动选择逻辑

```rust
match (&lmstudio_status, &ollama_status) {
    (ProviderStatus::Running, ProviderStatus::NotRunning) => {
        return Ok(LMSTUDIO_OSS_PROVIDER_ID.to_string());
    }
    (ProviderStatus::NotRunning, ProviderStatus::Running) => {
        return Ok(OLLAMA_OSS_PROVIDER_ID.to_string());
    }
    _ => {
        // 都运行或都未运行，显示UI
    }
}
```

### 6. 主入口函数

```rust
pub async fn select_oss_provider(codex_home: &std::path::Path) -> io::Result<String>
```

**流程**：
1. 检测 LM Studio 和 Ollama 状态
2. 如果只有一个运行，自动返回
3. 否则创建 `OssSelectionWidget`
4. 启用原始模式，进入备用屏幕
5. 事件循环处理键盘输入
6. 退出时恢复终端状态
7. 保存用户偏好到配置

## 具体技术实现

### 1. 键盘事件处理

```rust
pub fn handle_key_event(&mut self, key: KeyEvent) -> Option<String> {
    if key.kind == KeyEventKind::Press {
        self.handle_select_key(key);
    }
    if self.done {
        self.selection.clone()
    } else {
        None
    }
}

fn handle_select_key(&mut self, key_event: KeyEvent) {
    match key_event.code {
        KeyCode::Char('c') if key_event.modifiers.contains(KeyModifiers::CONTROL) => {
            self.send_decision("__CANCELLED__".to_string());
        }
        KeyCode::Left => {
            self.selected_option = (self.selected_option + self.select_options.len() - 1)
                % self.select_options.len();
        }
        KeyCode::Right => {
            self.selected_option = (self.selected_option + 1) % self.select_options.len();
        }
        KeyCode::Enter => {
            let opt = &self.select_options[self.selected_option];
            self.send_decision(opt.provider_id.to_string());
        }
        KeyCode::Esc => {
            self.send_decision(LMSTUDIO_OSS_PROVIDER_ID.to_string());  // Esc默认选择LM Studio
        }
        other => {
            let normalized = Self::normalize_keycode(other);
            if let Some(opt) = self.select_options.iter()
                .find(|opt| Self::normalize_keycode(opt.key) == normalized) {
                self.send_decision(opt.provider_id.to_string());
            }
        }
    }
}
```

**快捷键映射**：
- `Ctrl+C`：取消（返回 `"__CANCELLED__"`）
- `←/→`：切换选项
- `Enter`：确认选择
- `Esc`：默认选择 LM Studio
- `l/L`：选择 LM Studio
- `o/O`：选择 Ollama

### 2. 界面渲染

```rust
impl WidgetRef for &OssSelectionWidget<'_> {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // 布局：提示区域 + 响应区域
        let [prompt_chunk, response_chunk] = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(prompt_height), Constraint::Min(0)])
            .areas(area);

        // 响应区域：标题 + 按钮 + 描述
        let [title_area, button_area, description_area] = Layout::vertical([...])
            .areas(response_chunk.inner(Margin::new(1, 0)));

        // 按钮样式
        let style = if idx == self.selected_option {
            Style::new().bg(Color::Cyan).fg(Color::Black)    // 选中：青底黑字
        } else {
            Style::new().bg(Color::DarkGray)                  // 未选中：深灰底
        };
    }
}
```

**界面元素**：
- 标题："? Select an open-source provider"
- 状态指示：● Running / ○ Not Running / ? Unknown
- 按钮：LM Studio / Ollama（带高亮）
- 描述：当前选中项的详细说明
- 底部提示："Press Enter to select • Ctrl+C to exit"

### 3. 状态符号

```rust
fn get_status_symbol_and_color(status: &ProviderStatus) -> (&'static str, Color) {
    match status {
        ProviderStatus::Running => ("●", Color::Green),
        ProviderStatus::NotRunning => ("○", Color::Red),
        ProviderStatus::Unknown => ("?", Color::Yellow),
    }
}
```

### 4. 偏好保存

```rust
if let Ok(ref provider) = result
    && let Err(e) = set_default_oss_provider(codex_home, provider)
{
    tracing::warn!("Failed to save OSS provider preference: {e}");
}
```

保存到 Codex 配置，下次启动时自动使用。

## 关键代码路径与文件引用

### 直接依赖

| 文件/模块 | 依赖类型 | 用途 |
|-----------|----------|------|
| `codex_core::DEFAULT_LMSTUDIO_PORT` | 外部crate | LM Studio默认端口（1234） |
| `codex_core::DEFAULT_OLLAMA_PORT` | 外部crate | Ollama默认端口（11434） |
| `codex_core::LMSTUDIO_OSS_PROVIDER_ID` | 外部crate | 提供商ID常量 |
| `codex_core::OLLAMA_OSS_PROVIDER_ID` | 外部crate | 提供商ID常量 |
| `codex_core::config::set_default_oss_provider` | 外部crate | 保存用户偏好 |
| `crossterm` | 外部crate | 终端控制和事件处理 |
| `ratatui` | 外部crate | UI渲染 |
| `reqwest` | 外部crate | HTTP状态检测 |

### 调用方

| 文件 | 使用方式 |
|------|----------|
| `lib.rs` | `select_oss_provider(&codex_home).await` |

### 在 lib.rs 中的使用

```rust
// lib.rs
if cli.oss {
    let resolved = resolve_oss_provider(
        cli.oss_provider.as_deref(),
        &config_toml,
        cli.config_profile.clone(),
    );

    if let Some(provider) = resolved {
        Some(provider)
    } else {
        // 未配置提供商，提示用户选择
        let provider = oss_selection::select_oss_provider(&codex_home).await?;
        if provider == "__CANCELLED__" {
            return Err(std::io::Error::other(
                "OSS provider selection was cancelled by user",
            ));
        }
        Some(provider)
    }
}
```

### 常量定义

```rust
// codex-rs/core/src/lib.rs 或类似位置
pub const DEFAULT_LMSTUDIO_PORT: u16 = 1234;
pub const DEFAULT_OLLAMA_PORT: u16 = 11434;
pub const LMSTUDIO_OSS_PROVIDER_ID: &str = "lmstudio";
pub const OLLAMA_OSS_PROVIDER_ID: &str = "ollama";
```

## 依赖与外部交互

### 外部crate依赖

```rust
use std::io;
use std::sync::LazyLock;
use codex_core::DEFAULT_LMSTUDIO_PORT;
use codex_core::DEFAULT_OLLAMA_PORT;
use codex_core::LMSTUDIO_OSS_PROVIDER_ID;
use codex_core::OLLAMA_OSS_PROVIDER_ID;
use codex_core::config::set_default_oss_provider;
use crossterm::event::Event;
use crossterm::event::KeyCode;
use crossterm::event::KeyEvent;
use crossterm::event::KeyEventKind;
use crossterm::event::{self};
use crossterm::execute;
use crossterm::terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode};
use ratatui::Terminal;
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Alignment, Constraint, Direction, Layout, Margin, Rect};
use ratatui::prelude::*;
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Paragraph, Widget, WidgetRef, Wrap};
use std::time::Duration;
```

### HTTP检测流程

```
select_oss_provider()
    ├── check_lmstudio_status()
    │       └── check_port_status(1234)
    │               └── reqwest GET http://localhost:1234
    ├── check_ollama_status()
    │       └── check_port_status(11434)
    │               └── reqwest GET http://localhost:11434
    └── 根据状态决定自动选择或显示UI
```

### 与配置系统的集成

```rust
// 保存偏好
codex_core::config::set_default_oss_provider(codex_home, provider);

// 下次启动时解析
codex_core::config::resolve_oss_provider(
    cli.oss_provider.as_deref(),  // 命令行覆盖
    &config_toml,                  // 配置文件
    cli.config_profile.clone(),    // 配置profile
);
```

## 风险、边界与改进建议

### 已知风险

1. **硬编码端口**：LM Studio 和 Ollama 的默认端口硬编码，如果用户修改了端口则检测失败
2. **简单HTTP检测**：只检查端口是否响应HTTP，不验证实际API可用性
3. **无重试机制**：单次请求失败即标记为未运行，可能因临时网络问题误判
4. **终端状态恢复**：如果进程异常终止，可能遗留备用屏幕状态

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 两个服务器都运行 | 显示UI让用户选择 |
| 两个服务器都未运行 | 显示UI，用户仍可选择（可能知道服务器即将启动） |
| 检测超时 | 标记为 Unknown（黄色?） |
| 用户取消 | 返回 `"__CANCELLED__"`，上层退出 |
| 保存偏好失败 | 记录警告，不影响当前选择 |
| 终端尺寸过小 | 使用 `Wrap { trim: false }` 自动换行 |

### 改进建议

1. **配置支持**：
   - 支持从配置文件读取自定义端口
   - 支持配置检测超时时间
   - 支持禁用自动检测

2. **检测增强**：
   - 添加API端点验证（不仅检查端口响应）
   - 添加重试机制（如3次尝试）
   - 支持检测远程服务器（不仅localhost）

3. **用户体验**：
   - 添加"测试连接"按钮，验证选择的服务器可用
   - 显示服务器版本信息（如果API支持）
   - 添加"记住我的选择"复选框

4. **可访问性**：
   - 添加颜色之外的标识（如文字标签）
   - 支持屏幕阅读器

5. **错误处理**：
   - 更详细的错误信息（区分连接拒绝、超时、无效响应）
   - 提供故障排除建议

6. **测试覆盖**：
   - 当前无单元测试，建议添加：
     - 键盘事件处理测试
     - 状态检测模拟测试
     - 渲染快照测试

7. **代码质量**：
   - `OssSelectionWidget::new` 中硬编码了3个提供商选项，但只显示2个，代码不一致
   - 提取常量字符串到资源文件
   - 使用 builder 模式构造复杂的Paragraph

### 相关代码问题

```rust
// 第95-109行：创建了3个ProviderOption，但UI只显示2个
let providers = vec![
    ProviderOption { name: "LM Studio".to_string(), status: lmstudio_status },
    ProviderOption { name: "Ollama (Responses)".to_string(), status: ollama_status.clone() },
    ProviderOption { name: "Ollama (Chat)".to_string(), status: ollama_status },  // 未在UI中使用
];
```

**建议**：清理未使用的代码，或添加对 Ollama Chat API 的UI支持。

### 安全考虑

1. **本地主机限制**：只检测 `localhost`，避免向外部网络发送请求
2. **短超时**：2秒超时防止长时间阻塞
3. **无认证**：检测请求不需要认证，避免泄露凭证
