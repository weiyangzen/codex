# live_reload.rs 研究文档

## 场景与职责

`live_reload.rs` 是 Codex Rust 核心库的集成测试套件，专注于验证 **Skill 系统的实时重载功能**。该功能允许在运行时检测 Skill 文件的变更，并自动刷新缓存，使新会话能够使用更新后的 Skill 内容。

### 核心职责
1. **验证 Skill 文件变更检测**：文件系统监视器正确检测 Skill 文件修改
2. **验证 Skill 缓存刷新**：变更后缓存被清除，新请求使用更新内容
3. **验证事件通知**：`SkillsUpdateAvailable` 事件正确发出
4. **测试容错机制**：当文件监视不可靠时，手动清除缓存的备用方案

---

## 功能点目的

### 1. Skill 实时重载测试 (`live_skills_reload_refreshes_skill_cache_after_skill_change`)
- **目的**：验证 Skill 文件变更后，新会话使用更新后的内容
- **测试流程**：
  1. 创建初始 Skill 文件（v1）
  2. 提交第一轮对话，验证请求包含 v1 内容
  3. 修改 Skill 文件为 v2
  4. 等待 `SkillsUpdateAvailable` 事件（或手动清除缓存）
  5. 提交第二轮对话，验证请求包含 v2 内容

---

## 具体技术实现

### 测试基础设施

#### Skill 文件创建

```rust
fn write_skill(home: &Path, name: &str, description: &str, body: &str) -> PathBuf {
    let skill_dir = home.join("skills").join(name);
    fs::create_dir_all(&skill_dir).expect("create skill dir");
    let contents = format!("---\nname: {name}\ndescription: {description}\n---\n\n{body}\n");
    let path = skill_dir.join("SKILL.md");
    fs::write(&path, contents).expect("write skill");
    path
}
```

Skill 文件使用 YAML frontmatter 格式：
```markdown
---
name: demo
description: demo skill
---

skill body content
```

#### Skill 内容检测

```rust
fn contains_skill_body(request: &ResponsesRequest, skill_body: &str) -> bool {
    request
        .message_input_texts("user")
        .iter()
        .any(|text| text.contains(skill_body) && text.contains("<skill>"))
}
```

#### 带 Skill 的对话提交

```rust
async fn submit_skill_turn(test: &TestCodex, skill_path: PathBuf, prompt: &str) -> Result<()> {
    let session_model = test.session_configured.model.clone();
    test.codex
        .submit(Op::UserTurn {
            items: vec![
                UserInput::Text {
                    text: prompt.to_string(),
                    text_elements: Vec::new(),
                },
                UserInput::Skill {
                    name: "demo".to_string(),
                    path: skill_path,
                },
            ],
            final_output_json_schema: None,
            cwd: test.cwd_path().to_path_buf(),
            approval_policy: AskForApproval::Never,
            sandbox_policy: SandboxPolicy::DangerFullAccess,
            model: session_model,
            effort: None,
            summary: None,
            service_tier: None,
            collaboration_mode: None,
            personality: None,
        })
        .await?;

    wait_for_event(test.codex.as_ref(), |event| {
        matches!(event, EventMsg::TurnComplete(_))
    })
    .await;
    Ok(())
}
```

#### 文件变更等待

```rust
let saw_skills_update = timeout(Duration::from_secs(5), async {
    loop {
        match test.codex.next_event().await {
            Ok(event) => {
                if matches!(event.msg, EventMsg::SkillsUpdateAvailable) {
                    break;
                }
            }
            Err(err) => panic!("event stream ended unexpectedly: {err}"),
        }
    }
})
.await;

// 如果文件监视不可靠，手动清除缓存
if saw_skills_update.is_err() {
    test.thread_manager.skills_manager().clear_cache();
}
```

### 测试配置

```rust
let mut builder = test_codex()
    .with_pre_build_hook(move |home| {
        write_skill(home, "demo", "demo skill", skill_v1);
    })
    .with_config(|config| {
        enable_trusted_project(config);
    });
```

使用 `enable_trusted_project` 确保 Skill 在受信任项目中加载：

