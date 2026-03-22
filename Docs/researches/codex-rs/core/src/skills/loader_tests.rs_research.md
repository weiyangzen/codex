# loader_tests.rs 深度研究文档

## 场景与职责

`loader_tests.rs` 是 Codex 核心技能系统的测试文件，负责对 `loader.rs` 中的技能加载逻辑进行全面的单元测试和集成测试。该测试文件包含约 2000 行代码，覆盖了技能发现、解析、加载、权限处理、作用域管理等多个维度的功能验证。

### 核心测试职责

1. **技能根目录解析测试**：验证从不同配置层（System/User/Project）正确推导技能根目录
2. **技能文件加载测试**：验证 SKILL.md 文件的解析、frontmatter 提取、元数据读取
3. **作用域隔离测试**：验证 Repo/User/System/Admin 四个作用域的正确行为
4. **权限配置测试**：验证网络、文件系统、macOS 权限的解析和验证
5. **依赖管理测试**：验证技能依赖（env_var/mcp/cli）的解析
6. **UI 接口测试**：验证技能界面配置（图标、颜色、描述等）的解析
7. **边界情况测试**：验证符号链接、深度限制、重复名称、缓存等边界场景

---

## 功能点目的

### 1. 技能根目录解析 (`skill_roots_from_layer_stack`)

**目的**：确保从不同配置层正确识别技能存储位置。

**测试覆盖**：
- User 层映射到用户目录和系统缓存
- System 层映射到管理员技能目录
- Project 层映射到仓库技能目录（即使被禁用也包含）
- 从 `$HOME/.agents/skills` 加载用户技能

### 2. 技能元数据解析

**目的**：验证 SKILL.md 文件的 frontmatter 和元数据文件解析。

**测试覆盖**：
- 基础 frontmatter（name/description）解析
- `metadata.short-description` 字段解析
- 目录名作为技能名回退
- 长度限制验证（name: 64, description: 1024）

### 3. 权限配置解析

**目的**：验证技能权限配置的 YAML/JSON 解析。

**测试覆盖**：
- 网络权限（enabled, allowed_domains, denied_domains）
- 文件系统权限（read/write 路径）
- macOS 权限（preferences, automation, launch_services, accessibility, calendar, reminders, contacts）
- 权限归一化（分离 managed_network_override 和 permission_profile）

### 4. 依赖管理

**目的**：验证技能依赖工具的解析。

**测试覆盖**：
- env_var 类型依赖（如 GITHUB_TOKEN）
- mcp 类型依赖（streamable_http/stdio 传输）
- cli 类型依赖（如 gh 命令）

### 5. UI 接口配置

**目的**：验证技能界面元数据解析。

**测试覆盖**：
- display_name, short_description
- icon_small, icon_large（路径解析和验证）
- brand_color（#RRGGBB 格式验证）
- default_prompt（长度限制）

### 6. 策略配置

**目的**：验证技能策略配置。

**测试覆盖**：
- allow_implicit_invocation 开关
- products 列表（codex/chatgpt/atlas）

### 7. 边界场景

**目的**：验证异常和边界情况处理。

**测试覆盖**：
- 符号链接处理（目录链接跟随、文件链接忽略、循环检测）
- 扫描深度限制（MAX_SCAN_DEPTH = 6）
- 重复技能名处理（同作用域去重、跨作用域保留）
- 隐藏目录忽略（以 `.` 开头的目录）
- 无效 frontmatter 处理

---

## 具体技术实现

### 测试基础设施

```rust
// 测试配置构建
async fn make_config(codex_home: &TempDir) -> Config {
    // 创建临时配置，设置信任级别为 Trusted
}

// 技能加载辅助函数
fn load_skills_for_test(config: &Config) -> SkillLoadOutcome {
    // 使用空的 home_dir 避免扫描真实 $HOME/.agents/skills
}

// 技能文件创建辅助函数
fn write_skill(codex_home: &TempDir, dir: &str, name: &str, description: &str) -> PathBuf {
    // 创建 SKILL.md 文件，包含 frontmatter
}

fn write_skill_metadata_at(skill_dir: &Path, contents: &str) -> PathBuf {
    // 创建 agents/openai.yaml 元数据文件
}
```

### 关键测试模式

#### 1. 配置层堆栈构建

```rust
let layers = vec![
    ConfigLayerEntry::new(
        ConfigLayerSource::User { file: user_file },
        TomlValue::Table(toml::map::Map::new()),
    ),
];
let stack = ConfigLayerStack::new(layers, ...)?;
```

#### 2. 结果断言模式

```rust
assert!(outcome.errors.is_empty(), "unexpected errors: {:?}", outcome.errors);
assert_eq!(outcome.skills, vec![SkillMetadata { ... }]);
```

#### 3. 路径规范化

```rust
fn normalized(path: &Path) -> PathBuf {
    canonicalize_path(path).unwrap_or_else(|_| path.to_path_buf())
}
```

### 关键常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `MAX_NAME_LEN` | 64 | 技能名最大长度 |
| `MAX_DESCRIPTION_LEN` | 1024 | 描述最大长度 |
| `MAX_SCAN_DEPTH` | 6 | 技能扫描最大深度 |
| `MAX_SKILLS_DIRS_PER_ROOT` | 2000 | 每个根目录最大扫描目录数 |
| `SKILLS_FILENAME` | "SKILL.md" | 技能文件名 |
| `SKILLS_METADATA_FILENAME` | "openai.yaml" | 元数据文件名 |
| `SKILLS_METADATA_DIR` | "agents" | 元数据目录名 |

