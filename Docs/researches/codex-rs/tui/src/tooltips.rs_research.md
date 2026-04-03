# tooltips.rs 深度研究文档

## 场景与职责

`tooltips.rs` 是 Codex TUI 中负责**启动提示（Tooltip）**的模块。它在 Codex 启动时向用户显示随机或有针对性的提示信息，包括功能介绍、产品推广和公告通知。

### 核心职责

1. **随机提示选择**：从提示池中选择随机提示显示
2. **用户分层提示**：根据用户计划类型（PlanType）显示不同提示
3. **平台适配**：根据操作系统（macOS/Windows/其他）调整提示内容
4. **公告系统**：支持从远程 URL 获取动态公告
5. **提示预热**：后台线程预加载公告内容

### 使用场景

- Codex CLI 启动时显示欢迎提示
- 向付费用户推广 Codex App 和 Fast 模式
- 向免费用户介绍功能
- 显示限时活动公告

---

## 功能点目的

### 1. 提示分类

| 类型 | 目标用户 | 内容 |
|------|----------|------|
| 付费用户提示 | Plus/Business/Team/Enterprise/Pro | Codex App 推广、Fast 模式 |
| 免费用户提示 | Go/Free | 免费使用通知 |
| 其他用户提示 | 未识别计划 | 通用推广 |
| 实验性提示 | 所有用户 | 实验性功能公告 |

### 2. 平台特定提示

```rust
const PAID_TOOLTIP: &str = "*New* Try the **Codex App** with 2x rate limits...";
const PAID_TOOLTIP_WINDOWS: &str = "*New* Try the **Codex App**, now available on **Windows**...";
const PAID_TOOLTIP_NON_MAC: &str = "*New* 2x rate limits until *April 2nd*.";
```

### 3. 公告系统

- **远程获取**：从 GitHub raw URL 获取 TOML 格式公告
- **缓存机制**：使用 `OnceLock` 缓存公告内容
- **后台预热**：`prewarm()` 函数在后台线程预加载
- **条件过滤**：支持按日期、版本、目标应用过滤

### 4. 提示池

- **静态提示**：从 `tooltips.txt` 文件加载
- **实验性提示**：从 `FEATURES` 数组动态生成
- **过滤逻辑**：排除平台不相关的提示（如非 macOS 排除 "codex app" 提示）

---

## 具体技术实现

### 关键流程

#### 1. 提示选择流程

```rust
pub(crate) fn get_tooltip(plan: Option<PlanType>, fast_mode_enabled: bool) -> Option<String> {
    let mut rng = rand::rng();

    // 1. 优先检查公告
    if let Some(announcement) = announcement::fetch_announcement_tip() {
        return Some(announcement);
    }

    // 2. 80% 概率显示针对性提示
    if rng.random_ratio(8, 10) {
        match plan {
            Some(PlanType::Plus | PlanType::Business | PlanType::Team | 
                 PlanType::Enterprise | PlanType::Pro) => {
                return Some(pick_paid_tooltip(&mut rng, fast_mode_enabled).to_string());
            }
            Some(PlanType::Go | PlanType::Free) => {
                return Some(FREE_GO_TOOLTIP.to_string());
            }
            _ => { /* 回退到通用提示 */ }
        }
    }

    // 3. 20% 概率显示随机提示
    pick_tooltip(&mut rng).map(str::to_string)
}
```

#### 2. 付费用户提示选择

```rust
fn pick_paid_tooltip<R: Rng + ?Sized>(rng: &mut R, fast_mode_enabled: bool) -> &'static str {
    if fast_mode_enabled || rng.random_bool(0.5) {
        paid_app_tooltip()  // Codex App 推广
    } else {
        FAST_TOOLTIP        // Fast 模式推广
    }
}
```

**策略**：
- 已启用 Fast 模式的用户只看到 App 推广
- 未启用 Fast 模式的用户 50/50 看到 App 或 Fast 推广

#### 3. 公告获取流程

```rust
fn blocking_init_announcement_tip() -> Option<String> {
    // 1. 构建 HTTP 客户端（禁用代理避免 macOS 问题）
    let client = reqwest::blocking::Client::builder()
        .no_proxy()
        .build()
        .ok()?;
    
    // 2. 发送请求（2 秒超时）
    let response = client
        .get(ANNOUNCEMENT_TIP_URL)
        .timeout(Duration::from_millis(2000))
        .send()
        .ok()?;
    
    // 3. 返回文本内容
    response.error_for_status().ok()?.text().ok()
}
```

#### 4. 公告解析和过滤

```rust
pub(crate) fn parse_announcement_tip_toml(text: &str) -> Option<String> {
    // 1. 解析 TOML（支持两种格式）
    let announcements = toml::from_str::<AnnouncementTipDocument>(text)
        .map(|doc| doc.announcements)
        .or_else(|_| toml::from_str::<Vec<AnnouncementTipRaw>>(text))
        .ok()?;

    // 2. 过滤匹配的公告
    let mut latest_match = None;
    let today = Utc::now().date_naive();
    for raw in announcements {
        let Some(tip) = AnnouncementTip::from_raw(raw) else { continue };
        if tip.version_matches(CODEX_CLI_VERSION)
            && tip.date_matches(today)
            && tip.target_app == "cli"
        {
            latest_match = Some(tip.content);
        }
    }
    latest_match
}
```

