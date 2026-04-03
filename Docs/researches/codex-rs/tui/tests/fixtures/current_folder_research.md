# codex-rs/tui/tests/fixtures 目录研究文档

## 目录概述

`codex-rs/tui/tests/fixtures` 目录包含 TUI（Terminal User Interface）测试所需的静态数据文件。该目录目前包含一个主要的 fixture 文件：`oss-story.jsonl`，用于存储 TUI 会话的事件日志，供测试和开发使用。

---

## 1. 场景与职责

### 1.1 核心职责

该目录及其 fixture 文件承担以下核心职责：

1. **会话事件记录**：捕获和存储完整的 TUI 用户会话事件流，包括用户输入、系统响应、UI 重绘请求等
2. **测试数据提供**：为自动化测试提供真实、可复现的会话数据，用于验证 TUI 行为一致性
3. **回归测试基础**：作为快照测试（snapshot testing）的基准数据，检测 UI 渲染或事件处理的意外变更
4. **开发调试辅助**：开发者可通过分析 fixture 文件理解 TUI 内部事件流转机制

### 1.2 使用场景

| 场景 | 描述 |
|------|------|
| **VT100 测试** | 配合 `vt100-tests` feature 使用，验证终端模拟器行为 |
| **历史记录插入测试** | 测试 `insert_history` 模块的文本换行、颜色渲染等功能 |
| **实时流测试** | 验证 `live_wrap` 模块的行构建和溢出处理逻辑 |
| **集成测试** | 在 `test_backend.rs` 中作为事件源重放完整会话 |

---

## 2. 功能点目的

### 2.1 oss-story.jsonl 文件分析

**文件统计**：
- 总行数：约 8,041 行
- 格式：JSON Lines (JSONL)
- 时间跨度：2025-08-10 03:12:26 至 03:23:26（约 11 分钟会话）

**事件类型分布**：

| 事件类型 (kind) | 说明 | 典型频率 |
|----------------|------|---------|
| `app_event` | 应用级事件（RequestRedraw/Redraw/StartCommitAnimation 等） | 高频 |
| `codex_event` | Codex 核心事件（agent_message_delta, task_started 等） | 中频 |
| `key_event` | 用户键盘输入事件 | 低频 |
| `insert_history` | 历史记录插入通知 | 低频 |
| `log_line` | 日志输出行 | 极低频 |
| `session_start` | 会话开始元数据（meta dir） | 单次 |

### 2.2 数据结构详解

每个 JSON 行包含以下字段：

```json
{
  "ts": "2025-08-10T03:12:26.500Z",    // ISO 8601 时间戳（微秒精度）
  "dir": "to_tui",                       // 事件方向：to_tui / meta
  "kind": "app_event",                   // 事件类型
  "variant": "RequestRedraw",            // 事件变体（可选）
  "event": "KeyEvent { ... }",           // 详细事件数据（可选）
  "payload": { ... },                    // Codex 事件负载（可选）
  "lines": 9                             // 插入行数（insert_history 专用）
}
```

### 2.3 典型事件序列示例

**用户输入处理流程**：
```
1. key_event (Char 'h' Press) → 
2. app_event RequestRedraw → 
3. app_event Redraw → 
4. key_event (Char 'h' Release)
```

**Agent 响应流程**：
```
1. codex_event (task_started) → 
2. codex_event (agent_reasoning_raw_content_delta "The") → 
3. insert_history lines:1 → 
4. app_event RequestRedraw → 
5. app_event Redraw → 
6. ...（多个 delta 事件）→ 
7. codex_event (agent_message "Hello! How can I help you today?") → 
8. codex_event (task_complete)
```

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 Fixture 文件生成流程

1. **会话录制**：TUI 运行时通过 `session_log.rs` 模块记录所有事件到内存
2. **持久化**：会话结束时或按需将事件流写入 `.jsonl` 文件
3. **格式化**：每行一个 JSON 对象，使用紧凑格式（无多余空格）

#### 3.1.2 Fixture 文件在测试中的使用流程

以 `vt100_history.rs` 测试为例：

```rust
// 1. 创建 VT100Backend 模拟终端
let backend = VT100Backend::new(20, 6);
let mut term = Terminal::with_options(backend)?;

// 2. 设置视口区域
term.set_viewport_area(Rect::new(0, 5, 20, 1));

// 3. 构建测试数据（模拟 fixture 中的行数据）
let lines = vec!["first".into(), "second".into()];

// 4. 调用被测函数
insert_history_lines(&mut term, lines)?;

// 5. 验证 VT100 屏幕内容
let rows = term.backend().vt100().screen().contents();
assert!(rows.contains("first"));
```

### 3.2 核心数据结构

#### 3.2.1 事件类型定义

```rust
// 来自 app_event.rs 的核心事件枚举
pub(crate) enum AppEvent {
    CodexEvent(Event),                    // 核心 Codex 事件
    InsertHistoryCell(Box<dyn HistoryCell>), // 插入历史记录
    StartCommitAnimation,                 // 开始提交动画
    StopCommitAnimation,                  // 停止提交动画
    CommitTick,                           // 提交动画帧
    // ... 其他事件
}
```

