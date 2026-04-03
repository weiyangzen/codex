# Research: chat_small_idle_h2 (App Server)

## 场景与职责

此 snapshot 测试验证 **tui_app_server** 中 ChatWidget 在**小终端高度（2行）且空闲状态**下的渲染效果。相比 h1 测试，h2 提供了稍多的空间，可以显示更多界面元素。

**测试目的**：确保 ChatWidget 在高度为 2 行的限制下能够正确渲染，验证小空间下的布局适应能力。

## 功能点目的

1. **小空间适应**：验证 TUI 在小空间（2行）下的渲染能力
2. **内容优先级**：验证在有限空间下的内容优先级分配
3. **布局压缩**：测试布局系统的压缩能力
4. **渐进增强**：与 h1、h3 测试形成对比，展示渐进增强效果

## 具体技术实现

### Snapshot 内容
```
"                                        "
"                                        "
```

### 内容分析
- 显示两行空行（每行 40 个空格）
- 高度为 2 时，仍然可能无法显示有意义的内容
- 或者只显示最基本的占位符

### 关键代码路径

1. **测试函数**：
   - 文件：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 函数：`ui_snapshots_small_heights_idle` (约 line 9980)
   - 循环测试高度 1、2、3 的情况
   ```rust
   for h in [1, 2, 3] {
       let name = format!("chat_small_idle_h{h}");
       let mut terminal = Terminal::new(TestBackend::new(40, h)).expect("create terminal");
       terminal
           .draw(|f| chat.render(f.area(), f.buffer_mut()))
           .expect("draw chat idle");
       assert_snapshot!(name, terminal.backend());
   }
   ```

2. **渲染流程**：
   - 使用 `TestBackend` 进行测试渲染
   - 宽度：40 字符
   - 高度：2 行
   - 状态：空闲（无运行中的任务）

3. **空间分配**：
   - ChatWidget 尝试在 2 行空间内渲染
   - 可能包括：
     - 状态指示器（如果有）
     - 输入框（压缩或隐藏）
     - 历史记录区域（可能完全隐藏）

### 测试参数

| 参数 | 值 |
|------|-----|
| 宽度 | 40 字符 |
| 高度 | 2 行 |
| 状态 | 空闲（idle） |
| 后端 | TestBackend |

### 高度系列测试对比

| 高度 | Snapshot 名称 | 内容 |
|------|--------------|------|
| 1 | `chat_small_idle_h1` | 1 行空行 |
| 2 | `chat_small_idle_h2` | 2 行空行 |
| 3 | `chat_small_idle_h3` | 可能有内容 |

### 空闲状态 vs 运行状态

**空闲状态** (`chat_small_idle_h*`):
- 无任务运行
- 无状态指示器
- 可能只显示输入区域

**运行状态** (`chat_small_running_h*`):
- 有任务运行
- 显示状态指示器
- 可能有更多动态内容

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `chatwidget::ChatWidget` | 主聊天控件 |
| `test_backend::TestBackend` | 测试用的渲染后端 |
| `ratatui::Terminal` | 终端抽象 |
| `bottom_pane::BottomPane` | 底部面板（输入区域） |

### 渲染组件
- `StatusIndicatorWidget`：状态指示器（空闲时可能隐藏）
- `ChatComposer`：聊天输入框
- `HistoryCell`：历史记录单元（空间不足时隐藏）

### 空间管理策略
1. **优先级排序**：
   - 高：输入框（如果可能）
   - 中：状态指示器
   - 低：历史记录

2. **空间不足处理**：
   - 隐藏低优先级组件
   - 压缩高优先级组件
   - 必要时显示空白

## 风险、边界与改进建议

### 当前风险
1. **可用性**：2 行高度实际上无法提供可用界面
2. **信息缺失**：用户无法看到历史记录或输入反馈
3. **输入困难**：无法有效进行文本输入

### 边界情况
1. **最小可用高度**：确定实际可用的最小高度
2. **内容溢出**：处理超出显示区域的内容
3. **光标位置**：在极小空间下的光标定位

### 改进建议
1. **最小高度提示**：当空间过小时显示提示信息
   ```
   "Terminal too small"
   "Minimum: 10 rows"
   ```
2. **紧凑模式**：设计专门的紧凑布局模式
3. **全屏切换**：提供全屏模式以获得更多空间
4. **响应式布局**：根据可用空间动态调整布局

### 实际应用场景
- 此测试主要用于**回归测试**和**鲁棒性验证**
- 实际使用中，2 行高度的终端不现实
- 但确保了代码在意外情况下的稳定性

### 与 TUI 版本的关系
- 与 `codex_tui__chatwidget__tests__chat_small_idle_h2.snap` 保持平行实现
- 两个版本使用相同的测试参数和逻辑
- 布局行为一致

### 测试验证点
1. ✅ 不 panic
2. ✅ 返回有效的渲染输出
3. ✅ 输出包含 2 行
4. ✅ 与 h1、h3 测试形成有效对比

### 相关 Snapshots
| Snapshot | 高度 | 状态 | 预期内容 |
|----------|------|------|----------|
| `chat_small_idle_h1` | 1 | 空闲 | 1 行空行 |
| `chat_small_idle_h2` | 2 | 空闲 | 2 行空行 |
| `chat_small_idle_h3` | 3 | 空闲 | 可能有基本内容 |
| `chat_small_running_h1` | 1 | 运行 | 可能有状态指示器 |
| `chat_small_running_h2` | 2 | 运行 | 状态指示器 + 可能输入框 |
| `chat_small_running_h3` | 3 | 运行 | 更多内容 |

### 结论
`chat_small_idle_h2` 测试是 ChatWidget 小高度系列测试的一部分，用于验证组件在极端空间限制下的鲁棒性。虽然 2 行高度的实际使用场景有限，但此测试确保了代码的健壮性和可靠性。