### 数据结构

```rust
// 公告原始数据（TOML 反序列化）
#[derive(Debug, Deserialize)]
struct AnnouncementTipRaw {
    content: String,
    from_date: Option<String>,
    to_date: Option<String>,
    version_regex: Option<String>,
    target_app: Option<String>,
}

// 内部使用的公告结构
struct AnnouncementTip {
    content: String,
    from_date: Option<NaiveDate>,
    to_date: Option<NaiveDate>,
    version_regex: Option<Regex>,
    target_app: String,
}
```

---

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `version::CODEX_CLI_VERSION` | `version.rs` | 版本匹配 |
| `app_event::AppEvent` | `app_event.rs` | 应用事件（通过调用方） |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `codex_core::features::FEATURES` | 实验性功能列表 |
| `codex_protocol::account::PlanType` | 用户计划类型 |
| `lazy_static` | 静态提示列表初始化 |
| `rand` | 随机提示选择 |
| `chrono` | 日期解析和比较 |
| `regex_lite` | 版本正则匹配 |
| `serde` | TOML 反序列化 |
| `toml` | TOML 解析 |
| `reqwest` | HTTP 公告获取 |

### 调用方

| 文件 | 用途 |
|------|------|
| `app.rs` | 启动时获取并显示提示 |
| `history_cell.rs` | 历史单元格提示 |
| `bottom_pane/command_popup.rs` | 命令弹窗提示 |

---

## 依赖与外部交互

### 提示池构建流程

```rust
lazy_static! {
    static ref TOOLTIPS: Vec<&'static str> = RAW_TOOLTIPS
        .lines()
        .map(str::trim)
        .filter(|line| {
            // 过滤空行和注释
            if line.is_empty() || line.starts_with('#') { return false; }
            // 非 macOS/Windows 过滤 "codex app" 提示
            if !IS_MACOS && !IS_WINDOWS && line.contains("codex app") { return false; }
            true
        })
        .collect();
    
    static ref ALL_TOOLTIPS: Vec<&'static str> = {
        let mut tips = Vec::new();
        tips.extend(TOOLTIPS.iter().copied());
        tips.extend(experimental_tooltips());  // 添加实验性提示
        tips
    };
}
```

### 公告系统架构

```
tooltips.rs::announcement
    ├── ANNOUNCEMENT_TIP: OnceLock<Option<String>> - 缓存
    ├── prewarm() - 后台预热
    ├── fetch_announcement_tip() - 获取缓存的公告
    ├── blocking_init_announcement_tip() - HTTP 获取
    └── parse_announcement_tip_toml() - 解析和过滤
```

### 平台检测

```rust
const IS_MACOS: bool = cfg!(target_os = "macos");
const IS_WINDOWS: bool = cfg!(target_os = "windows");
```

用于：
- 选择平台特定的提示文本
- 过滤不相关的提示

---

## 风险、边界与改进建议

### 已知风险

1. **网络依赖**：公告获取依赖网络连接，失败时无感知回退
2. **远程代码执行**：TOML 解析可能存在的安全问题（使用 `toml` crate 的限制功能）
3. **隐私泄露**：HTTP 请求可能泄露用户 IP 和 Codex 版本

### 边界情况

1. **空提示池**：如果 `tooltips.txt` 为空，随机提示返回 `None`
2. **公告超时**：2 秒超时可能导致公告未加载完成
3. **日期解析失败**：无效日期格式的公告被跳过
4. **正则表达式无效**：无效的正则表达式导致公告被跳过

### 测试覆盖

| 测试 | 描述 |
|------|------|
| `random_tooltip_returns_some_tip_when_available` | 随机提示返回 |
| `random_tooltip_is_reproducible_with_seed` | 随机种子可复现 |
| `paid_tooltip_pool_rotates_between_promos` | 付费提示轮换 |
| `paid_tooltip_pool_skips_fast_when_fast_mode_is_enabled` | Fast 模式跳过 |
| `announcement_tip_toml_picks_last_matching` | 公告匹配 |
| `announcement_tip_toml_picks_no_match` | 无匹配公告 |
| `announcement_tip_toml_bad_deserialization` | 解析失败处理 |
| `announcement_tip_toml_parse_comments` | 注释处理 |

### 改进建议

1. **离线支持**：
   - 缓存公告到本地文件
   - 网络失败时使用缓存

2. **隐私保护**：
   - 添加选项禁用远程公告
   - 使用匿名化请求

3. **本地化**：
   - 支持多语言提示
   - 根据系统语言选择提示

4. **个性化**：
   - 根据用户使用模式推荐提示
   - 允许用户标记已读提示

5. **可访问性**：
   - 添加选项禁用启动提示
   - 支持屏幕阅读器朗读提示

6. **性能优化**：
   - 使用异步 HTTP 客户端
   - 减少启动时的阻塞等待

### 代码特点

- **分层提示策略**：根据用户类型显示不同内容
- **平台感知**：针对不同操作系统调整内容
- **容错设计**：多处使用 `ok()` 和 `unwrap_or` 处理失败
- **测试友好**：使用种子化的 RNG 确保测试可复现

### 相关文件

- `tooltips.txt`：静态提示列表
- `announcement_tip.toml`：远程公告配置
- `app.rs`：提示显示逻辑
- `version.rs`：版本信息