#### 3.2.2 VT100 后端结构

```rust
// test_backend.rs
pub struct VT100Backend {
    crossterm_backend: CrosstermBackend<vt100::Parser>,
}

impl VT100Backend {
    pub fn new(width: u16, height: u16) -> Self {
        crossterm::style::force_color_output(true);
        Self {
            crossterm_backend: CrosstermBackend::new(
                vt100::Parser::new(height, width, 0)
            ),
        }
    }
    
    pub fn vt100(&self) -> &vt100::Parser {
        self.crossterm_backend.writer()
    }
}
```

### 3.3 关键协议与命令

#### 3.3.1 终端控制序列

`insert_history.rs` 中使用的主要 ANSI 序列：

| 序列 | 命令 | 用途 |
|------|------|------|
| `ESC [ top;bottom r` | DECSTBM | 设置滚动区域 |
| `ESC [ r` | DECSTBM (reset) | 重置滚动区域 |
| `ESC M` | RI (Reverse Index) | 反向索引（向上滚动） |
| `ESC [ 2 K` | EL2 | 清除整行 |
| `ESC [ H` | CUP | 光标归位 |

#### 3.3.2 文本换行策略

```rust
// wrapping.rs / insert_history.rs
pub fn adaptive_wrap_line(line: &Line, options: RtOptions) -> Vec<Line> {
    // 1. 检测 URL-only 行：保持完整，让终端自动换行
    // 2. 检测混合行（URL + 文本）：自适应换行，保护 URL 不被分割
    // 3. 纯文本行：标准词边界换行
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件依赖图

```
codex-rs/tui/tests/fixtures/oss-story.jsonl
    │
    ▼
codex-rs/tui/tests/
    ├── all.rs                    # 测试入口，聚合所有测试模块
    ├── test_backend.rs           # 重导出 VT100Backend
    └── suite/
        ├── mod.rs                # 测试模块聚合
        ├── vt100_history.rs      # 历史记录插入测试 ★
        ├── vt100_live_commit.rs  # 实时提交测试 ★
        ├── status_indicator.rs   # 状态指示器测试
        ├── model_availability_nux.rs  # 模型可用性测试
        └── no_panic_on_startup.rs     # 启动稳定性测试

    ▲
    │
codex-rs/tui/src/
    ├── test_backend.rs           # VT100Backend 实现 ★
    ├── insert_history.rs         # 历史记录插入逻辑 ★
    ├── live_wrap.rs              # 实时文本换行 ★
    ├── custom_terminal.rs        # 自定义终端实现 ★
    ├── app_event.rs              # 应用事件定义
    └── wrapping.rs               # 文本换行工具
```

### 4.2 关键代码路径详解

#### 路径 1：VT100 测试执行流程

```
vt100_history.rs::TestScenario::new()
    → VT100Backend::new(width, height)
        → CrosstermBackend::new(vt100::Parser::new(...))
    → Terminal::with_options(backend)
        → 初始化双缓冲、视口区域

vt100_history.rs::run_insert()
    → insert_history_lines(&mut term, lines)
        → 计算 wrap_width
        → adaptive_wrap_line() / 保持 URL 完整
        → 设置滚动区域 (SetScrollRegion)
        → 输出换行和样式序列
        → 恢复光标位置
    → term.backend().vt100().screen().contents()
        → 验证屏幕内容
```

#### 路径 2：实时行构建流程

```
vt100_live_commit.rs::live_001_commit_on_overflow()
    → RowBuilder::new(20)
        → 初始化 target_width、current_line、rows
    → rb.push_fragment("one\n") / ...
        → 按换行符分割输入
        → wrap_current_line() 处理长行
        → 存储 Row { text, explicit_break }
    → rb.drain_commit_ready(3)
        → 计算溢出行数
        → 移除并返回最旧的行
    → insert_history_lines(&mut term, lines)
        → 提交到终端历史记录
```

### 4.3 测试配置

**Cargo.toml 相关配置**：

```toml
[features]
vt100-tests = []  # 启用 VT100 模拟器测试

[dev-dependencies]
vt100 = { workspace = true }           # VT100 终端模拟器
codex-utils-cargo-bin = { workspace = true }  # 二进制文件定位
codex-utils-pty = { workspace = true }        # PTY 进程管理
```

**BUILD.bazel 配置**：

```starlark
codex_rust_crate(
    name = "tui",
    # ...
    test_data_extra = glob(["src/**/snapshots/**"]),
    integration_compile_data_extra = ["src/test_backend.rs"],
)
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 | 版本 |
|------|------|------|
| `vt100` | VT100 终端模拟器，解析 ANSI 序列 | workspace |
| `ratatui` | TUI 框架，提供 Backend/Buffer/Rect 等 | workspace |
| `crossterm` | 跨平台终端控制库 | workspace |
| `unicode-width` | Unicode 字符宽度计算 | workspace |

### 5.2 内部模块依赖

