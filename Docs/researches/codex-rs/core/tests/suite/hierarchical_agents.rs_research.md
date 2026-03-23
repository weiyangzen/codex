# hierarchical_agents.rs 深度研究文档

## 场景与职责

`hierarchical_agents.rs` 是 Codex 核心测试套件中验证**分层代理文档（Hierarchical Agents Documentation）**功能的集成测试文件。该功能允许项目通过嵌套的 `AGENTS.md` 文件提供分层级的 AI 指令。

核心验证点：
1. **AGENTS.md 内容注入**：验证文件内容被正确附加到用户指令
2. **层级消息追加**：验证分层代理消息在基础指令之后追加
3. **无项目文档场景**：验证即使没有 AGENTS.md 文件也能正常工作

## 功能点目的

### 1. 分层代理文档
- **目的**：支持大型项目中多层级、模块化的 AI 指令
- **机制**：从项目根目录到当前工作目录，收集所有 `AGENTS.md` 文件
- **应用场景**：
  - 项目级通用规范（根目录 AGENTS.md）
  - 模块级特殊规则（子目录 AGENTS.md）

### 2. 指令追加顺序
- **目的**：确保层级消息在基础指令之后
- **验证点**：`HIERARCHICAL_AGENTS_MESSAGE` 出现在 `be nice` 之后

### 3. 功能开关控制
- **目的**：通过特性标志控制功能启用
- **特性**：`Feature::ChildAgentsMd`

## 具体技术实现

### 特性定义

```rust
// codex-rs/core/src/features.rs
FeatureSpec {
    id: Feature::ChildAgentsMd,
    key: "child_agents_md",
    stage: Stage::UnderDevelopment,
    default_enabled: false,
}
```

### 项目文档发现

```rust
// codex-rs/core/src/project_doc.rs
pub const DEFAULT_PROJECT_DOC_FILENAME: &str = "AGENTS.md";
pub const LOCAL_PROJECT_DOC_FILENAME: &str = "AGENTS.override.md";

pub(crate) const HIERARCHICAL_AGENTS_MESSAGE: &str =
    include_str!("../hierarchical_agents_message.md");

pub(crate) async fn get_user_instructions(config: &Config) -> Option<String> {
    let project_docs = read_project_docs(config).await;
    
    let mut output = String::new();
    
    // 1. 添加用户自定义指令
    if let Some(instructions) = config.user_instructions.clone() {
        output.push_str(&instructions);
    }
    
    // 2. 添加项目文档（AGENTS.md）
    match project_docs {
        Ok(Some(docs)) => {
            if !output.is_empty() {
                output.push_str(PROJECT_DOC_SEPARATOR);
            }
            output.push_str(&docs);
        }
        ...
    };
    
    // 3. 添加 JS REPL 指令（如果启用）
    if let Some(js_repl_section) = render_js_repl_instructions(config) {
        ...
    }
    
    // 4. 添加分层代理消息（如果启用）
    if config.features.enabled(Feature::ChildAgentsMd) {
        if !output.is_empty() {
            output.push_str("\n\n");
        }
        output.push_str(HIERARCHICAL_AGENTS_MESSAGE);
    }
    
    if !output.is_empty() { Some(output) } else { None }
}
```

### 文档发现流程

```rust
pub async fn read_project_docs(config: &Config) -> std::io::Result<Option<String>> {
    let max_total = config.project_doc_max_bytes;
    if max_total == 0 {
        return Ok(None);
    }
    
    // 1. 发现文档路径
    let paths = discover_project_doc_paths(config)?;
    if paths.is_empty() {
        return Ok(None);
    }
    
    // 2. 读取并合并文档
    let mut remaining: u64 = max_total as u64;
    let mut parts: Vec<String> = Vec::new();
    
    for p in paths {
        if remaining == 0 { break; }
        
        let file = match tokio::fs::File::open(&p).await {
            Ok(f) => f,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
            Err(e) => return Err(e),
        };
        
        // 读取并截断（如果超过预算）
        let size = file.metadata().await?.len();
        let mut reader = tokio::io::BufReader::new(file).take(remaining);
        let mut data: Vec<u8> = Vec::new();
        reader.read_to_end(&mut data).await?;
        
        if size > remaining {
            tracing::warn!("Project doc `{}` exceeds remaining budget...", p.display());
        }
        
        let text = String::from_utf8_lossy(&data).to_string();
        if !text.trim().is_empty() {
            parts.push(text);
            remaining = remaining.saturating_sub(data.len() as u64);
        }
    }
    
    if parts.is_empty() { Ok(None) } else { Ok(Some(parts.join("\n\n"))) }
}
```

### 路径发现算法

