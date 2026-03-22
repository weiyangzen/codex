# loader.rs 研究文档

## 场景与职责

`loader.rs` 是 Codex 技能系统的**核心加载模块**，负责从文件系统发现和加载技能定义。该模块实现了完整的技能生命周期管理，从文件扫描到元数据解析，再到权限配置处理。

**核心职责：**

1. **技能根目录发现**：根据配置层栈确定技能搜索根目录
2. **文件系统扫描**：递归扫描技能目录，发现 SKILL.md 文件
3. **YAML 前置元数据解析**：解析 SKILL.md 文件的 YAML frontmatter
4. **元数据文件加载**：加载 `agents/openai.yaml` 扩展配置
5. **权限配置处理**：解析网络、文件系统、macOS 沙箱权限
6. **作用域管理**：区分 User/Repo/System/Admin 不同作用域的技能
7. **去重和排序**：处理多来源技能的冲突和优先级

该模块是技能系统的数据入口，决定了哪些技能可用以及它们的配置。

## 功能点目的

### 1. 配置结构定义

#### `SkillFrontmatter` / `SkillFrontmatterMetadata`
```rust
#[derive(Debug, Deserialize)]
struct SkillFrontmatter {
    name: Option<String>,
    description: Option<String>,
    metadata: SkillFrontmatterMetadata,
}
```
解析 SKILL.md 文件的 YAML 前置元数据：
```yaml
---
name: my-skill
description: A useful skill
metadata:
  short-description: Short desc
---
```

#### `SkillMetadataFile`
```rust
#[derive(Debug, Default, Deserialize)]
struct SkillMetadataFile {
    interface: Option<Interface>,
    dependencies: Option<Dependencies>,
    policy: Option<Policy>,
    permissions: Option<SkillPermissionProfile>,
}
```
定义 `agents/openai.yaml` 的结构，包含界面、依赖、策略和权限配置。

### 2. `load_skills_from_roots` - 主加载入口
```rust
pub(crate) fn load_skills_from_roots<I>(roots: I) -> SkillLoadOutcome
where
    I: IntoIterator<Item = SkillRoot>,
```

**执行流程：**
1. 遍历所有技能根目录
2. 对每个根目录调用 `discover_skills_under_root`
3. 路径去重：保留第一个出现的技能（按根目录顺序）
4. 排序：按作用域优先级（Repo > User > System > Admin）+ 名称 + 路径

**作用域优先级：**
```rust
fn scope_rank(scope: SkillScope) -> u8 {
    match scope {
        SkillScope::Repo => 0,    // 最高优先级
        SkillScope::User => 1,
        SkillScope::System => 2,
        SkillScope::Admin => 3,   // 最低优先级
    }
}
```

### 3. `skill_roots` - 根目录发现
根据配置层栈确定技能搜索路径：

**Project 层：**
- `{config_folder}/skills` → Repo 作用域

**User 层：**
- `{config_folder}/skills` → User 作用域（向后兼容）
- `$HOME/.agents/skills` → User 作用域（推荐位置）
- `{config_folder}/skills/.system` → System 作用域

**System 层：**
- `{config_folder}/skills` → Admin 作用域

**Repo 层（额外）：**
- 从 CWD 向上到项目根目录，每个目录的 `.agents/skills` → Repo 作用域

### 4. `discover_skills_under_root` - 目录扫描
**扫描策略：**
- BFS（广度优先）遍历，限制最大深度（`MAX_SCAN_DEPTH = 6`）
- 目录数量限制（`MAX_SKILLS_DIRS_PER_ROOT = 2000`）
- 符号链接处理：User/Repo/Admin 跟随，System 不跟随
- 隐藏文件/目录跳过（以 `.` 开头）

**文件识别：**
- 查找名为 `SKILL.md` 的文件
- 调用 `parse_skill_file` 解析

### 5. `parse_skill_file` - 文件解析
**解析流程：**
1. 读取文件内容
2. 提取 YAML frontmatter（`---` 包围的内容）
3. 解析 frontmatter 为 `SkillFrontmatter`
4. 生成默认技能名（从父目录名）
5. 添加命名空间前缀（如果是插件提供的技能）
6. 加载 `agents/openai.yaml` 扩展元数据
7. 验证字段长度限制
8. 规范化路径

**字段长度限制：**
```rust
const MAX_NAME_LEN: usize = 64;
const MAX_DESCRIPTION_LEN: usize = 1024;
const MAX_SHORT_DESCRIPTION_LEN: usize = 1024;
// ... 其他限制
```

### 6. `load_skill_metadata` - 扩展元数据加载
加载 `agents/openai.yaml` 文件：
- 使用 `AbsolutePathBufGuard` 确保路径安全
- 解析 YAML 为 `SkillMetadataFile`
- 转换和验证各个字段

### 7. 权限配置处理

#### `normalize_permissions`
将技能权限配置转换为内部 `PermissionProfile`：
- **网络权限**：`enabled`, `allowed_domains`, `denied_domains`
- **文件系统权限**：`read`, `write` 路径列表
- **macOS 权限**：沙箱扩展配置

#### `SkillManagedNetworkOverride`
提取域名级别的网络覆盖配置，用于精细控制技能的网络访问。

### 8. 资源路径解析

#### `resolve_asset_path`
验证和解析界面资源路径（图标等）：
- 必须是相对路径
- 必须在 `assets/` 目录下
- 不允许 `..` 路径遍历

示例：
- ✅ `assets/icon.png`
- ❌ `/absolute/path.png`
- ❌ `../secret.png`
- ❌ `other/icon.png`（不在 assets 下）

## 具体技术实现

