# prompt_for_init_command.md 研究文档

## 场景与职责

`prompt_for_init_command.md` 是 Codex TUI 中 `/init` 斜杠命令使用的提示词模板文件。该文件定义了当用户执行 `/init` 命令时，系统向 AI 模型发送的指令，用于生成项目的 `AGENTS.md` 贡献者指南文档。

该文件是 TUI 与 AI 模型交互的关键配置，直接影响生成的 `AGENTS.md` 文档的质量和结构。

## 功能点目的

### 1. 指令生成目标
指导 AI 生成一份清晰、简洁、结构化的项目贡献者指南（`AGENTS.md`），包含：
- 项目结构和模块组织
- 构建、测试和开发命令
- 编码风格和命名约定
- 测试指南
- 提交和 PR 规范

### 2. 输出规范约束
| 约束项 | 要求 |
|--------|------|
| 文档标题 | "Repository Guidelines" |
| 结构 | 使用 Markdown 标题 (#, ##) |
| 篇幅 | 200-400 词（最优） |
| 风格 | 简洁、直接、专业、教学式 |
| 示例 | 提供命令、路径、命名模式示例 |

### 3. 推荐章节结构
```markdown
# Repository Guidelines

## Project Structure & Module Organization
## Build, Test, and Development Commands
## Coding Style & Naming Conventions
## Testing Guidelines
## Commit & Pull Request Guidelines
## (Optional) Security & Configuration Tips / Architecture Overview / Agent-Specific Instructions
```

## 具体技术实现

### 调用链路

```
用户输入 /init
    ↓
chat_composer.rs: 识别斜杠命令
    ↓
command_popup.rs: 显示命令补全（包含 Init）
    ↓
slash_command.rs: SlashCommand::Init 定义
    ↓
chatwidget.rs: dispatch_command(SlashCommand::Init)
    ↓
custom_prompt_view.rs: 显示自定义提示输入界面
    ↓
AI 请求: prompt_for_init_command.md 作为系统提示
    ↓
生成 AGENTS.md 文件
```

### 代码实现路径

#### 1. 斜杠命令定义
**文件**: `src/slash_command.rs`
```rust
#[derive(...)]
pub enum SlashCommand {
    // ... 其他命令
    Init,  // 第 30 行
    // ...
}

impl SlashCommand {
    pub fn description(self) -> &'static str {
        match self {
            // ...
            SlashCommand::Init => "create an AGENTS.md file with instructions for Codex",
            // ...
        }
    }

    pub fn available_during_task(self) -> bool {
        match self {
            // ...
            SlashCommand::Init => false,  // 任务运行时不可用
            // ...
        }
    }
}
```

#### 2. 命令分发处理
**文件**: `src/chatwidget.rs` (约第 4339 行)
```rust
SlashCommand::Init => {
    let init_target = self.config.cwd.join(DEFAULT_PROJECT_DOC_FILENAME);
    if init_target.exists() {
        let message = format!(
            "{DEFAULT_PROJECT_DOC_FILENAME} already exists here. Skipping /init to avoid overwriting it."
        );
        // ... 显示警告
    } else {
        // 触发 AGENTS.md 生成流程
        self.app_event_tx.send(AppEvent::GenerateAgentsMd);
    }
}
```

#### 3. 自定义提示视图
**文件**: `src/bottom_pane/custom_prompt_view.rs`
- 提供多行文本输入界面
- 支持占位符提示
- 处理提交和取消事件

### 提示词模板内容

**文件**: `codex-rs/tui/prompt_for_init_command.md`
```markdown
Generate a file named AGENTS.md that serves as a contributor guide for this repository.
Your goal is to produce a clear, concise, and well-structured document with descriptive headings and actionable explanations for each section.
Follow the outline below, but adapt as needed — add sections if relevant, and omit those that do not apply to this project.

Document Requirements
...
```

## 关键代码路径与文件引用

### 核心实现文件
| 文件 | 行数 | 职责 |
|------|------|------|
| `src/slash_command.rs` | ~217 | 定义 `SlashCommand::Init` 及其元数据 |
| `src/chatwidget.rs` | ~5000+ | 命令分发和处理逻辑 |
| `src/bottom_pane/custom_prompt_view.rs` | ~247 | 自定义提示输入 UI |
| `src/bottom_pane/command_popup.rs` | ~200+ | 命令弹出框（包含 Init 命令） |
| `src/bottom_pane/chat_composer.rs` | ~2000+ | 识别 `/` 开头的命令 |

### 测试文件
| 文件 | 说明 |
|------|------|
| `src/chatwidget/tests.rs` | 包含 `SlashCommand::Init` 的测试用例 |

### 相关常量
```rust
// src/chatwidget.rs
const DEFAULT_PROJECT_DOC_FILENAME: &str = "AGENTS.md";  // 来自 codex_core::project_doc
```

## 依赖与外部交互

### 内部依赖
| 模块 | 交互方式 |
|------|----------|
| `codex_core::project_doc` | 提供 `DEFAULT_PROJECT_DOC_FILENAME` 常量 |
| `codex_core::config::Config` | 获取当前工作目录 (`config.cwd`) |
| `AppEventSender` | 发送生成请求事件 |

### 外部交互
| 组件 | 交互 |
|------|------|
| AI 模型 | 接收提示词模板，生成 AGENTS.md 内容 |
| 文件系统 | 检查 AGENTS.md 是否已存在，避免覆盖 |
| 用户界面 | 显示输入框、确认对话框、成功/失败提示 |

### 数据流
```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   用户输入 /init  │ --> │  chatwidget.rs   │ --> │  检查文件存在性  │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              │                           │
                              v                           v
                       ┌──────────────┐            ┌──────────────┐
                       │ 显示警告提示  │            │ 发送 AI 请求  │
                       │ (文件已存在)  │            │              │
                       └──────────────┘            └──────────────┘
                                                           │
                                                           v
                                                   ┌──────────────┐
                                                   │ AI 生成内容   │
                                                   │ 使用提示模板  │
                                                   └──────────────┘
                                                           │
                                                           v
                                                   ┌──────────────┐
                                                   │ 写入 AGENTS.md│
                                                   └──────────────┘
```

## 风险、边界与改进建议

### 风险点

#### 1. 文件覆盖风险
```rust
// chatwidget.rs
if init_target.exists() {
    // 仅显示警告，不阻止生成
    let message = format!("... Skipping /init to avoid overwriting it.");
}
```
- 当前实现会跳过已存在的文件
- 用户可能需要手动删除或重命名旧文件

#### 2. 提示词模板维护
- 模板文件 `prompt_for_init_command.md` 需要与代码同步更新
- 变更提示词可能影响生成文档的质量

#### 3. 多语言支持
- 当前提示词为英文
- 非英语项目可能需要本地化版本

### 边界条件

#### 1. 任务运行时不可用
```rust
SlashCommand::Init => false,  // available_during_task
```
- 当 AI 正在处理任务时，无法执行 `/init`
- 需要等待当前任务完成

#### 2. 工作目录限制
- AGENTS.md 生成在当前工作目录 (`config.cwd`)
- 子目录项目可能需要切换目录

#### 3. 权限问题
- 需要写入当前目录的权限
- 只读文件系统会失败

### 改进建议

#### 1. 增强文件处理
```rust
// 建议添加覆盖确认
if init_target.exists() {
    // 显示确认对话框："AGENTS.md 已存在，是否覆盖？"
    // 选项：覆盖 / 备份后覆盖 / 取消
}
```

#### 2. 多语言支持
```rust
// 建议根据项目语言选择提示词模板
let prompt_template = match detect_project_language() {
    Language::Chinese => "prompt_for_init_command_zh.md",
    _ => "prompt_for_init_command.md",
};
```

#### 3. 交互式生成
```rust
// 建议添加可选的交互式问题
let questions = vec![
    "项目的主要编程语言是什么？",
    "使用的构建工具是什么？",
    "是否有特殊的编码规范？",
];
// 将答案注入提示词
```

#### 4. 模板自定义
```rust
// 允许项目自定义提示词模板
// 检查 .codex/init_prompt.md 是否存在
let custom_prompt = config.cwd.join(".codex/init_prompt.md");
let prompt = if custom_prompt.exists() {
    fs::read_to_string(custom_prompt)?
} else {
    include_str!("../prompt_for_init_command.md").to_string()
};
```

#### 5. 生成预览
```rust
// 显示生成的 AGENTS.md 预览
// 用户确认后再写入文件
self.show_preview_dialog(generated_content, |confirmed| {
    if confirmed {
        fs::write(init_target, generated_content)?;
    }
});
```

#### 6. 版本控制集成
```rust
// 检测 Git 仓库，自动添加文件到 Git
if is_git_repo(&config.cwd) {
    // 提示用户是否执行 `git add AGENTS.md`
}
```
