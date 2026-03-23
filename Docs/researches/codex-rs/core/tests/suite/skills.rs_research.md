# skills.rs 研究文档

## 场景与职责

`skills.rs` 是 Codex Core 的集成测试套件，专注于验证 **Skill（技能）系统** 的核心功能。该测试文件确保 Skill 的加载、注入、错误处理和系统 Skill 管理能够正确工作。

核心测试场景包括：
1. **Skill 指令注入** - 验证用户回合中 Skill 指令是否正确注入到模型输入
2. **Skill 加载错误处理** - 验证损坏的 Skill 文件被正确处理并报告错误
3. **系统 Skill 缓存** - 验证嵌入式系统 Skill 正确安装和加载

## 功能点目的

### 1. Skill 注入机制

当用户在输入中使用 `$skill-name` 语法时，系统需要：
1. 解析 Skill 引用
2. 加载 Skill 定义（SKILL.md）
3. 将 Skill 内容注入到模型输入中

### 2. Skill 加载错误处理

Skill 加载可能失败的原因：
- YAML 解析错误
- 缺少必需字段
- 文件系统权限问题

### 3. 系统 Skill 管理

系统 Skill 是 Codex 内置的技能，存储在：
```
<CODEX_HOME>/skills/.system/<skill-name>/SKILL.md
```

## 具体技术实现

### 关键测试流程

#### 1. Skill 创建辅助函数

```rust
fn write_skill(home: &Path, name: &str, description: &str, body: &str) -> std::path::PathBuf {
    let skill_dir = home.join("skills").join(name);
    fs::create_dir_all(&skill_dir).unwrap();
    let contents = format!("---\nname: {name}\ndescription: {description}\n---\n\n{body}\n");
    let path = skill_dir.join("SKILL.md");
    fs::write(&path, contents).unwrap();
    path
}
```

生成的 SKILL.md 格式：
```markdown
---
name: demo
description: demo skill
---

skill body
```

#### 2. 系统 Skill 路径辅助函数

```rust
fn system_skill_md_path(home: impl AsRef<Path>, name: &str) -> std::path::PathBuf {
    home.as_ref()
        .join("skills")
        .join(".system")
        .join(name)
        .join("SKILL.md")
}
```

#### 3. Skill 注入验证测试

```rust
#[tokio::test]
async fn user_turn_includes_skill_instructions() -> Result<()> {
    let server = start_mock_server().await;
    let skill_body = "skill body";
    let mut builder = test_codex().with_pre_build_hook(|home| {
        write_skill(home, "demo", "demo skill", skill_body);
    });
    let test = builder.build(&server).await?;
    
    // 使用 $demo 引用 Skill
    test.codex
        .submit(Op::UserTurn {
            items: vec![
                UserInput::Text {
                    text: "please use $demo".to_string(),
                    text_elements: Vec::new(),
                },
                UserInput::Skill {
                    name: "demo".to_string(),
                    path: skill_path.clone(),
                },
            ],
            // ... 其他参数
        })
        .await?;
    
    // 验证请求中包含 Skill 指令
    let request = mock.single_request();
    let user_texts = request.message_input_texts("user");
    assert!(
        user_texts.iter().any(|text| {
            text.contains("<skill>\n<name>demo</name>")
                && text.contains("<path>")
                && text.contains(skill_body)
        }),
        "expected skill instructions in user input"
    );
}
```

#### 4. Skill 加载错误测试

```rust
#[tokio::test]
async fn skill_load_errors_surface_in_session_configured() -> Result<()> {
    let server = start_mock_server().await;
    let mut builder = test_codex().with_pre_build_hook(|home| {
        let skill_dir = home.join("skills").join("broken");
        fs::create_dir_all(&skill_dir).unwrap();
        fs::write(skill_dir.join("SKILL.md"), "not yaml").unwrap();
    });
    let test = builder.build(&server).await?;
    
    // 请求列出 Skill
    test.codex
        .submit(Op::ListSkills {
            cwds: Vec::new(),
            force_reload: false,
        })
        .await?;
    
    // 验证错误报告
    let response = wait_for_event_match(...).await;
    assert_eq!(errors.len(), 1, "expected one load error");
    assert!(error_path.ends_with("skills/broken/SKILL.md"));
}
```

#### 5. 系统 Skill 验证测试

```rust
#[tokio::test]
async fn list_skills_includes_system_cache_entries() -> Result<()> {
    const SYSTEM_SKILL_NAME: &str = "skill-creator";
    
    let server = start_mock_server().await;
    let mut builder = test_codex().with_pre_build_hook(|home| {
        // 验证系统 Skill 尚未安装
        let system_skill_path = system_skill_md_path(home, SYSTEM_SKILL_NAME);
        assert!(!system_skill_path.exists());
    });
    let test = builder.build(&server).await?;
    
    // 验证系统 Skill 已自动安装
    let system_skill_path = system_skill_md_path(test.codex_home_path(), SYSTEM_SKILL_NAME);
    assert!(system_skill_path.exists());
    
    // 验证 Skill 内容正确
    let system_skill_contents = fs::read_to_string(&system_skill_path)?;
    assert!(system_skill_contents.contains("name: skill-creator"));
    
    // 验证 ListSkills 响应包含系统 Skill
    test.codex.submit(Op::ListSkills { ... }).await?;
    let skill = skills.iter().find(|skill| skill.name == SYSTEM_SKILL_NAME);
    assert_eq!(skill.scope, codex_protocol::protocol::SkillScope::System);
}
```

### 关键数据结构

#### UserInput 枚举