### YAML Frontmatter 提取
```rust
fn extract_frontmatter(contents: &str) -> Option<String> {
    let mut lines = contents.lines();
    // 检查开头的 ---
    if !matches!(lines.next(), Some(line) if line.trim() == "---") {
        return None;
    }
    // 收集到下一个 ---
    let mut frontmatter_lines = Vec::new();
    for line in lines.by_ref() {
        if line.trim() == "---" {
            return Some(frontmatter_lines.join("\n"));
        }
        frontmatter_lines.push(line);
    }
    None // 未找到闭合 ---
}
```

### 技能名称生成
```rust
fn default_skill_name(path: &Path) -> String {
    path.parent()
        .and_then(Path::file_name)
        .and_then(|name| name.to_str())
        .map(sanitize_single_line)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "skill".to_string())
}
```
从 SKILL.md 的父目录名生成默认技能名。

### 命名空间处理
```rust
fn namespaced_skill_name(path: &Path, base_name: &str) -> String {
    plugin_namespace_for_skill_path(path)
        .map(|namespace| format!("{namespace}:{base_name}"))
        .unwrap_or_else(|| base_name.to_string())
}
```
插件提供的技能自动添加命名空间前缀，避免命名冲突。

### 单行道清理
```rust
fn sanitize_single_line(raw: &str) -> String {
    raw.split_whitespace().collect::<Vec<_>>().join(" ")
}
```
将多行文本合并为单行，去除多余空白。

## 关键代码路径与文件引用

### 本文件关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `load_skills_from_roots` | 184-216 | 主入口，加载所有技能 |
| `skill_roots` | 218-229 | 确定技能根目录 |
| `discover_skills_under_root` | 388-525 | 扫描目录发现技能 |
| `parse_skill_file` | 527-585 | 解析单个 SKILL.md |
| `load_skill_metadata` | 602-655 | 加载扩展元数据 |
| `normalize_permissions` | 657-691 | 处理权限配置 |
| `resolve_asset_path` | 783-829 | 验证资源路径 |

### 调用路径
```
codex-rs/core/src/skills/manager.rs:73
    └── load_skills_from_roots(roots)

codex-rs/core/src/plugins/manager.rs:1016
    └── load_skills_from_roots(skill_roots)
```

### 数据结构依赖
| 类型 | 定义位置 | 用途 |
|------|----------|------|
| `SkillMetadata` | model.rs | 技能元数据输出 |
| `SkillLoadOutcome` | model.rs | 加载结果聚合 |
| `SkillInterface` | model.rs | 界面配置 |
| `SkillDependencies` | model.rs | 依赖配置 |
| `SkillPolicy` | model.rs | 策略配置 |
| `PermissionProfile` | codex_protocol | 权限配置 |

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `crate::config_loader::*` | 配置层栈处理 |
| `crate::plugins::plugin_namespace_for_skill_path` | 插件命名空间 |
| `crate::skills::model::*` | 技能数据模型 |
| `crate::skills::system::system_cache_root_dir` | 系统技能缓存 |
| `codex_utils_absolute_path::AbsolutePathBufGuard` | 路径安全 |

### 外部 crate
| crate | 用途 |
|-------|------|
| `serde_yaml` | YAML 解析 |
| `toml` | TOML 配置解析 |
| `dunce::canonicalize` | 跨平台路径规范化 |
| `dirs::home_dir` | 获取用户主目录 |
| `tracing::error` | 错误日志 |

## 风险、边界与改进建议

### 已知风险

1. **YAML 解析安全风险**
   - 使用 `serde_yaml` 解析用户提供的 YAML
   - 存在 YAML 炸弹（Billion Laughs）攻击风险
   - 风险：恶意技能文件可能导致内存耗尽

2. **路径遍历风险**
   - 虽然 `resolve_asset_path` 有防护，但其他路径处理可能存在问题
   - 符号链接可能指向系统敏感目录

3. **扫描性能问题**
   - 大量技能目录（接近 2000 限制）可能导致启动延迟
   - 网络文件系统上的扫描性能更差

4. **编码问题**
   - 假设 SKILL.md 使用 UTF-8 编码
   - 其他编码可能导致解析失败或乱码

### 边界情况

1. **空 Frontmatter**
   - `---\n---` 被视为有效 frontmatter，但内容为空
   - 后续使用默认值

2. **重复技能名**
   - 同名技能按根目录顺序去重
   - 用户可能困惑为什么某些技能未加载

3. **最大深度限制**
   - 深度超过 6 层的技能不会被发现
   - 需要文档说明技能目录结构

4. **系统技能错误**
   - 系统技能解析错误被静默忽略
   - 可能导致系统功能缺失而用户不知情

### 改进建议

1. **YAML 安全加固**
   ```rust
   // 建议：限制别名扩展数量
   let yaml = serde_yaml::with_limit(MAX_ALIAS_EXPANSIONS).from_str(...)?;
   ```

2. **异步加载**
   ```rust
   // 建议：使用异步 I/O 避免阻塞
   pub(crate) async fn load_skills_from_roots(...) -> SkillLoadOutcome
   ```

3. **增量加载**
   - 缓存技能目录的修改时间
   - 仅重新加载变更的技能

4. **更好的错误报告**
   - 系统技能错误不应被完全静默
   - 至少记录 warn 级别日志

5. **配置化限制**
   - 允许用户配置 `MAX_SCAN_DEPTH` 和 `MAX_SKILLS_DIRS_PER_ROOT`
   - 适应不同规模的项目

6. **验证增强**
   ```rust
   // 建议：添加技能名称唯一性验证
   fn validate_no_duplicate_names(skills: &[SkillMetadata]) -> Result<(), Vec<SkillError>>
   ```

7. **测试覆盖**
   - 添加更多边界情况测试（见 `loader_tests.rs`）
   - 添加模糊测试，随机生成 YAML 验证鲁棒性
