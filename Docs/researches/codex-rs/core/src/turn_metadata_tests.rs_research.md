# turn_metadata_tests.rs 研究文档

## 场景与职责

`turn_metadata_tests.rs` 是 `turn_metadata.rs` 的配套测试模块，负责验证回合元数据功能的正确性。测试覆盖：

1. **Git 元数据收集**：验证在真实 Git 仓库中能正确获取提交状态和更改状态
2. **沙盒标签生成**：验证 `TurnMetadataState` 正确集成沙盒标签

## 功能点目的

### 测试用例设计意图

| 测试函数 | 目的 |
|----------|------|
| `build_turn_metadata_header_includes_has_changes_for_clean_repo` | 验证干净仓库（无未提交更改）的元数据正确性 |
| `turn_metadata_state_uses_platform_sandbox_tag` | 验证沙盒标签与平台策略的集成 |

## 具体技术实现

### 测试 1：干净仓库元数据

```rust
#[tokio::test]
async fn build_turn_metadata_header_includes_has_changes_for_clean_repo()
```

**测试流程**：
1. 创建临时目录
2. 初始化 Git 仓库（`git init`）
3. 配置 Git 用户信息
4. 创建文件并提交（`git add . && git commit -m "initial"`）
5. 调用 `build_turn_metadata_header`
6. 解析返回的 JSON
7. 验证 `has_changes` 为 `false`

**关键技术点**：
- 使用 `tempfile::TempDir` 创建隔离的测试环境
- 使用 `tokio::process::Command` 异步执行 Git 命令
- 使用 `serde_json::Value` 动态解析 JSON 结果

### 测试 2：沙盒标签集成

```rust
#[test]
fn turn_metadata_state_uses_platform_sandbox_tag()
```

**测试流程**：
1. 创建临时目录作为工作目录
2. 构造 `SandboxPolicy::new_read_only_policy()`
3. 创建 `TurnMetadataState` 实例
4. 获取头信息并解析 JSON
5. 验证 `sandbox` 字段与 `sandbox_tag` 函数输出一致

**关键技术点**：
- 非异步测试（`#[test]` 而非 `#[tokio::test]`）
- 使用 `WindowsSandboxLevel::Disabled` 确保跨平台一致性
- 验证与 `sandbox_tags.rs` 的集成

## 关键代码路径与文件引用

### 被测试代码

| 被测试项 | 定义位置 |
|----------|----------|
| `build_turn_metadata_header` | `turn_metadata.rs:90` |
| `TurnMetadataState::new` | `turn_metadata.rs:130` |
| `TurnMetadataState::current_header_value` | `turn_metadata.rs:158` |
| `sandbox_tag` | `sandbox_tags.rs:6` |

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `tokio::process::Command` | 异步执行 Git 命令 |
| `serde_json::Value` | JSON 解析验证 |
| `SandboxPolicy` | 构造沙盒策略 |
| `WindowsSandboxLevel` | 指定 Windows 沙盒级别 |

## 依赖与外部交互

### 外部命令依赖

测试依赖系统安装的 `git` 命令：
- `git init`
- `git config`
- `git add`
- `git commit`

### 环境要求

1. **Git 必须安装**：测试会跳过或失败如果 Git 不可用
2. **文件系统权限**：需要创建临时目录和文件
3. **异步运行时**：使用 Tokio 运行时

## 风险、边界与改进建议

### 当前测试覆盖的不足

1. **缺少脏仓库测试**
   - 当前只测试了干净仓库
   - 应添加有未提交更改时的 `has_changes: true` 测试

2. **缺少非 Git 仓库测试**
   - 应验证在非 Git 目录下的行为

3. **缺少并发测试**
   - `spawn_git_enrichment_task` 的并发逻辑未测试
   - 任务取消逻辑未测试

4. **缺少错误处理测试**
   - Git 命令失败时的行为
   - 序列化失败时的行为

### 改进建议

1. **添加脏仓库测试**
```rust
#[tokio::test]
async fn build_turn_metadata_header_detects_uncommitted_changes() {
    // 创建文件但不提交
    // 验证 has_changes 为 true
}
```

2. **添加非 Git 目录测试**
```rust
#[tokio::test]
async fn build_turn_metadata_header_returns_none_outside_git_repo() {
    // 在非 Git 目录调用
    // 验证返回 None（如果没有沙盒标签）
}
```

3. **添加富化任务测试**
```rust
#[tokio::test]
async fn git_enrichment_task_updates_header() {
    // 启动富化任务
    // 等待完成
    // 验证头信息已更新
}
```

4. **使用 mock 替代真实 Git**
   - 当前测试依赖真实 Git 命令
   - 可考虑使用 mock 提高测试速度和稳定性

### 潜在风险

1. **测试不稳定（Flaky）**
   - Git 命令可能因系统负载而超时
   - 临时目录清理可能失败

2. **平台差异**
   - Windows 上 Git 行为可能略有不同
   - 路径分隔符差异

3. **Git 版本差异**
   - 不同 Git 版本的输出格式可能不同
   - 建议指定最低 Git 版本要求