```rust
pub enum UserInput {
    Text {
        text: String,
        text_elements: Vec<TextElement>,
    },
    Skill {
        name: String,
        path: PathBuf,
    },
    // ...
}
```

#### Skill 元数据

```rust
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    pub short_description: Option<String>,
    pub interface: Option<SkillInterface>,
    pub dependencies: Option<SkillDependencies>,
    pub policy: Option<SkillPolicy>,
    pub permission_profile: Option<PermissionProfile>,
    pub path_to_skills_md: PathBuf,
    pub scope: SkillScope,  // User | System | Project
}
```

#### SkillScope 枚举

```rust
pub enum SkillScope {
    User,    // 用户定义的 Skill
    System,  // 系统内置的 Skill
    Project, // 项目特定的 Skill
}
```

#### ListSkillsResponse

```rust
pub struct ListSkillsResponse {
    pub skills: Vec<SkillEntry>,
}

pub struct SkillEntry {
    pub cwd: PathBuf,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillError>,
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/skills.rs` - 本测试文件
- `codex-rs/core/tests/common/test_codex.rs` - 测试基础设施

### 被测试的源代码
- `codex-rs/core/src/skills/mod.rs` - Skill 模块入口
- `codex-rs/core/src/skills/loader.rs` - Skill 加载器
- `codex-rs/core/src/skills/manager.rs` - Skill 管理器
- `codex-rs/core/src/skills/model.rs` - Skill 模型定义
- `codex-rs/core/src/skills/injection.rs` - Skill 注入逻辑
- `codex-rs/core/src/skills/system.rs` - 系统 Skill 管理

### 核心测试用例

| 测试用例 | 描述 |
|---------|------|
| `user_turn_includes_skill_instructions` | 验证用户回合包含 Skill 指令 |
| `skill_load_errors_surface_in_session_configured` | 验证 Skill 加载错误被报告 |
| `list_skills_includes_system_cache_entries` | 验证系统 Skill 被正确加载 |

### Skill 加载代码路径

1. **初始化加载** - `skills::manager::SkillsManager::load_skills`
2. **文件解析** - `skills::loader::load_skill_from_path`
3. **YAML 解析** - `serde_yaml` 解析 frontmatter
4. **错误收集** - `skills::model::SkillLoadOutcome`
5. **系统 Skill 安装** - `skills::system::install_system_skills`

### Skill 注入代码路径

1. **引用检测** - `skills::injection::collect_explicit_skill_mentions`
2. **内容构建** - `skills::injection::build_skill_injections`
3. **输入构造** - `instructions::user_instructions::build_user_instructions`

## 依赖与外部交互

### 测试依赖

1. **core_test_support**
   - `test_codex::test_codex()` - 创建测试实例
   - `responses::start_mock_server()` - 启动模拟服务器
   - `responses::mount_sse_once()` - 挂载 SSE 响应
   - `wait_for_event_match` - 等待特定事件

2. **codex_protocol**
   - `Op::UserTurn` - 用户回合操作
   - `Op::ListSkills` - 列出 Skill 操作
   - `UserInput::Skill` - Skill 输入项
   - `SkillScope` - Skill 作用域枚举

3. **serde_yaml** - YAML 解析

### 文件系统布局

测试创建的 Skill 目录结构：
```
<CODEX_HOME>/
  skills/
    <user-skill-name>/
      SKILL.md              # 用户 Skill 定义
    .system/
      <system-skill-name>/
        SKILL.md            # 系统 Skill 定义
```

### 协议事件

测试涉及的事件：
- `EventMsg::TurnComplete` - 回合完成
- `EventMsg::ListSkillsResponse` - Skill 列表响应

### 系统 Skill 嵌入

系统 Skill 在编译时嵌入，通过 `include_str!` 加载：
```rust
// skills/system.rs
const SYSTEM_SKILLS: &[(&str, &str)] = &[
    ("skill-creator", include_str!("../../../skills/skill-creator/SKILL.md")),
    // ...
];
```

## 风险、边界与改进建议

### 当前风险

1. **平台限制** - 测试标记为 `#!cfg(not(target_os = "windows"))`，Windows 平台覆盖不足
2. **网络依赖** - 使用 `skip_if_no_network!`，无网络时测试被跳过
3. **硬编码 Skill 名称** - 测试依赖特定的系统 Skill 名称

### 边界情况

1. **同名 Skill** - 用户 Skill 与系统 Skill 同名时的优先级
2. **循环依赖** - Skill A 引用 Skill B，Skill B 引用 Skill A
3. **大 Skill 文件** - 非常大的 SKILL.md 文件的加载性能
4. **特殊字符** - Skill 名称和内容中的特殊字符处理

### 改进建议

1. **增加 Windows 支持** - 为 Windows 平台添加等效测试
2. **增加同名 Skill 测试** - 验证用户 Skill 覆盖系统 Skill 的行为
3. **增加性能测试** - 测试大量 Skill 的加载性能
4. **增加并发测试** - 验证多线程环境下的 Skill 加载
5. **增加 Skill 更新测试** - 验证运行时 Skill 文件变更的检测

### 相关配置项

```rust
// Skill 加载配置
config.skills.enabled = true;
config.skills.auto_reload = true;
```

### Skill 注入格式

注入到模型输入的 Skill 格式：
```xml
<skill>
<name>{skill_name}</name>
<path>{skill_path}</path>
{skill_body}
</skill>
```

### 错误处理

Skill 加载错误包含：
- `path` - 错误发生的文件路径
- `message` - 错误描述

错误类型包括：
- YAML 解析错误
- 文件读取错误
- 验证错误（如缺少必需字段）
