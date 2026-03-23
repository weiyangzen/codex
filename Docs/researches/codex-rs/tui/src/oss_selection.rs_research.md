# oss_selection.rs 深入研究

## 场景与职责

`oss_selection.rs` 是 Codex TUI 中负责**开源模型提供商（OSS Provider）选择**的模块。当用户首次使用 Codex 或需要切换本地模型服务时，提供交互式界面选择 LM Studio 或 Ollama 作为后端提供商。

### 核心场景

1. **首次启动配置**：新用户首次运行 Codex 时选择本地模型服务
2. **多服务检测**：自动检测本地运行的模型服务
3. **自动选择**：当只有一个服务运行时自动选择
4. **偏好保存**：记住用户选择作为默认提供商

### 支持的提供商

| 提供商 | 协议 | 默认端口 | 标识符 |
|--------|------|----------|--------|
| LM Studio | 本地服务器 | 1234 | `lmstudio` |
| Ollama (Responses API) | 本地服务器 | 11434 | `ollama` |

## 功能点目的

### 1. ProviderStatus - 服务状态

```rust
#[derive(Clone)]
enum ProviderStatus {
    Running,      // 服务运行中（绿色 ●）
    NotRunning,   // 服务未运行（红色 ○）
    Unknown,      // 状态未知（黄色 ?）
}
```

### 2. SelectOption - 选择选项

```rust
struct SelectOption {
    label: Line<'static>,        // 显示标签（如 "LM Studio"）
    description: &'static str,   // 描述文本
    key: KeyCode,                // 快捷键（如 'l'）
    provider_id: &'static str,   // 提供商 ID
}
```

### 3. OssSelectionWidget - 选择组件

```rust
pub struct OssSelectionWidget<'a> {
    select_options: &'a Vec<SelectOption>,
    confirmation_prompt: Paragraph<'a>,
    selected_option: usize,      // 当前选中索引
    done: bool,                  // 是否完成
    selection: Option<String>,   // 选择结果
}
```

### 4. 核心函数

#### `select_oss_provider(codex_home) -> io::Result<String>`

主入口函数，流程：
1. 检测 LM Studio 状态
2. 检测 Ollama 状态
3. 自动选择（仅一个运行时）
4. 显示交互式选择界面
5. 保存用户偏好

## 具体技术实现