```
fixtures/
    └── oss-story.jsonl
        → 被 tests/suite/*.rs 引用（事件重放）
        → 被 src/test_backend.rs 消费（VT100 模拟）
        → 依赖 src/insert_history.rs（历史记录插入）
        → 依赖 src/live_wrap.rs（实时换行）
        → 依赖 src/custom_terminal.rs（终端管理）
        → 依赖 src/app_event.rs（事件定义）
```

### 5.3 与其他 crate 的交互

| Crate | 交互方式 | 用途 |
|-------|---------|------|
| `codex-utils-cargo-bin` | 函数调用 | 定位测试二进制文件和资源 |
| `codex-utils-pty` | 函数调用 | PTY 进程管理和输出捕获 |
| `codex-core` | 环境变量 | `CODEX_RS_SSE_FIXTURE` 指向 fixture |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 平台兼容性风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| Windows 不支持 | VT100/PTY 测试在 Windows 上无法运行 | 使用 `cfg!(windows)` 跳过测试 |
| 终端差异 | 不同终端对 ANSI 序列解释可能不同 | 使用 vt100 crate 标准化行为 |

#### 6.1.2 数据一致性风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| Fixture 过时 | oss-story.jsonl 可能与新代码不兼容 | 定期重新录制会话 |
| 时间戳漂移 | 绝对时间戳导致测试不稳定 | 测试中忽略时间戳字段 |

### 6.2 边界情况

#### 6.2.1 文本换行边界

```rust
// vt100_history.rs 中测试的边界情况
1. long_token_wraps:         // 45 字符文本在 20 列宽度下换行
2. emoji_and_cjk:            // 宽字符（Emoji/CJK）宽度计算
3. mixed_ansi_spans:         // ANSI 颜色序列与文本混合
4. word_wrap_no_mid_word_split:  // 词边界换行，不截断单词
5. em_dash_and_space_word_wrap:  // 特殊标点（em-dash）处理
```

#### 6.2.2 终端尺寸边界

```rust
// 测试用例覆盖的边界
- 宽度 20，高度 6（最小可用尺寸）
- 宽度 40，高度 10（标准尺寸）
- 视口高度 1（单行视口）
```

### 6.3 改进建议

#### 6.3.1 短期改进（高优先级）

1. **Fixture 文档化**
   ```markdown
   - 添加 oss-story.jsonl 的生成脚本和说明
   - 记录会话场景（用户做了什么操作）
   - 添加事件类型参考文档
   ```

2. **测试覆盖率提升**
   ```rust
   // 建议添加的测试
   - 多字节 UTF-8 字符处理
   - 零宽度连接符（ZWJ）序列
   - OSC 8 超链接序列
   - 极端尺寸（1x1 终端）
   ```

#### 6.3.2 中期改进（中优先级）

3. **Fixture 管理工具**
   ```rust
   // 建议添加 bin 工具
   - fixture-record: 录制新会话
   - fixture-validate: 验证 fixture 格式
   - fixture-trim: 裁剪会话长度
   ```

4. **参数化测试**
   ```rust
   // 使用 rstest 或类似框架
   #[rstest]
   #[case(20, 6)]
   #[case(40, 10)]
   #[case(80, 24)]
   fn test_history_insertion(#[case] width: u16, #[case] height: u16) {
       // 多尺寸测试
   }
   ```

#### 6.3.3 长期改进（低优先级）

5. **性能基准测试**
   ```rust
   // 使用 criterion 框架
   - 大文件（10k+ 行）插入性能
   - 复杂样式渲染性能
   - 内存使用分析
   ```

6. **可视化测试报告**
   ```markdown
   - 生成测试后的终端屏幕截图（文本形式）
   - 对比期望与实际输出
   - 集成到 CI 报告
   ```

### 6.4 维护检查清单

- [ ] 每次修改 `insert_history.rs` 后运行 `cargo test -p codex-tui --features vt100-tests`
- [ ] 每年重新录制 `oss-story.jsonl` 以匹配最新事件格式
- [ ] 监控 `vt100` crate 的更新，评估兼容性问题
- [ ] 确保新添加的测试用例覆盖边界情况（空输入、极端尺寸、特殊字符）

---

## 附录：事件类型完整列表

### A.1 Meta 事件（dir: meta）

| kind | 描述 |
|------|------|
| `session_start` | 会话开始，包含 cwd、model、provider 信息 |

### A.2 To TUI 事件（dir: to_tui）

| kind | variant / 子类型 | 描述 |
|------|-----------------|------|
| `app_event` | `RequestRedraw` | 请求重绘 |
| | `Redraw` | 执行重绘 |
| | `StartCommitAnimation` | 开始提交动画 |
| | `StopCommitAnimation` | 停止提交动画 |
| | `CommitTick` | 提交动画帧 |
| `codex_event` | `task_started` | 任务开始 |
| | `task_complete` | 任务完成 |
| | `agent_message` | Agent 完整消息 |
| | `agent_message_delta` | Agent 消息增量 |
| | `agent_reasoning_raw_content_delta` | Agent 推理内容增量 |
| | `session_configured` | 会话配置完成 |
| `key_event` | - | 键盘事件（Press/Release） |
| `insert_history` | - | 历史记录插入通知 |
| `log_line` | - | 日志输出行 |

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/tui 当前 HEAD*