---

## 关键代码路径与文件引用

### 被测试的主要函数

| 函数 | 所在文件 | 职责 |
|------|----------|------|
| `skill_roots_from_layer_stack` | loader.rs:917 | 从配置层推导技能根目录 |
| `load_skills_from_roots` | loader.rs:184 | 从多个根目录加载技能 |
| `discover_skills_under_root` | loader.rs:388 | 在单个根目录下发现技能 |
| `parse_skill_file` | loader.rs:527 | 解析单个 SKILL.md 文件 |
| `load_skill_metadata` | loader.rs:602 | 加载技能元数据文件 |
| `normalize_permissions` | loader.rs:657 | 归一化权限配置 |
| `resolve_interface` | loader.rs:693 | 解析界面配置 |
| `resolve_dependencies` | loader.rs:724 | 解析依赖配置 |

### 测试文件结构

```
loader_tests.rs
├── 辅助函数
│   ├── make_config / make_config_for_cwd
│   ├── load_skills_for_test
│   ├── mark_as_git_repo
│   ├── normalized
│   └── write_skill / write_raw_skill_at / write_skill_metadata_at
├── 根目录解析测试
│   ├── skill_roots_from_layer_stack_maps_user_to_user_and_system_cache_and_system_to_admin
│   └── skill_roots_from_layer_stack_includes_disabled_project_layers
├── 技能加载测试
│   ├── loads_skills_from_home_agents_dir_for_user_scope
│   ├── loads_valid_skill
│   ├── loads_skills_from_repo_root
│   └── loads_skills_from_system_cache_when_present
├── 元数据解析测试
│   ├── loads_skill_dependencies_metadata_from_yaml
│   ├── loads_skill_interface_metadata_from_yaml
│   ├── loads_skill_policy_from_yaml
│   └── loads_skill_permissions_from_yaml
├── 边界场景测试
│   ├── respects_max_scan_depth_for_user_scope
│   ├── deduplicates_by_path_preferring_first_root
│   ├── keeps_duplicate_names_from_repo_and_user
│   └── loads_skills_via_symlinked_subdir_for_user_scope
└── 错误处理测试
    ├── skips_hidden_and_invalid
    ├── enforces_length_limits
    └── ignores_invalid_brand_color
```

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::config::*` | 配置构建和覆盖 |
| `crate::config_loader::*` | 配置层加载和堆栈管理 |
| `crate::skills::loader::*` | 被测试的技能加载逻辑 |
| `crate::skills::model::*` | 技能元数据模型 |
| `codex_protocol::protocol::SkillScope` | 技能作用域枚举 |
| `codex_protocol::models::*` | 权限模型 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tempfile::TempDir` | 创建临时目录用于测试 |
| `pretty_assertions::assert_eq` | 更好的测试失败输出 |
| `serde_yaml` | YAML 解析验证 |
| `toml` | TOML 配置构建 |

### 文件系统交互

测试通过 `tempfile` 创建隔离的临时文件系统环境：
- 模拟 `$CODEX_HOME/skills` 目录结构
- 模拟 `.codex/skills` 项目级技能目录
- 模拟 `.agents/skills` 传统用户技能目录
- 模拟 `.git` 标记以触发仓库根检测

---

## 风险、边界与改进建议

### 当前风险

1. **平台特定测试**：
   - 符号链接测试使用 `#[cfg(unix)]`，Windows 覆盖不足
   - macOS 权限测试在非 macOS 平台行为可能不同

2. **测试执行顺序依赖**：
   - 部分测试依赖文件系统状态，虽然使用临时目录，但并行执行可能有竞争

3. **硬编码常量**：
   - 测试中的常量（如 `MAX_SCAN_DEPTH = 6`）与实现耦合，修改需要同步更新测试

### 边界情况

1. **符号链接安全**：
   - System 作用域忽略符号链接（安全考虑）
   - 循环符号链接检测通过 `visited_dirs` HashSet 实现

2. **路径遍历防护**：
   - 图标路径验证阻止 `..` 和绝对路径
   - 技能扫描限制在 `MAX_SCAN_DEPTH` 深度内

3. **重复处理**：
   - 同一路径的技能按作用域优先级去重
   - 同名但不同路径的技能保留（通过路径区分）

### 改进建议

1. **测试覆盖率**：
   - 增加 Windows 平台的符号链接测试（使用 `std::os::windows::fs`）
   - 增加更多并发场景测试（多线程技能加载）

2. **性能测试**：
   - 添加大目录树（接近 `MAX_SKILLS_DIRS_PER_ROOT`）的性能基准测试
   - 测试缓存命中/未命中的性能差异

3. **错误场景**：
   - 增加更多损坏文件格式的测试用例
   - 测试磁盘满/权限拒绝等 IO 错误处理

4. **测试可维护性**：
   - 将重复的 `SkillMetadata` 结构体比较提取为辅助宏
   - 使用 insta snapshot 测试替代大量手工构造的期望结构

5. **文档**：
   - 为复杂测试用例添加更多注释说明测试意图
   - 建立测试数据工厂模式，减少样板代码
