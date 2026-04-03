# 研究文档：exploring_step3_start_cat_foo

## 场景与职责

此 snapshot 测试用例验证 **tui_app_server** 中 "Exploring" 功能的第三步：在已有完成命令的基础上开始新的读取操作（`cat foo.txt`）。这是探索模式系列测试的第三步，验证多命令追加和混合状态显示。

**测试场景**：
- 代理已完成 `ls -la`（状态：Explored）
- 代理开始新的读取操作 `cat foo.txt`
- ExecCell 包含一个已完成命令和一个活动命令
- 验证混合状态下的显示内容

**Snapshot 内容**：
```
• Exploring
  └ List ls -la
    Read foo.txt
```

## 功能点目的

1. **多命令累积**：支持在同一个探索单元中累积多个相关命令
2. **混合状态显示**：当一个命令完成而另一个正在进行时，整体状态显示为 "Exploring"
3. **命令类型区分**：区分 "List" 和 "Read" 操作类型，提供语义化的操作描述
4. **层级缩进**：使用缩进表示命令间的逻辑关系

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` - 函数 `exec_history_extends_previous_when_consecutive`

### 核心测试逻辑

```rust
#[tokio::test]
async fn exec_history_extends_previous_when_consecutive() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    // 1) Start "ls -la" (List)
    let begin_ls = begin_exec(&mut chat, "call-ls", "ls -la");
    assert_snapshot!("exploring_step1_start_ls", active_blob(&chat));

    // 2) Finish "ls -la"
    end_exec(&mut chat, begin_ls, "", "", 0);
    assert_snapshot!("exploring_step2_finish_ls", active_blob(&chat));

    // 3) Start "cat foo.txt" (Read)
    let begin_cat_foo = begin_exec(&mut chat, "call-cat-foo", "cat foo.txt");
    assert_snapshot!("exploring_step3_start_cat_foo", active_blob(&chat));
    
    // 后续步骤...
}
```

### 命令追加逻辑

位于 `codex-rs/tui_app_server/src/exec_cell/model.rs`：

```rust
impl ExecCell {
    pub(crate) fn with_added_call(
        &self,
        call_id: String,
        command: Vec<String>,
        parsed: Vec<ParsedCommand>,
        source: ExecCommandSource,
        interaction_input: Option<String>,
    ) -> Option<Self> {
        let call = ExecCall {
            call_id,
            command,
            parsed,
            output: None,
            source,
            start_time: Some(Instant::now()),
            duration: None,
            interaction_input,
        };
        
        // 只有当前是探索模式且新命令也是探索命令时，才追加到同一单元
        if self.is_exploring_cell() && Self::is_exploring_call(&call) {
            Some(Self {
                calls: [self.calls.clone(), vec![call]].concat(),
                animations_enabled: self.animations_enabled,
            })
        } else {
            None  // 返回 None 表示应该创建新单元
        }
    }
}
```

### 混合状态判定

```rust
impl ExecCell {
    pub(crate) fn is_active(&self) -> bool {
        // 只要有一个调用没有输出（未完成），整体就是活动状态
        self.calls.iter().any(|c| c.output.is_none())
    }
}
```

### 多命令渲染逻辑

位于 `codex-rs/tui_app_server/src/exec_cell/render.rs`：

```rust
impl ExecCell {
    fn exploring_display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // ... 标题行（Exploring/Explored）...
        
        let mut calls = self.calls.clone();
        let mut out_indented = Vec::new();
        
        while !calls.is_empty() {
            let mut call = calls.remove(0);
            
            // 读取操作合并优化：连续的 Read 操作合并显示
            if call.parsed.iter().all(|p| matches!(p, ParsedCommand::Read { .. })) {
                while let Some(next) = calls.first() {
                    if next.parsed.iter().all(|p| matches!(p, ParsedCommand::Read { .. })) {
                        call.parsed.extend(next.parsed.clone());
                        calls.remove(0);
                    } else {
                        break;
                    }
                }
            }
            
            // 根据命令类型生成显示行
            for parsed in &call.parsed {
                match parsed {
                    ParsedCommand::ListFiles { cmd, path } => {
                        lines.push(("List", vec![path.clone().unwrap_or(cmd.clone()).into()]));
                    }
                    ParsedCommand::Read { name, .. } => {
                        lines.push(("Read", vec![name.clone().into()]));
                    }
                    // ...
                }
            }
        }
        
        // 添加缩进前缀：第一行用 "  └ "，后续用 "    "
        out.extend(prefix_lines(out_indented, "  └ ".dim(), "    ".into()));
        out
    }
}
```

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例实现 |
| `codex-rs/tui_app_server/src/exec_cell/model.rs` | ExecCell 命令追加逻辑 |
| `codex-rs/tui_app_server/src/exec_cell/render.rs` | 多命令渲染和合并逻辑 |
| `codex-rs/tui_app_server/src/render/line_utils.rs` | 行前缀工具函数 |

### 相关数据结构

```rust
// 解析后的 Read 命令
codex_protocol::parse_command::ParsedCommand::Read {
    name: String,        // 文件名，如 "foo.txt"
    path: Option<String>, // 完整路径
    // ...
}

