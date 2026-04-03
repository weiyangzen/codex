# tooltips.txt 研究文档

## 场景与职责

`codex-rs/tui/tooltips.txt` 是 Codex TUI 的提示语文本资源文件，包含启动时随机显示的提示语（tooltips）。这些提示语帮助用户发现 Codex CLI 的功能特性，提升用户体验和产品粘性。

该文件是静态资源，通过 `include_str!` 宏嵌入到二进制中，在 `tooltips.rs` 模块中被解析和使用。

## 功能点目的

### 1. 用户教育
- 向用户展示 Codex CLI 的各种功能
- 推广新功能和最佳实践
- 提供社区和支持资源链接

### 2. 提示语分类
当前 tooltips.txt 包含以下类别的提示：

| 类别 | 示例 |
|------|------|
| 命令使用 | `/compact`, `/new`, `/feedback`, `/model` |
| 功能介绍 | `/permissions`, `/review`, `/skills`, `/status` |
| 社区资源 | Discord, 社区论坛 |
| 快捷操作 | `!` 执行 shell 命令, `/` 打开命令弹出框 |
| 实用技巧 | 图片粘贴、会话恢复、Tab 队列 |

### 3. 提示语展示策略
- **随机选择**: 从提示语池中随机选择
- **付费用户优先**: 付费用户优先看到产品推广提示
- **动态公告**: 支持从远程获取时效性公告

## 具体技术实现

### 提示语解析与过滤

**文件**: `src/tooltips.rs`
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
            // 非 Mac/Windows 平台过滤掉 "codex app" 相关提示
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

    // 1. 优先检查远程公告
    if let Some(announcement) = announcement::fetch_announcement_tip() {
        return Some(announcement);
    }

    // 2. 80% 概率显示付费用户定向提示
    if rng.random_ratio(8, 10) {
        match plan {
            Some(PlanType::Plus | PlanType::Business | PlanType::Team | ...) => {
                return Some(pick_paid_tooltip(&mut rng, fast_mode_enabled).to_string());
            }
            Some(PlanType::Go | PlanType::Free) => {
                return Some(FREE_GO_TOOLTIP.to_string());
            }
            _ => { /* 继续随机提示 */ }
        }
    }

    // 3. 从 tooltips.txt 中随机选择
    pick_tooltip(&mut rng).map(str::to_string)
}
```

### 付费用户提示策略

```rust
fn pick_paid_tooltip<R: Rng + ?Sized>(rng: &mut R, fast_mode_enabled: bool) -> &'static str {
    if fast_mode_enabled || rng.random_bool(0.5) {
        paid_app_tooltip()  // 推广 Codex App
    } else {
        FAST_TOOLTIP         // 推广 Fast 模式
    }
}

fn paid_app_tooltip() -> &'static str {
    if IS_MACOS {
        PAID_TOOLTIP
    } else if IS_WINDOWS {
        PAID_TOOLTIP_WINDOWS
    } else {
        PAID_TOOLTIP_NON_MAC
    }
}
```

### 远程公告系统

```rust
const ANNOUNCEMENT_TIP_URL: &str = 
    "https://raw.githubusercontent.com/openai/codex/main/announcement_tip.toml";

pub(crate) mod announcement {
    static ANNOUNCEMENT_TIP: OnceLock<Option<String>> = OnceLock::new();

    pub(crate) fn prewarm() {
        // 在后台线程预加载公告
        let _ = thread::spawn(|| ANNOUNCEMENT_TIP.get_or_init(init_announcement_tip_in_thread));
    }

    fn blocking_init_announcement_tip() -> Option<String> {
        let client = reqwest::blocking::Client::builder()
            .no_proxy()  // 避免 macOS 系统配置崩溃
            .build()
            .ok()?;
        let response = client
            .get(ANNOUNCEMENT_TIP_URL)
            .timeout(Duration::from_millis(2000))
            .send()
            .ok()?;
        response.error_for_status().ok()?.text().ok()
    }
}
```

### 公告 TOML 格式

```toml
[[announcements]]
content = "提示语内容"
from_date = "2024-10-01"    # 可选：开始日期（含）
to_date = "2024-10-15"      # 可选：结束日期（不含）
version_regex = "^0\\.0\\.0$" # 可选：版本匹配
```

## 关键代码路径与文件引用

### 核心实现文件
| 文件 | 行数 | 职责 |
|------|------|------|
| `tooltips.txt` | ~24 | 提示语文本资源 |
| `src/tooltips.rs` | ~411 | 提示语解析、选择、公告系统 |
| `src/lib.rs` | ~1000+ | 调用 `tooltips::announcement::prewarm()` |

### 提示语使用流程
```
启动流程 (lib.rs::run_ratatui_app)
    ↓
tooltips::announcement::prewarm()  // 预加载远程公告
    ↓
ChatWidget 初始化
    ↓
get_tooltip(plan, fast_mode_enabled)  // 获取提示语
    ↓
显示在 UI 中（底部状态栏或欢迎界面）
```

### 测试覆盖
**文件**: `src/tooltips.rs` (tests 模块)
```rust
#[test]
fn random_tooltip_returns_some_tip_when_available() {
    let mut rng = StdRng::seed_from_u64(42);
    assert!(pick_tooltip(&mut rng).is_some());
}

