# Tooltips 研究文档

## 场景与职责

`tooltips.rs` 实现了 Codex TUI 的启动提示系统。在用户启动 Codex 时显示有用的提示信息，包括：

1. **随机提示池**：从预定义提示池中随机选择
2. **付费用户推广**：根据用户套餐类型显示定向推广
3. **远程公告**：从 GitHub 获取动态公告
4. **平台特定内容**：根据操作系统显示不同内容

该模块位于 `codex-rs/tui_app_server/src/tooltips.rs`，是用户引导和推广的重要渠道。

## 功能点目的

### 1. 启动提示显示

`get_tooltip()` 函数是主要入口，返回启动时显示的提示：
- 80% 概率显示套餐相关推广
- 20% 概率显示随机提示
- 优先显示远程公告（如果可用）

### 2. 付费用户推广

根据 `PlanType` 显示不同的推广内容：
- **Plus/Business/Team/Enterprise/Pro**：显示 Codex App 推广或 Fast 模式提示
- **Go/Free**：显示免费使用提示
- **其他/未知**：显示通用提示

### 3. 远程公告系统

从远程 URL 获取动态公告：
- URL：`https://raw.githubusercontent.com/openai/codex/main/announcement_tip.toml`
- 支持日期范围过滤（`from_date`, `to_date`）
- 支持版本正则匹配（`version_regex`）
- 支持目标应用过滤（`target_app`）
- 2秒超时，避免阻塞启动

### 4. 平台特定内容

- **macOS**：显示 Codex App 推广
- **Windows**：显示 Windows 版 Codex App 推广
- **Linux/其他**：显示简化推广或无 App 引用

## 具体技术实现

### 提示选择逻辑

```rust
pub(crate) fn get_tooltip(plan: Option<PlanType>, fast_mode_enabled: bool) -> Option<String> {
    let mut rng = rand::rng();

    // 1. 优先显示远程公告
    if let Some(announcement) = announcement::fetch_announcement_tip() {
        return Some(announcement);
    }

    // 2. 80% 概率显示套餐相关推广
    if rng.random_ratio(8, 10) {
        match plan {
            Some(PlanType::Plus) | Some(PlanType::Business) | ... => {
                return Some(pick_paid_tooltip(&mut rng, fast_mode_enabled).to_string());
            }
            Some(PlanType::Go) | Some(PlanType::Free) => {
                return Some(FREE_GO_TOOLTIP.to_string());
            }
            _ => {
                let tooltip = if IS_MACOS { OTHER_TOOLTIP } else { OTHER_TOOLTIP_NON_MAC };
                return Some(tooltip.to_string());
            }
        }
    }

    // 3. 20% 概率显示随机提示
    pick_tooltip(&mut rng).map(str::to_string)
}
```

### 付费用户提示选择

```rust
fn pick_paid_tooltip<R: Rng + ?Sized>(rng: &mut R, fast_mode_enabled: bool) -> &'static str {
    if fast_mode_enabled || rng.random_bool(0.5) {
        paid_app_tooltip()  // 50% 概率（或已启用 Fast 模式）
    } else {
        FAST_TOOLTIP        // 50% 概率
    }
}

fn paid_app_tooltip() -> &'static str {
    if IS_MACOS {
        PAID_TOOLTIP           // macOS 完整推广
    } else if IS_WINDOWS {
        PAID_TOOLTIP_WINDOWS   // Windows 推广
    } else {
        PAID_TOOLTIP_NON_MAC   // 其他平台简化推广
    }
}
```

### 远程公告系统

```rust
pub(crate) mod announcement {
    static ANNOUNCEMENT_TIP: OnceLock<Option<String>> = OnceLock::new();

    /// 预热公告缓存
    pub(crate) fn prewarm() {
        let _ = thread::spawn(|| ANNOUNCEMENT_TIP.get_or_init(init_announcement_tip_in_thread));
    }

    /// 获取公告（如果预热完成）
    pub(crate) fn fetch_announcement_tip() -> Option<String> {
        ANNOUNCEMENT_TIP
            .get()
            .cloned()
            .flatten()
            .and_then(|raw| parse_announcement_tip_toml(&raw))
    }

    fn blocking_init_announcement_tip() -> Option<String> {
        // 禁用代理避免 macOS 系统配置 panic
        let client = reqwest::blocking::Client::builder()
            .no_proxy()
            .build()
            .ok()?;
        let response = client
            .get(ANNOUNCEMENT_TIP_URL)
            .timeout(Duration::from_millis(2000))
            .send()
            .ok()?;
        response.error_for_status().ok()?.text().ok()
    }

    pub(crate) fn parse_announcement_tip_toml(text: &str) -> Option<String> {
        let announcements = toml::from_str::<AnnouncementTipDocument>(text)
            .map(|doc| doc.announcements)
            .or_else(|_| toml::from_str::<Vec<AnnouncementTipRaw>>(text))
            .ok()?;

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
}
```

