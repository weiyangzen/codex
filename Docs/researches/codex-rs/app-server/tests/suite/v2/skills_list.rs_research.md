# skills_list.rs 研究文档

## 场景与职责

本文件是 Codex App Server v2 API 的集成测试套件的一部分，专门测试**技能列表功能** (`skills/list`)。技能 (Skills) 是可复用的 AI 辅助功能模块，通过 Markdown 文件定义，可以被 Codex 加载和执行。

测试场景覆盖：
1. **额外用户根目录** - 从配置的额外目录加载技能
2. **路径验证** - 拒绝相对路径，要求绝对路径
3. **缓存机制** - 验证 `force_reload` 参数的缓存控制行为
4. **文件监视** - 验证技能文件变更时发出 `skills/changed` 通知

## 功能点目的

### 1. 技能发现机制
技能系统允许用户和组织定义可复用的 AI 辅助工作流：
- **默认扫描**: 扫描标准位置（如 `~/.codex/skills/`）
- **额外根目录**: 通过 `per_cwd_extra_user_roots` 配置额外扫描路径
- **按 CWD 配置**: 不同工作目录可以有不同的额外技能源

### 2. 技能缓存
为提高性能，技能列表会被缓存：
- `force_reload: false` - 使用缓存结果
- `force_reload: true` - 强制重新扫描磁盘

### 3. 技能变更检测
文件系统监视器监控技能文件变更：
- 技能文件修改时发出 `skills/changed` 通知
- 客户端可以响应变更刷新技能列表

### 4. 技能文件格式
```markdown
---
name: skill-name
description: Skill description
---

# Body
Skill implementation details...
```

## 具体技术实现

### 关键流程

```
测试用例: skills_list_includes_skills_from_per_cwd_extra_user_roots
1. 创建临时 CODEX_HOME
2. 创建临时 CWD
3. 创建额外技能根目录，写入测试技能
4. 初始化 MCP 连接
5. 发送 skills/list 请求
   - cwds: [cwd]
   - per_cwd_extra_user_roots: [{cwd, extra_user_roots: [extra_root]}]
   - force_reload: true
6. 验证响应包含来自额外根目录的技能

测试用例: skills_list_rejects_relative_extra_user_roots
1-4. 同上
5. 发送 skills/list 请求，使用相对路径
6. 验证返回错误，提示路径必须是绝对路径

测试用例: skills_list_uses_cached_result_until_force_reload
1. 首次请求: force_reload=false, 无额外根目录
2. 二次请求: force_reload=false, 有额外根目录
   - 验证仍使用缓存（不包含新技能）
3. 三次请求: force_reload=true, 有额外根目录
   - 验证重新扫描，包含新技能

测试用例: skills_changed_notification_is_emitted_after_skill_change
1. 创建临时 CODEX_HOME
2. 写入初始技能文件
3. 初始化 MCP，启动线程
4. 修改技能文件内容
5. 等待 skills/changed 通知
6. 验证通知内容
```

### 核心数据结构

```rust
// 请求参数
SkillsListParams {
    cwds: Vec<PathBuf>,  // 工作目录列表
    force_reload: bool,  // 是否强制重新扫描
    per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>,
}

SkillsListExtraRootsForCwd {
    cwd: PathBuf,
    extra_user_roots: Vec<PathBuf>,  // 必须是绝对路径
}

// 响应结构
SkillsListResponse {
    data: Vec<SkillsListEntry>,
}

SkillsListEntry {
    cwd: PathBuf,
    skills: Vec<SkillMetadata>,
}

// 变更通知
SkillsChangedNotification {}
```

### 技能文件写入辅助

```rust
fn write_skill(root: &TempDir, name: &str) -> Result<()> {
    let skill_dir = root.path().join("skills").join(name);
    std::fs::create_dir_all(&skill_dir)?;
    let content = format!(
        "---\nname: {name}\ndescription: {name} description\n---\n\n# Body\n"
    );
    std::fs::write(skill_dir.join("SKILL.md"), content)?;
    Ok(())
}
```

### 缓存行为验证