#[test]
fn paid_tooltip_pool_rotates_between_promos() {
    // 验证付费用户提示池轮换
}

#[test]
fn announcement_tip_toml_picks_last_matching() {
    // 验证公告 TOML 解析
}
```

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `rand` | 随机数生成 |
| `lazy_static` | 静态初始化 |
| `reqwest` | HTTP 请求（公告下载） |
| `regex-lite` | 版本正则匹配 |
| `chrono` | 日期解析和比较 |

### 内部依赖
| 模块 | 交互 |
|------|------|
| `codex_protocol::account::PlanType` | 用户套餐类型 |
| `codex_core::features::FEATURES` | 实验性功能提示 |

### 网络交互
| 端点 | 用途 | 超时 |
|------|------|------|
| `raw.githubusercontent.com/openai/codex/main/announcement_tip.toml` | 获取公告 | 2000ms |

### 特性集成
```rust
fn experimental_tooltips() -> Vec<&'static str> {
    FEATURES
        .iter()
        .filter_map(|spec| spec.stage.experimental_announcement())
        .collect()
}
```

## 风险、边界与改进建议

### 风险点

#### 1. 网络依赖
- 远程公告下载可能失败
- 超时设置（2秒）可能影响启动体验
- 无网络环境下功能降级

#### 2. 平台差异
```rust
// 非 Mac/Windows 过滤 "codex app" 提示
if !IS_MACOS && !IS_WINDOWS && line.contains("codex app") {
    return false;
}
```
- Linux 用户看不到 Codex App 推广
- 可能导致功能发现不完整

#### 3. 提示语过时
- tooltips.txt 是静态资源
- 需要随版本更新而更新
- 可能包含已废弃的功能说明

### 边界条件

#### 1. 空提示语池
```rust
fn pick_tooltip<R: Rng + ?Sized>(rng: &mut R) -> Option<&'static str> {
    if ALL_TOOLTIPS.is_empty() {
        None
    } else {
        ALL_TOOLTIPS.get(rng.random_range(0..ALL_TOOLTIPS.len())).copied()
    }
}
```
- 如果 tooltips.txt 为空或全部被过滤，返回 `None`

#### 2. 公告解析失败
```rust
pub(crate) fn parse_announcement_tip_toml(text: &str) -> Option<String> {
    toml::from_str::<AnnouncementTipDocument>(text)
        .map(|doc| doc.announcements)
        .or_else(|_| toml::from_str::<Vec<AnnouncementTipRaw>>(text))
        .ok()?
    // ...
}
```
- TOML 解析失败时静默返回 `None`

#### 3. 并发安全
```rust
static ANNOUNCEMENT_TIP: OnceLock<Option<String>> = OnceLock::new();
```
- 使用 `OnceLock` 确保线程安全
- 但公告内容在进程生命周期内固定

### 改进建议

#### 1. 本地化支持
```rust
// 根据用户语言选择提示语文件
const RAW_TOOLTIPS: &str = match locale() {
    "zh-CN" => include_str!("../tooltips_zh.txt"),
    _ => include_str!("../tooltips.txt"),
};
```

#### 2. 提示语分类标签
```text
# tooltips.txt 格式改进
[command] Use /compact when the conversation gets long
[feature] Use /skills to list available skills
[community] Join the OpenAI community Discord
[tips] Paste an image with Ctrl+V to attach it
```

#### 3. 用户偏好学习
```rust
pub struct TooltipPreferences {
    pub shown_tooltips: HashSet<String>,
    pub preferred_categories: Vec<Category>,
}

// 避免重复显示相同提示
fn pick_tooltip_with_preference(rng: &mut R, prefs: &TooltipPreferences) -> Option<&str> {
    // 优先选择未显示过的提示
}
```

#### 4. 离线公告缓存
```rust
pub(crate) fn prewarm() {
    // 1. 尝试从缓存加载
    if let Some(cached) = load_cached_announcement() {
        let _ = ANNOUNCEMENT_TIP.set(cached);
        return;
    }
    // 2. 后台下载更新
    thread::spawn(|| {
        if let Some(new) = download_announcement() {
            cache_announcement(&new);
            let _ = ANNOUNCEMENT_TIP.set(Some(new));
        }
    });
}
```

#### 5. A/B 测试支持
```rust
pub struct TooltipExperiment {
    pub id: String,
    pub variants: Vec<&'static str>,
    pub weights: Vec<f64>,
}

fn pick_experimental_tooltip(experiment: &TooltipExperiment) -> &'static str {
    // 根据配置权重选择变体
}
```

#### 6. 提示语效果追踪
```rust
// 记录提示语展示和点击
pub fn record_tooltip_shown(tooltip_id: &str) {
    telemetry::track("tooltip_shown", json!({ "id": tooltip_id }));
}

pub fn record_tooltip_clicked(tooltip_id: &str) {
    telemetry::track("tooltip_clicked", json!({ "id": tooltip_id }));
}
```

#### 7. 动态提示语更新
```rust
// 支持从配置加载额外提示语
pub fn load_custom_tooltips(path: &Path) -> Vec<&'static str> {
    // 允许项目自定义提示语
}
```