### 提示池定义

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
            // 非 macOS/Windows 过滤掉包含 "codex app" 的提示
            if !IS_MACOS && !IS_WINDOWS && line.contains("codex app") {
                return false;
            }
            true
        })
        .collect();
    
    static ref ALL_TOOLTIPS: Vec<&'static str> = {
        let mut tips = Vec::new();
        tips.extend(TOOLTIPS.iter().copied());
        tips.extend(experimental_tooltips());
        tips
    };
}
```

### 硬编码提示常量

```rust
const PAID_TOOLTIP: &str = "*New* Try the **Codex App** with 2x rate limits until *April 2nd*. Run 'codex app' or visit https://chatgpt.com/codex?app-landing-page=true";

const PAID_TOOLTIP_WINDOWS: &str = "*New* Try the **Codex App**, now available on **Windows**, with 2x rate limits until *April 2nd*. Run 'codex app' or visit https://chatgpt.com/codex?app-landing-page=true";

const PAID_TOOLTIP_NON_MAC: &str = "*New* 2x rate limits until *April 2nd*.";

const FAST_TOOLTIP: &str = "*New* Use **/fast** to enable our fastest inference at 2X plan usage.";

const FREE_GO_TOOLTIP: &str = "*New* For a limited time, Codex is included in your plan for free – let's build together.";
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/tooltips.rs` (411 行)

### 依赖文件
- `tooltips.txt` - 随机提示池（编译时包含）
- `announcement_tip.toml` - 远程公告配置

### 依赖模块
| 模块 | 用途 |
|------|------|
| `codex_core::features::FEATURES` | 实验性功能提示 |
| `codex_protocol::account::PlanType` | 用户套餐类型 |
| `version::CODEX_CLI_VERSION` | 版本号匹配 |

### 调用方
- `app.rs` 或主入口 - 启动时显示提示
- `announcement::prewarm()` - 预热公告缓存

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `rand` | 随机提示选择 |
| `lazy_static` | 静态提示池初始化 |
| `reqwest` | 远程公告获取 |
| `chrono` | 日期解析和比较 |
| `regex_lite` | 版本正则匹配 |
| `toml` | 公告配置解析 |
| `serde` | 配置反序列化 |

### 内部依赖
- `codex_core::features` - 实验性功能提示
- `version::CODEX_CLI_VERSION` - 版本匹配

### 网络交互
- `GET https://raw.githubusercontent.com/openai/codex/main/announcement_tip.toml`
- 2秒超时
- 禁用代理（避免 macOS 系统配置问题）

## 风险、边界与改进建议

### 潜在风险

1. **网络依赖**：启动时依赖 GitHub 可用性，虽然超时仅 2 秒，但网络慢时仍可能影响体验。

2. **日期硬编码**：`PAID_TOOLTIP` 中的 "April 2nd" 是硬编码的，需要定期更新。

3. **随机种子**：使用 `rand::rng()` 的默认种子，测试时可能难以复现特定提示。

4. **平台检测**：使用编译时 `cfg!` 而非运行时检测，无法处理容器或远程开发场景。

### 边界情况

1. **提示池为空**：如果 `tooltips.txt` 为空或所有提示被过滤，`pick_tooltip` 返回 `None`。

2. **公告解析失败**：TOML 解析失败时静默返回 `None`，不会显示错误。

3. **版本正则无效**：无效的正则表达式会导致该公告被跳过。

4. **日期格式错误**：非 `YYYY-MM-DD` 格式的日期会导致该公告被跳过。

### 测试覆盖

模块包含全面的单元测试：
- `random_tooltip_returns_some_tip_when_available` - 随机提示存在性
- `random_tooltip_is_reproducible_with_seed` - 可复现性
- `paid_tooltip_pool_rotates_between_promos` - 付费提示轮换
- `paid_tooltip_pool_skips_fast_when_fast_mode_is_enabled` - Fast 模式过滤
- `announcement_tip_toml_*` - 公告解析各种场景

### 改进建议

1. **配置化提示池**：允许用户通过配置禁用或自定义提示。

2. **提示频率控制**：记录上次显示时间，避免每次启动都显示提示。

3. **A/B 测试支持**：添加提示 ID 和展示追踪，支持效果分析。

4. **本地化支持**：当前提示都是英文，考虑多语言支持。

5. **动态日期**：使用相对日期（如 "until next week"）而非绝对日期。

6. **离线模式**：缓存远程公告，离线时显示缓存版本。

7. **提示历史**：避免在短时间内重复显示相同的随机提示。

8. **用户反馈**：添加提示反馈机制（如 "不再显示此提示"）。

### 安全和隐私

1. **代理禁用**：`no_proxy()` 设置是为了避免 macOS 系统配置 panic，但可能绕过企业代理。

2. **版本信息泄露**：`version_regex` 匹配会暴露客户端版本号。

3. **用户追踪**：远程请求可能暴露用户 IP 和使用时间模式。
