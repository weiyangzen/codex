# GitDiffToRemoteParams Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`GitDiffToRemoteParams` 是 App-Server Protocol v1 API 中用于获取本地分支与远程分支差异的请求参数类型。

主要使用场景：
- **代码审查**：在执行操作前查看本地与远程的差异
- **同步检查**：检查本地分支是否需要同步
- **变更预览**：向用户展示即将推送的变更

## 2. 功能点目的 (Purpose of This Type)

- **指定工作目录**：通过 `cwd` 字段指定要检查的 Git 仓库路径
- **差异计算**：请求服务器计算当前 HEAD 与远程跟踪分支的差异
- **集成展示**：在 UI 中展示 diff 信息供用户审查

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
export type GitDiffToRemoteParams = { cwd: string };
```

```rust
// Rust 定义
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct GitDiffToRemoteParams {
    pub cwd: PathBuf,
}
```

### 关键特性

- **简单结构**：仅包含工作目录路径一个字段
- **路径类型**：使用 `PathBuf`（Rust）/ `string`（TypeScript）表示文件系统路径
- **camelCase 序列化**：符合 API 命名规范

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/app-server-protocol/src/protocol/v1.rs` (lines 165-168) | Rust 类型定义 |
| `/codex-rs/app-server-protocol/schema/typescript/GitDiffToRemoteParams.ts` | TypeScript 类型定义（生成） |
| `/codex-rs/app-server-protocol/src/protocol/common.rs` (lines 513-516) | ClientRequest 枚举中注册为 deprecated API |

### 相关类型

- `GitDiffToRemoteResponse`：对应的响应类型，包含 SHA 和 diff 内容
- `GitSha`：提交 SHA 类型

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `std::path::PathBuf`：路径处理
- `serde`：序列化/反序列化
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 使用流程

```rust
// 1. 构造请求
let params = GitDiffToRemoteParams {
    cwd: PathBuf::from("/path/to/repo"),
};

// 2. 发送请求
let request = ClientRequest::GitDiffToRemote {
    request_id: RequestId::Integer(1),
    params,
};

// 3. 接收响应
// GitDiffToRemoteResponse { sha: GitSha, diff: String }
```

### 外部交互

- Git 命令行：执行 `git diff` 或类似操作
- 文件系统：验证工作目录存在且是 Git 仓库

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **已弃用状态**：该 API 已被标记为 DEPRECATED
2. **路径验证**：需要验证 `cwd` 是有效的 Git 仓库
3. **远程分支**：假设存在配置的远程跟踪分支
4. **大 diff**：大型差异可能导致响应过大

### 改进建议

1. **迁移到新 API**：使用 v2 API 替代
2. **添加选项**：支持指定远程名称和分支
3. **分页支持**：对大 diff 添加分页或限制选项
4. **缓存机制**：缓存 diff 结果避免重复计算

### 错误处理

可能的错误场景：
- 路径不存在
- 路径不是 Git 仓库
- 没有配置远程
- 网络问题导致无法获取远程信息

### 安全考虑

- 验证路径在允许访问的范围内
- 防止路径遍历攻击
- 限制 diff 输出大小防止 DoS
