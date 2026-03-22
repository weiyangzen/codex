# announcement_tip.toml 文件研究文档

## 场景与职责

announcement_tip.toml 是 Codex TUI（终端用户界面）的公告提示配置文件，承担以下核心职责：
- **产品公告**: 向用户展示重要更新、新功能或提示信息
- **版本引导**: 鼓励用户升级到推荐版本
- **临时通知**: 在特定时间段内显示时效性信息
- **定向推送**: 根据应用类型（CLI、VSCE 等）定向显示

## 功能点目的

### 1. 公告系统架构
```
announcement_tip.toml
├── 公告条目 1 (欢迎消息)
├── 公告条目 2 (测试公告)
└── 公告条目 3 (版本升级提示)
```

### 2. 匹配逻辑
```rust
// 伪代码：公告选择逻辑
for announcement in announcements.iter().rev() {
    if announcement.matches(version, target_app, current_date) {
        selected = announcement;
    }
}
// 显示最后一个匹配的条目
```

### 3. 公告属性
| 属性 | 说明 | 示例 |
|------|------|------|
| `content` | 公告内容（支持 Markdown） | `"Welcome to Codex!"` |
| `from_date` | 开始日期（包含） | `"2024-10-01"` |
| `to_date` | 结束日期（不包含） | `"2024-10-15"` |
| `target_app` | 目标应用 | `"cli"`, `"vsce"` |
| `version_regex` | 版本匹配正则 | `"^0\\.0\\.0$"` |

## 具体技术实现

### 文件结构
```toml
# 示例公告配置
[[announcements]]
content = "Welcome to Codex! Check out the new onboarding flow."
from_date = "2024-10-01"
to_date = "2024-10-15"
target_app = "cli"
```

### 数据结构
```rust
// 对应的 Rust 结构（推测）
#[derive(Debug, Deserialize)]
struct Announcement {
    content: String,
    #[serde(default)]
    from_date: Option<String>,
    #[serde(default)]
    to_date: Option<String>,
    #[serde(default)]
    target_app: Option<String>,
    #[serde(default)]
    version_regex: Option<String>,
}

#[derive(Debug, Deserialize)]
struct AnnouncementConfig {
    announcements: Vec<Announcement>,
}
```

### 当前配置分析

#### 公告 1: 欢迎消息
```toml
[[announcements]]
content = "Welcome to Codex! Check out the new onboarding flow."
from_date = "2024-10-01"
to_date = "2024-10-15"
target_app = "cli"
```
- **用途**: 新用户引导
- **时效**: 2024年10月1日-15日（已过期）
- **目标**: CLI 用户

#### 公告 2: 测试公告
```toml
[[announcements]]
content = "This is a test announcement"
version_regex = "^0\\.0\\.0$"
to_date = "2026-05-10"
```
- **用途**: 本地开发测试
- **目标**: 版本 0.0.0（本地构建）
- **时效**: 到 2026年5月10日

#### 公告 3: 版本升级提示
```toml
[[announcements]]
content = "**BREAKING NEWS**: `gpt-5.3-codex` is out! Upgrade to `0.98.0`..."
from_date = "2026-02-01"
to_date = "2026-02-16"
version_regex = "^0\\.(?:[0-9]|[1-8][0-9]|9[0-7])\\."
```
- **用途**: 鼓励升级到 0.98.0+
- **目标**: 版本 0.0.0 - 0.97.x 的用户
- **时效**: 2026年2月1日-16日
- **特性**: 使用 Markdown 粗体

## 关键代码路径与文件引用

### 相关文件
| 文件 | 说明 |
|------|------|
| `/home/sansha/Github/codex/announcement_tip.toml` | 本文件 |
| `codex-rs/tui/src/` | TUI 实现（可能包含公告渲染） |
| `codex-rs/core/src/` | 核心逻辑（可能包含公告加载） |

### 代码引用（推测）
```rust
// 可能的公告加载代码
codex-rs/core/src/
├── config.rs          # 配置加载
└── announcement.rs    # 公告模块

codex-rs/tui/src/
├── app.rs             # 应用主循环
├── ui.rs              # UI 渲染
└── components/
    └── announcement.rs # 公告组件
```

