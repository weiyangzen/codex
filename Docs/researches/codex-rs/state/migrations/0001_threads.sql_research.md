# 0001_threads.sql 研究文档

## 场景与职责

本迁移文件是 `codex-rs/state` crate 的初始数据库迁移，负责创建核心的 `threads` 表，用于存储 Codex 会话（thread）的元数据。这是整个状态管理系统的基石，为后续的线程管理、归档、查询等功能提供数据存储基础。

## 功能点目的

### 1. threads 表结构
创建包含以下字段的线程元数据表：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | TEXT PRIMARY KEY | 线程唯一标识符（UUID格式） |
| `rollout_path` | TEXT NOT NULL | rollout 文件的绝对路径 |
| `created_at` | INTEGER NOT NULL | 创建时间戳（Unix秒） |
| `updated_at` | INTEGER NOT NULL | 最后更新时间戳 |
| `source` | TEXT NOT NULL | 会话来源（如 "cli", "vscode" 等） |
| `model_provider` | TEXT NOT NULL | 模型提供商 |
| `cwd` | TEXT NOT NULL | 当前工作目录 |
| `title` | TEXT NOT NULL | 会话标题 |
| `sandbox_policy` | TEXT NOT NULL | 沙箱策略 |
| `approval_mode` | TEXT NOT NULL | 审批模式 |
| `tokens_used` | INTEGER NOT NULL DEFAULT 0 | 使用的token数量 |
| `has_user_event` | INTEGER NOT NULL DEFAULT 0 | 是否有用户事件 |
| `archived` | INTEGER NOT NULL DEFAULT 0 | 是否已归档 |
| `archived_at` | INTEGER | 归档时间戳（可为空） |
| `git_sha` | TEXT | Git commit SHA |
| `git_branch` | TEXT | Git 分支名 |
| `git_origin_url` | TEXT | Git 远程仓库URL |

### 2. 索引设计
创建5个索引优化查询性能：
- `idx_threads_created_at`: 按创建时间倒序查询
- `idx_threads_updated_at`: 按更新时间倒序查询
- `idx_threads_archived`: 归档状态筛选
- `idx_threads_source`: 按来源筛选
- `idx_threads_provider`: 按模型提供商筛选

## 具体技术实现

### 关键流程
1. **表创建**: 使用标准 SQLite CREATE TABLE 语法
2. **索引创建**: 使用 CREATE INDEX 优化常见查询模式
3. **外键关系**: 后续迁移中的表（如 `thread_dynamic_tools`）通过 `thread_id` 外键关联到本表

### 数据类型设计
- 时间戳使用 INTEGER 存储 Unix 秒（符合 SQLite 最佳实践）
- 布尔值使用 INTEGER（0/1）表示
- 可选字段使用 nullable 类型

## 关键代码路径与文件引用

### 模型定义
- `codex-rs/state/src/model/thread_metadata.rs`: 定义 `ThreadMetadata` 和 `ThreadRow` 结构体，映射本表结构

### 运行时操作
- `codex-rs/state/src/runtime/threads.rs`: 实现线程的 CRUD 操作
  - `get_thread()`: 查询单个线程
  - `upsert_thread()`: 插入或更新线程
  - `list_threads()`: 分页查询线程列表

### 数据提取
- `codex-rs/state/src/extract.rs`: 从 rollout JSONL 文件提取元数据并写入本表

## 依赖与外部交互

### 上游依赖
- 无（这是初始迁移）

### 下游依赖
- `0004_thread_dynamic_tools.sql`: 依赖 `threads.id` 作为外键
- `0006_memories.sql`: `stage1_outputs` 表依赖 `threads.id`
- `0014_agent_jobs.sql`: `agent_job_items` 可能引用线程

### 应用层交互
- `codex-rs/tui/src/app.rs`: 通过 `StateRuntime` 查询线程列表
- `codex-rs/core/src/rollout.rs`: 写入 rollout 时更新线程元数据

## 风险、边界与改进建议

### 风险
1. **主键约束**: `id` 必须是有效的 UUID 格式，非法格式会导致插入失败
2. **路径长度**: `rollout_path` 和 `cwd` 使用 TEXT，理论上无长度限制，但过长的路径可能影响性能

### 边界情况
1. **时间戳精度**: 使用 Unix 秒级精度，同一秒内创建/更新的线程排序依赖 `id` 字段
2. **归档逻辑**: `archived` 和 `archived_at` 需要保持一致性，应用层需确保同时更新

### 改进建议
1. 考虑添加 `CHECK` 约束确保 `archived=1` 时 `archived_at` 不为空
2. 可为 `git_sha` 添加索引（如果频繁按 Git 提交查询）
3. 考虑将 `tokens_used` 拆分为输入/输出 token 分别统计
