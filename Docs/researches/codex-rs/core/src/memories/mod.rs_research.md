# mod.rs - 研究文档

## 场景与职责

`mod.rs` 是 `memories` 模块的入口文件，定义了记忆子系统的公共接口、常量配置和模块结构。它是理解和使用记忆系统的起点。

### 核心职责

1. **模块组织**: 声明子模块并控制可见性
2. **公共接口**: 导出记忆系统的主要入口点
3. **常量定义**: 定义 Phase 1 和 Phase 2 的配置常量
4. **指标定义**: 定义遥测指标名称
5. **路径辅助**: 提供记忆文件系统路径构建函数

## 功能点目的

### 模块结构

```rust
pub(crate) mod citations;      // 引用解析（公开给外部使用）
mod control;                    // 目录清理控制
mod phase1;                     // Phase 1 实现
mod phase2;                     // Phase 2 实现
pub(crate) mod prompts;        // 提示模板构建
mod start;                      // 启动入口
mod storage;                    // 文件系统存储
#[cfg(test)]
mod tests;                      // 集成测试
pub(crate) mod usage;          // 使用统计
```

### 公共接口

```rust
/// 启动记忆启动管道的单一入口点
pub(crate) use start::start_memories_startup_task;

/// 安全清理记忆根目录内容
pub(crate) use control::clear_memory_root_contents;
```

### 工件常量

```rust
mod artifacts {
    pub(super) const ROLLOUT_SUMMARIES_SUBDIR: &str = "rollout_summaries";
    pub(super) const RAW_MEMORIES_FILENAME: &str = "raw_memories.md";
}
```

### Phase 1 常量

| 常量 | 值 | 描述 |
|------|-----|------|
| `MODEL` | `"gpt-5.1-codex-mini"` | 默认模型 |
| `REASONING_EFFORT` | `ReasoningEffort::Low` | 推理努力程度 |
| `PROMPT` | `stage_one_system.md` | 系统提示模板 |
| `CONCURRENCY_LIMIT` | `8` | 并行作业限制 |
| `DEFAULT_STAGE_ONE_ROLLOUT_TOKEN_LIMIT` | `150_000` | 回退 token 限制 |
| `MEMORY_TOOL_DEVELOPER_INSTRUCTIONS_SUMMARY_TOKEN_LIMIT` | `5_000` | 开发者指令摘要限制 |
| `CONTEXT_WINDOW_PERCENT` | `70` | 上下文窗口使用百分比 |
| `JOB_LEASE_SECONDS` | `3_600` | 作业租约时长（1小时） |
| `JOB_RETRY_DELAY_SECONDS` | `3_600` | 重试延迟（1小时） |
| `THREAD_SCAN_LIMIT` | `5_000` | 线程扫描限制 |
| `PRUNE_BATCH_SIZE` | `200` | 清理批处理大小 |

### Phase 2 常量

| 常量 | 值 | 描述 |
|------|-----|------|
| `MODEL` | `"gpt-5.3-codex"` | 默认模型 |
| `REASONING_EFFORT` | `ReasoningEffort::Medium` | 推理努力程度 |
| `JOB_LEASE_SECONDS` | `3_600` | 作业租约时长（1小时） |
| `JOB_RETRY_DELAY_SECONDS` | `3_600` | 重试延迟（1小时） |
| `JOB_HEARTBEAT_SECONDS` | `90` | 心跳间隔 |

### 指标常量

```rust
mod metrics {
    // Phase 1 指标
    pub(super) const MEMORY_PHASE_ONE_JOBS: &str = "codex.memory.phase1";
    pub(super) const MEMORY_PHASE_ONE_E2E_MS: &str = "codex.memory.phase1.e2e_ms";
    pub(super) const MEMORY_PHASE_ONE_OUTPUT: &str = "codex.memory.phase1.output";
    pub(super) const MEMORY_PHASE_ONE_TOKEN_USAGE: &str = "codex.memory.phase1.token_usage";
    
    // Phase 2 指标
    pub(super) const MEMORY_PHASE_TWO_JOBS: &str = "codex.memory.phase2";
    pub(super) const MEMORY_PHASE_TWO_E2E_MS: &str = "codex.memory.phase2.e2e_ms";
    pub(super) const MEMORY_PHASE_TWO_INPUT: &str = "codex.memory.phase2.input";
    pub(super) const MEMORY_PHASE_TWO_TOKEN_USAGE: &str = "codex.memory.phase2.token_usage";
}
```