```rust
fn enable_trusted_project(config: &mut codex_core::config::Config) {
    config.active_project = ProjectConfig {
        trust_level: Some(TrustLevel::Trusted),
    };
}
```

### Mock 服务器设置

```rust
let responses = mount_sse_sequence(
    &server,
    vec![
        responses::sse(vec![responses::ev_completed("resp-1")]),
        responses::sse(vec![responses::ev_completed("resp-2")]),
    ],
)
.await;
```

使用 `mount_sse_sequence` 设置两阶段响应：
1. 第一轮对话响应
2. 第二轮对话响应

---

## 关键代码路径与文件引用

### 测试文件
- **当前文件**：`codex-rs/core/tests/suite/live_reload.rs` (151 行)

### Skill 系统实现
- **`codex-rs/core/src/skills/`**：Skill 管理实现
- **`codex-rs/core/src/skills/manager.rs`**：Skill 管理器（推测）
- **`codex-rs/core/src/skills/watcher.rs`**：文件监视实现（推测）

### 协议定义
- **`codex-rs/protocol/src/protocol.rs`**：
  - `EventMsg::SkillsUpdateAvailable`
  - `UserInput::Skill`

### 配置定义
- **`codex-rs/protocol/src/config_types.rs`**：
  - `TrustLevel`
  - `ProjectConfig`

### 测试支持库
- **`codex-rs/core/tests/common/responses.rs`**：
  - `mount_sse_sequence`：顺序响应 Mock
- **`codex-rs/core/tests/common/test_codex.rs`**：
  - `TestCodex` 结构体
  - `thread_manager` 访问

---

## 依赖与外部交互

### 外部依赖
1. **wiremock**：HTTP Mock 服务器
2. **tokio**：异步运行时
3. **notify**（推测）：文件系统监视
4. **tempfile**：临时目录管理

### 内部依赖
1. **codex_core**：核心库（Skill 管理器、配置）
2. **codex_protocol**：协议类型
3. **core_test_support**：测试支持库

### 文件系统交互
- 在临时目录中创建 Skill 文件
- 修改 Skill 文件触发重载
- 文件监视器检测变更

---

## 风险、边界与改进建议

### 已知风险

1. **文件监视不可靠性**：
   - 注释说明："Some environments do not reliably surface file watcher events"
   - 测试包含手动清除缓存的备用方案

2. **时序问题**：
   - 文件写入和事件检测之间可能有延迟
   - 使用 5 秒超时等待事件

3. **平台差异**：
   - 文件系统监视行为在不同平台可能有差异
   - 测试使用 `#![allow(clippy::expect_used, clippy::unwrap_used)]` 放宽检查

### 边界情况

1. **并发修改**：
   - 当前测试未覆盖并发修改场景
   - 建议增加多 Skill 同时修改的测试

2. **删除和重建**：
   - 当前测试只覆盖内容修改
   - 建议增加删除后重建的测试

3. **无效 Skill 文件**：
   - 当前测试未覆盖无效 YAML frontmatter 的处理
   - 建议增加错误处理测试

4. **权限变更**：
   - 当前测试未覆盖文件权限变更
   - 建议增加权限不足场景测试

### 改进建议

1. **增加测试覆盖**：
   - 测试 Skill 删除场景
   - 测试 Skill 重命名场景
   - 测试多个 Skill 同时变更
   - 测试深层目录结构变更

2. **可靠性改进**：
   - 增加文件监视健康检查
   - 提供手动刷新 API
   - 增加变更确认机制

3. **性能测试**：
   - 大量 Skill 文件的加载性能
   - 频繁变更的处理性能

4. **错误处理测试**：
   - 无效 Skill 文件格式
   - 文件读取权限错误
   - 磁盘空间不足

5. **跨平台测试**：
   - 在 Windows 上验证文件监视
   - 在 macOS 上验证文件监视
   - 在 Linux 上验证文件监视

### 相关测试

- **`codex-rs/core/tests/suite/skills.rs`**：Skill 系统基础功能测试
- **`codex-rs/core/tests/suite/skill_approval.rs`**：Skill 审批流程测试