// ExecCell 内部结构
pub(crate) struct ExecCell {
    pub(crate) calls: Vec<ExecCall>,  // 多个命令调用
    animations_enabled: bool,
}
```

### 命令追加流程

```
ExecCommandBeginEvent (cat foo.txt)
    ↓
ChatWidget::handle_codex_event
    ↓
检查现有 active_cell 是否为探索模式
    ↓
ExecCell::with_added_call(new_call)
    ↓
条件检查：
  - self.is_exploring_cell() == true ✅
  - Self::is_exploring_call(&call) == true ✅
    ↓
追加新 ExecCall 到 calls 向量
    ↓
保持同一 ExecCell，更新显示
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `codex_protocol::parse_command::ParsedCommand` | 命令类型枚举 |
| `codex_shell_command::parse_command` | 命令解析 |
| `crate::render::line_utils::prefix_lines` | 行前缀添加 |

### 模块交互

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ExecCell 状态（Step 3）                           │
│                                                                     │
│  calls: [                                                          │
│    ExecCall {  // ls -la                                           │
│      output: Some(...),      ← 已完成                              │
│      parsed: [ListFiles { ... }],                                  │
│      ...                                                           │
│    },                                                              │
│    ExecCall {  // cat foo.txt                                      │
│      output: None,           ← 活动中                              │
│      parsed: [Read { name: "foo.txt" }],                           │
│      ...                                                           │
│    }                                                               │
│  ]                                                                  │
│                                                                     │
│  is_active() = true  // 因为有 output == None 的调用               │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      渲染输出                                        │
│                                                                     │
│  • Exploring           ← 因为 is_active() == true                  │
│    └ List ls -la      ← 第一个命令                                 │
│      Read foo.txt     ← 第二个命令（缩进对齐）                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **内存累积**：长时间探索会话可能导致 calls 向量过大
2. **渲染性能**：大量命令时渲染可能变慢
3. **命令顺序依赖**：渲染逻辑依赖 calls 的顺序，乱序到达可能导致显示异常

### 边界情况

| 场景 | 当前行为 | 注意事项 |
|-----|---------|---------|
| 非探索命令插入 | 创建新 ExecCell | 中断探索链 |
| 大量命令（>100） | 未限制 | 可能影响性能 |
| 相同文件重复读取 | 合并显示 | Read 合并逻辑 |
| 混合类型命令 | 分别显示 | List + Read 不合并 |

### 改进建议

1. **命令数量限制**：
   ```rust
   const MAX_EXPLORING_CALLS: usize = 50;
   
   fn with_added_call(...) -> Option<Self> {
       if self.calls.len() >= MAX_EXPLORING_CALLS {
           // 强制创建新单元，避免过度累积
           return None;
       }
       // ...
   }
   ```

2. **命令分组显示**：
   ```rust
   // 建议：按类型分组显示
   • Exploring
     └ List ls -la
     └ Read 3 files: foo.txt, bar.txt, baz.txt
   ```

3. **时间戳显示**：
   ```rust
   // 建议：添加相对时间
   • Exploring (started 2m ago)
     └ List ls -la (30s ago)
       Read foo.txt
   ```

4. **测试扩展**：
   ```rust
   // 建议添加的测试
   #[tokio::test]
   async fn exploring_many_calls() {
       // 测试大量命令的累积行为
   }
   
   #[tokio::test]
   async fn exploring_non_exploring_interrupt() {
       // 测试非探索命令中断探索链
       let begin_ls = begin_exec(&mut chat, "call-ls", "ls -la");
       end_exec(&mut chat, begin_ls, "", "", 0);
       
       // 插入非探索命令（如 UserShell 源的命令）
       let begin_shell = begin_exec_with_source(&mut chat, "call-shell", "make", ExecCommandSource::UserShell);
       // 验证创建了新单元
   }
   ```

### 系列测试上下文

本测试是 "exploring" 系列测试的第三步，验证探索模式的核心特性——**命令累积**：

| 步骤 | Snapshot | 状态 | 操作 | 验证点 |
|-----|----------|------|------|--------|
| 1 | `exploring_step1_start_ls` | Exploring | 开始 `ls -la` | 基础探索模式 |
| 2 | `exploring_step2_finish_ls` | Explored | 完成 `ls -la` | 状态转换 |
| 3 | `exploring_step3_start_cat_foo` | **Exploring** | **开始 `cat foo.txt`** | **命令累积** |
| 4 | `exploring_step4_finish_cat_foo` | Explored | 完成 `foo.txt` | 完成累积 |
| 5 | `exploring_step5_finish_sed_range` | Explored | 完成 `sed` | Read 合并 |
| 6 | `exploring_step6_finish_cat_bar` | Explored | 完成 `bar.txt` | 多文件显示 |

本测试的关键验证点是：
- 新命令正确追加到现有探索单元
- 混合状态（一个完成 + 一个活动）正确显示为 "Exploring"
- 不同命令类型（List vs Read）正确分类显示