```rust
pub fn discover_project_doc_paths(config: &Config) -> std::io::Result<Vec<PathBuf>> {
    let mut dir = config.cwd.clone();
    if let Ok(canon) = normalize_path(&dir) {
        dir = canon;
    }
    
    // 1. 确定项目根目录
    let project_root_markers = ...;  // 默认 [".git"]
    let mut project_root = None;
    if !project_root_markers.is_empty() {
        for ancestor in dir.ancestors() {
            for marker in &project_root_markers {
                if ancestor.join(marker).exists() {
                    project_root = Some(ancestor.to_path_buf());
                    break;
                }
            }
            if project_root.is_some() { break; }
        }
    }
    
    // 2. 收集搜索目录（从根到当前目录）
    let search_dirs: Vec<PathBuf> = if let Some(root) = project_root {
        let mut dirs = Vec::new();
        let mut cursor = dir.as_path();
        loop {
            dirs.push(cursor.to_path_buf());
            if cursor == root { break; }
            let Some(parent) = cursor.parent() else { break; };
            cursor = parent;
        }
        dirs.reverse();  // 根目录在前
        dirs
    } else {
        vec![dir]
    };
    
    // 3. 在每个目录中查找 AGENTS.md
    let mut found: Vec<PathBuf> = Vec::new();
    let candidate_filenames = candidate_filenames(config);
    for d in search_dirs {
        for name in &candidate_filenames {
            let candidate = d.join(name);
            match std::fs::symlink_metadata(&candidate) {
                Ok(md) if md.file_type().is_file() || md.file_type().is_symlink() => {
                    found.push(candidate);
                    break;
                }
                _ => continue,
            }
        }
    }
    
    Ok(found)
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/hierarchical_agents.rs` - 本测试文件

### 核心实现
- `codex-rs/core/src/project_doc.rs` - 项目文档处理
  - `get_user_instructions` - 获取完整用户指令
  - `read_project_docs` - 读取项目文档
  - `discover_project_doc_paths` - 发现文档路径

- `codex-rs/core/src/features.rs` - 特性标志
  - `Feature::ChildAgentsMd` - 分层代理特性

- `codex-rs/core/hierarchical_agents_message.md` - 分层代理消息模板

### 配置相关
- `codex-rs/core/src/config.rs` - 配置定义
  - `user_instructions` - 用户自定义指令
  - `project_doc_max_bytes` - 文档大小限制
  - `project_doc_fallback_filenames` - 备选文件名

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `codex_core::project_doc` | 项目文档发现和处理 |
| `codex_core::features` | 特性标志检查 |
| `codex_core::config` | 配置读取 |
| `core_test_support` | 测试基础设施 |

### 测试验证
```rust
const HIERARCHICAL_AGENTS_SNIPPET: &str =
    "Files called AGENTS.md commonly appear in many places inside a container";

// 验证 AGENTS.md 内容被注入
let instructions = user_messages
    .iter()
    .find(|text| text.starts_with("# AGENTS.md instructions for "))
    .expect("instructions message");
assert!(instructions.contains("be nice"), "expected AGENTS.md text included");

// 验证层级消息在基础指令之后
let snippet_pos = instructions.find(HIERARCHICAL_AGENTS_SNIPPET).expect("...");
let base_pos = instructions.find("be nice").expect("...");
assert!(snippet_pos > base_pos, "expected hierarchical agents message appended after base");
```

### 测试配置
```rust
let mut builder = test_codex().with_config(|config| {
    config
        .features
        .enable(Feature::ChildAgentsMd)
        .expect("test config should allow feature update");
    std::fs::write(config.cwd.join("AGENTS.md"), "be nice").expect("write AGENTS.md");
});
```

## 风险、边界与改进建议

### 已知风险

1. **文档大小限制**
   - 默认限制：`project_doc_max_bytes`
   - 风险：大文档被截断可能导致指令不完整

2. **编码问题**
   - 处理：`String::from_utf8_lossy` 转换
   - 风险：非 UTF-8 内容可能丢失

3. **循环链接**
   - 现状：允许符号链接，但不检测循环
   - 风险：循环链接可能导致无限循环

### 边界情况

1. **空 AGENTS.md**
   - 处理：`text.trim().is_empty()` 检查
   - 行为：跳过空文档

2. **无项目根标记**
   - 处理：只搜索当前目录
   - 行为：`vec![dir]`

3. **多个候选文件名**
   - 优先级：`AGENTS.override.md` > `AGENTS.md` > 备选
   - 每目录只取第一个匹配的

4. **特性未启用**
   - 行为：`HIERARCHICAL_AGENTS_MESSAGE` 不追加
   - 但 `AGENTS.md` 内容仍注入（如果存在）

### 改进建议

1. **循环检测**
   - 添加符号链接循环检测
   - 限制最大遍历深度

2. **编码支持**
   - 支持更多编码（GBK、Latin-1 等）
   - 添加编码自动检测

3. **性能优化**
   - 缓存文档发现结果
   - 监听文件变化自动刷新

4. **功能增强**
   - 支持 YAML front matter 元数据
   - 支持条件指令（基于文件类型等）
   - 支持指令继承和覆盖规则

5. **测试覆盖**
   - 添加多层级 AGENTS.md 测试
   - 添加大文档性能测试
   - 添加符号链接测试

6. **文档完善**
   - 提供 AGENTS.md 编写指南
   - 添加示例和最佳实践