### 路径辅助函数

```rust
/// 构建记忆根目录路径
pub fn memory_root(codex_home: &Path) -> PathBuf {
    codex_home.join("memories")
}

/// 构建 rollout_summaries 子目录路径
fn rollout_summaries_dir(root: &Path) -> PathBuf {
    root.join(artifacts::ROLLOUT_SUMMARIES_SUBDIR)
}

/// 构建 raw_memories.md 文件路径
fn raw_memories_file(root: &Path) -> PathBuf {
    root.join(artifacts::RAW_MEMORIES_FILENAME)
}

/// 确保目录布局存在
async fn ensure_layout(root: &Path) -> std::io::Result<()> {
    tokio::fs::create_dir_all(rollout_summaries_dir(root)).await
}
```

## 关键代码路径与文件引用

### 模块导出

| 项目 | 行号 | 可见性 | 描述 |
|------|------|--------|------|
| `citations` | 7 | `pub(crate)` | 引用解析模块 |
| `control` | 8 | `mod` | 清理控制（私有） |
| `phase1` | 9 | `mod` | Phase 1（私有） |
| `phase2` | 10 | `mod` | Phase 2（私有） |
| `prompts` | 11 | `pub(crate)` | 提示构建模块 |
| `start` | 12 | `mod` | 启动入口（私有） |
| `storage` | 13 | `mod` | 存储（私有） |
| `usage` | 16 | `pub(crate)` | 使用统计模块 |

### 常量定义位置

| 模块 | 行号范围 | 描述 |
|------|----------|------|
| `artifacts` | 27-30 | 工件文件名常量 |
| `phase_one` | 33-62 | Phase 1 配置常量 |
| `phase_two` | 65-77 | Phase 2 配置常量 |
| `metrics` | 79-96 | 遥测指标名称 |

### 函数定义

| 函数 | 行号 | 签名 |
|------|------|------|
| `memory_root` | 101-103 | `pub fn memory_root(codex_home: &Path) -> PathBuf` |
| `rollout_summaries_dir` | 105-107 | `fn rollout_summaries_dir(root: &Path) -> PathBuf` |
| `raw_memories_file` | 109-111 | `fn raw_memories_file(root: &Path) -> PathBuf` |
| `ensure_layout` | 113-115 | `async fn ensure_layout(root: &Path) -> std::io::Result<()>` |

## 依赖与外部交互

### 导入依赖

| 依赖 | 用途 |
|------|------|
| `codex_protocol::openai_models::ReasoningEffort` | Phase 1/2 推理努力程度 |
| `std::path::Path`/`PathBuf` | 路径处理 |

### 子模块依赖

| 子模块 | 导出内容 |
|--------|----------|
| `control` | `clear_memory_root_contents` |
| `start` | `start_memories_startup_task` |

## 风险、边界与改进建议

### 常量硬编码风险

1. **模型版本**: 硬编码的模型名称可能在模型更新时过时
2. **阈值限制**: Token 限制和并发限制是经验值，可能不适合所有场景
3. **时间常量**: 租约和重试延迟固定为 1 小时，缺乏灵活性

### 改进建议

1. **配置化常量**:
```rust
// 考虑从 Config 读取而非硬编码
pub fn phase_one_model(config: &Config) -> String {
    config.memories.extract_model.clone()
        .unwrap_or_else(|| phase_one::MODEL.to_string())
}
```

2. **动态调整**:
   - 根据系统负载动态调整并发限制
   - 根据模型响应时间调整租约时长

3. **版本化模板**:
   - 为提示模板添加版本控制
   - 支持模板热更新

4. **指标标签标准化**:
   - 考虑使用枚举而非字符串常量
   - 避免拼写错误

5. **路径验证**:
   - 在 `memory_root` 中添加路径验证
   - 确保路径不包含非法字符

6. **文档化常量**:
   - 为每个常量添加文档注释说明其用途和选择理由