### 服务检测流程

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
```

### 端口检测实现

```rust
async fn check_port_status(port: u16) -> io::Result<bool> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(2))  // 2秒超时
        .build()
        .map_err(io::Error::other)?;
    
    let url = format!("http://localhost:{port}");
    
    match client.get(&url).send().await {
        Ok(response) => Ok(response.status().is_success()),
        Err(_) => Ok(false),  // 连接失败 = 未运行
    }
}
```

### 自动选择逻辑

```rust
match (&lmstudio_status, &ollama_status) {
    (ProviderStatus::Running, ProviderStatus::NotRunning) => {
        return Ok(LMSTUDIO_OSS_PROVIDER_ID.to_string());
    }
    (ProviderStatus::NotRunning, ProviderStatus::Running) => {
        return Ok(OLLAMA_OSS_PROVIDER_ID.to_string());
    }
    _ => {
        // 都运行或都未运行 - 显示 UI
    }
}
```

### UI 渲染结构

```
┌─────────────────────────────────────────┐
│                                         │
│  ? Select an open-source provider       │  // 标题（蓝色 ? + 粗体）
│                                         │
│    Choose which local AI server...      │  // 说明
│                                         │
│    ● LM Studio                          │  // 状态指示器
│    ○ Ollama (Responses)                 │
│    ○ Ollama (Chat)                      │
│                                         │
│    ● Running  ○ Not Running             │  // 图例
│                                         │
│    Press Enter to select • Ctrl+C...    │  // 操作提示
│                                         │
│  Select provider?                       │
│                                         │
│  [  LM Studio  ]  [  Ollama  ]          │  // 选择按钮
│                                         │
│    Local LM Studio server...            │  // 选中项描述
│                                         │
└─────────────────────────────────────────┘
```

### 键盘事件处理

```rust
fn handle_select_key(&mut self, key_event: KeyEvent) {
    match key_event.code {
        KeyCode::Char('c') if key_event.modifiers.contains(CONTROL) => {
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
            self.send_decision(LMSTUDIO_OSS_PROVIDER_ID.to_string());  // 默认选择
        }
        other => {
            // 快捷键匹配（不区分大小写）
            let normalized = Self::normalize_keycode(other);
            if let Some(opt) = self.select_options.iter()
                .find(|opt| Self::normalize_keycode(opt.key) == normalized) {
                self.send_decision(opt.provider_id.to_string());
            }
        }
    }
}
```

### 偏好保存

```rust
if let Ok(ref provider) = result
    && let Err(e) = set_default_oss_provider(codex_home, provider)
{
    tracing::warn!("Failed to save OSS provider preference: {e}");
}
```

## 关键代码路径

### 1. 主流程（行 290-343）

```rust
pub async fn select_oss_provider(codex_home: &std::path::Path) -> io::Result<String> {
    // 检测服务状态
    let lmstudio_status = check_lmstudio_status().await;
    let ollama_status = check_ollama_status().await;
    
    // 自动选择逻辑
    match (&lmstudio_status, &ollama_status) {
        (Running, NotRunning) => return Ok(LMSTUDIO_OSS_PROVIDER_ID.to_string()),
        (NotRunning, Running) => return Ok(OLLAMA_OSS_PROVIDER_ID.to_string()),
        _ => {}
    }
    
    // 创建组件
    let mut widget = OssSelectionWidget::new(lmstudio_status, ollama_status)?;
    
    // 设置终端
    enable_raw_mode()?;
    execute!(stdout(), EnterAlternateScreen)?;
    
    // 事件循环
    let result = loop {
        terminal.draw(|f| (&widget).render_ref(f.area(), f.buffer_mut()))?;
        if let Event::Key(key_event) = event::read()?
            && let Some(selection) = widget.handle_key_event(key_event)
        {
            break Ok(selection);
        }
    };
    
    // 恢复终端
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    
    // 保存偏好
    if let Ok(ref provider) = result {
        let _ = set_default_oss_provider(codex_home, provider);
    }
    
    result
}
```

### 2. 组件渲染（行 232-280）

```rust
impl WidgetRef for &OssSelectionWidget<'_> {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // 分割区域：提示区 + 响应区
        let [prompt_chunk, response_chunk] = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(prompt_height), Constraint::Min(0)])
            .areas(area);
        
        // 渲染选择按钮
        let lines: Vec<Line> = self.select_options.iter().enumerate()
            .map(|(idx, opt)| {
                let style = if idx == self.selected_option {
                    Style::new().bg(Color::Cyan).fg(Color::Black)  // 选中
                } else {
                    Style::new().bg(Color::DarkGray)  // 未选中
                };
                opt.label.clone().alignment(Alignment::Center).style(style)
            })
            .collect();
        
        // 水平布局按钮
        let areas = Layout::horizontal(...).split(button_area);
        for (idx, area) in areas.iter().enumerate() {
            lines[idx].render(*area, buf);
        }
        
        // 渲染描述
        Line::from(self.select_options[self.selected_option].description)
            .style(Style::new().italic().fg(Color::DarkGray))
            .render(description_area, buf);
    }
}
```

### 3. 状态符号映射（行 282-288）

```rust
fn get_status_symbol_and_color(status: &ProviderStatus) -> (&'static str, Color) {
    match status {
        ProviderStatus::Running => ("●", Color::Green),
        ProviderStatus::NotRunning => ("○", Color::Red),
        ProviderStatus::Unknown => ("?", Color::Yellow),
    }
}
```

## 依赖与外部交互

### 直接依赖

| 模块 | 用途 |
|------|------|
| `codex_core::DEFAULT_LMSTUDIO_PORT` | LM Studio 默认端口（1234） |
| `codex_core::DEFAULT_OLLAMA_PORT` | Ollama 默认端口（11434） |
| `codex_core::LMSTUDIO_OSS_PROVIDER_ID` | 提供商标识符 |
| `codex_core::OLLAMA_OSS_PROVIDER_ID` | 提供商标识符 |
| `codex_core::config::set_default_oss_provider` | 保存偏好设置 |
| `crossterm` | 终端控制和事件处理 |
| `ratatui` | TUI 渲染 |
| `reqwest` | HTTP 服务检测 |

### 常量定义

```rust
// codex-rs/core/src/model_provider_info.rs
pub const DEFAULT_LMSTUDIO_PORT: u16 = 1234;
pub const DEFAULT_OLLAMA_PORT: u16 = 11434;
pub const LMSTUDIO_OSS_PROVIDER_ID: &str = "lmstudio";
pub const OLLAMA_OSS_PROVIDER_ID: &str = "ollama";
```

### 被调用方

- **应用初始化**：首次启动或需要选择提供商时调用
- **配置管理**：保存和加载默认提供商偏好

## 风险、边界与改进建议

### 已知风险

1. **硬编码端口**：
   - 使用默认端口检测，如果用户配置了非标准端口会检测失败
   - 建议支持配置自定义端口

2. **简单 HTTP 检测**：
   - 仅检查端口是否响应 HTTP，不验证实际 API 可用性
   - 可能有误报（其他服务占用端口）

3. **超时设置**：
   - 2秒超时在慢网络环境下可能不够
   - 建议可配置或自适应

4. **无取消处理**：
   - 返回 `__CANCELLED__` 字符串，调用方需特殊处理
   - 建议使用 `Result` 的 `Err` 变体

### 边界情况处理

| 场景 | 处理方式 |
|------|----------|
| 都未运行 | 显示 UI，用户手动选择 |
| 都运行 | 显示 UI，用户手动选择 |
| 检测超时 | 标记为 Unknown |
| 连接错误 | 标记为 NotRunning |
| Ctrl+C | 返回 `__CANCELLED__` |
| Esc | 默认选择 LM Studio |
| 窗口大小变化 | 下次渲染时适应 |

### 测试覆盖

当前模块**无显式测试**，依赖集成测试验证：
- 建议添加单元测试覆盖：
  - 状态检测模拟
  - 键盘事件处理
  - 自动选择逻辑
  - 渲染输出验证

### 改进建议

1. **端口配置**：支持自定义端口检测
2. **API 验证**：检测实际 API 端点而非仅端口
3. **更多提供商**：支持其他本地模型服务（如 LocalAI, text-generation-webui）
4. **健康检查**：定期刷新状态指示器
5. **搜索发现**：支持局域网内自动发现服务
6. **连接测试**：选择后验证实际可用性
7. **错误详情**：显示连接失败的具体原因
8. **取消语义**：使用类型安全的取消结果而非魔术字符串

## 文件引用汇总

- **本文件**：`codex-rs/tui/src/oss_selection.rs` (373 lines)
- **模型提供商信息**：`codex-rs/core/src/model_provider_info.rs`
- **配置管理**：`codex-rs/core/src/config.rs`