### 配置文件引用
```toml
# Cargo.toml 可能的依赖
toml = { workspace = true }  # 用于解析 TOML
regex = { workspace = true } # 用于版本匹配
chrono = { workspace = true } # 用于日期处理
```

## 依赖与外部交互

### 运行时依赖
```
announcement_tip.toml
├── TOML 解析器 ──────────────┐
│   └── toml crate            │
├── 正则表达式引擎 ────────────┤
│   └── regex crate           ├── 公告系统
├── 日期时间处理 ──────────────┤
│   └── chrono crate          │
└── 版本信息 ──────────────────┘
    └── CARGO_PKG_VERSION
```

### 构建时嵌入
公告文件可能在构建时嵌入或运行时从以下位置加载：
- 嵌入二进制（`include_str!`）
- 配置文件目录（`~/.codex/`）
- 远程获取（HTTP 请求）

## 风险、边界与改进建议

### 风险

#### 1. 时区问题
```toml
# 当前配置使用 UTC 日期
from_date = "2024-10-01"  # UTC 00:00:00?
```
- **风险**: 用户本地时区与 UTC 不一致可能导致提前/延迟显示
- **建议**: 明确时区或支持时区配置

#### 2. 正则表达式复杂性
```toml
version_regex = "^0\\.(?:[0-9]|[1-8][0-9]|9[0-7])\\."
```
- **风险**: 复杂的正则难以维护，容易出错
- **建议**: 添加注释说明或改用语义化版本范围

#### 3. 过期公告堆积
- **风险**: 历史公告长期保留在配置文件中
- **建议**: 定期清理过期公告

### 边界

#### 功能边界
- 仅支持文本内容（无富媒体）
- 不支持条件逻辑（如用户行为触发）
- 不支持 A/B 测试
- 不支持用户反馈收集

#### 技术边界
- 日期格式固定为 `YYYY-MM-DD`
- 正则语法为 Rust regex 方言
- 无国际化 (i18n) 支持

### 改进建议

#### 1. 添加版本范围支持
```toml
# 建议的新格式
[[announcements]]
content = "Upgrade to 0.98.0!"
[version]
min = "0.0.0"
max = "0.97.999"
exclude = ["0.95.0"]  # 可选：排除特定版本
```

#### 2. 添加优先级和频率控制
```toml
[[announcements]]
content = "Important update!"
priority = "high"        # low, normal, high, critical
max_shows = 3            # 最多显示次数
show_interval = "24h"    # 显示间隔
```

#### 3. 添加国际化支持
```toml
[[announcements]]
[content]
en = "Welcome to Codex!"
zh = "欢迎使用 Codex！"
ja = "Codex へようこそ！"
```

#### 4. 添加操作按钮
```toml
[[announcements]]
content = "New version available!"
[actions]
primary = { text = "Update Now", action = "update" }
secondary = { text = "Learn More", url = "https://..." }
dismiss = { text = "Remind Me Later", delay = "7d" }
```

#### 5. 添加条件触发
```toml
[[announcements]]
content = "Try the new file search feature!"
[conditions]
min_sessions = 5          # 至少使用 5 次
features_used = ["exec"]  # 使用过 exec 命令
platform = ["macos", "linux"]  # 特定平台
```

#### 6. 配置验证工具
```bash
#!/bin/bash
# 验证公告配置

# 检查日期格式
# 检查正则语法
# 检查重叠时间段
# 检查过期公告
```

#### 7. 遥测和效果追踪
```toml
[[announcements]]
content = "Check out the new feature!"
id = "new-feature-2026-02"  # 唯一标识
[metrics]
impression = true          # 追踪展示
click = true               # 追踪点击
dismiss = true             # 追踪关闭
```

### 配置管理建议

#### 版本控制
```
announcement_tip.toml
├── main 分支（当前生效）
├── staging 分支（测试）
└── archive/（历史配置）
    ├── 2024-Q4.toml
    └── 2025-Q1.toml
```

#### CI/CD 集成
```yaml
# 建议的 CI 检查
announcement-check:
  - 验证 TOML 语法
  - 验证日期逻辑（from_date < to_date）
  - 验证正则表达式语法
  - 检查即将过期的公告
  - 检查重叠的时间段
```