```rust
// 1. 首次请求 - 缓存为空，扫描基础路径
let first_response = skills_list(cwds, force_reload=false, extra_roots=None).await?;
assert!(!first_data[0].skills.iter().any(|s| s.name == "late-extra-skill"));

// 2. 二次请求 - 使用缓存，忽略新的 extra_roots
let second_response = skills_list(cwds, force_reload=false, extra_roots=Some(...)).await?;
assert!(!second_data[0].skills.iter().any(|s| s.name == "late-extra-skill"));

// 3. 三次请求 - 强制重新扫描
let third_response = skills_list(cwds, force_reload=true, extra_roots=Some(...)).await?;
assert!(third_data[0].skills.iter().any(|s| s.name == "late-extra-skill"));
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/skills_list.rs` - 本测试文件

### 测试支持库
- `codex-rs/app-server/tests/common/mcp_process.rs`
  - `send_skills_list_request()` (行459)

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `SkillsList => "skills/list"` (行296)
  - `SkillsChanged => "skills/changed"` (通知)

- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `SkillsListParams` (行3065)
  - `SkillsListExtraRootsForCwd`
  - `SkillsListResponse`
  - `SkillsChangedNotification`
  - `SkillMetadata`

### 核心实现
- `codex-rs/core/src/skills/` - 技能系统核心实现
- `codex-rs/core/src/skills/discovery.rs` - 技能发现
- `codex-rs/core/src/skills/loader.rs` - 技能加载
- `codex-rs/core/src/skills/watcher.rs` - 文件监视

## 依赖与外部交互

### 直接依赖
| 依赖 | 用途 |
|-----|------|
| `tempfile::TempDir` | 创建隔离的临时目录 |
| `tokio::time::timeout` | 异步超时控制 |
| `std::fs` | 文件系统操作 |
| `pretty_assertions::assert_eq` | 断言增强 |

### 超时配置
```rust
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(10);
const WATCHER_TIMEOUT: Duration = Duration::from_secs(20);  // 文件监视需要更长时间
```

### 文件系统操作
```rust
// 写入技能文件
std::fs::write(
    &skill_path,
    "---\nname: demo\ndescription: updated\n---\n\n# Updated\n",
)?;
```

## 风险、边界与改进建议

### 当前风险

1. **文件系统依赖**
   - 测试依赖文件系统操作，可能受平台差异影响
   - Windows 路径处理可能有差异
   - 建议: 使用跨路径抽象库

2. **时序敏感**
   - 文件监视测试依赖文件系统事件时序
   - 在慢速/负载系统上可能超时
   - 建议: 增加重试机制或更长超时

3. **缓存失效策略简单**
   - 仅通过 `force_reload` 控制
   - 无自动过期机制
   - 建议: 添加更多缓存策略测试

### 边界情况

1. **循环引用**
   - 未测试技能之间的循环依赖
   - 建议: 添加循环依赖检测测试

2. **大技能文件**
   - 未测试大型技能文件的加载性能
   - 建议: 添加性能基准测试

3. **并发修改**
   - 未测试技能文件被并发修改的情况
   - 建议: 添加并发安全测试

4. **无效技能格式**
   - 未测试损坏/无效的技能文件处理
   - 建议: 添加错误处理测试

### 改进建议

1. **扩展测试覆盖**
   ```rust
   // 建议添加:
   - async fn skills_list_nested_directories()  // 嵌套目录扫描
   - async fn skills_list_duplicate_names()  // 重复名称处理
   - async fn skills_list_invalid_skill_file()  // 无效文件格式
   - async fn skills_list_performance_large_set()  // 大量技能性能
   - async fn skills_concurrent_reload()  // 并发重新加载
   ```

2. **跨平台测试**
   - 确保 Windows 路径处理正确
   - 测试符号链接处理

3. **安全测试**
   - 测试路径遍历攻击防护
   - 验证技能文件沙箱限制

4. **监控和指标**
   - 添加技能加载时间指标
   - 监控缓存命中率

### 相关测试文件
- `codex-rs/core/tests/suite/skills.rs` - 核心技能测试
- `codex-rs/app-server/tests/suite/v2/plugin_list.rs` - 类似功能的插件列表测试
