# GitDiffToRemoteResponse Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`GitDiffToRemoteResponse` 是 `GitDiffToRemote` 请求的响应类型，用于返回本地分支与远程分支的差异信息。

主要使用场景：
- **变更展示**：在 UI 中展示本地与远程的代码差异
- **提交确认**：在执行推送前向用户展示将要推送的内容
- **状态同步**：帮助用户了解本地分支是否领先于远程

## 2. 功能点目的 (Purpose of This Type)

- **返回基准 SHA**：告知客户端比较的基准提交
- **返回 diff 内容**：提供可读的差异文本
- **支持审查流程**：为代码审查提供数据基础

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
import type { GitSha } from "./GitSha";

export type GitDiffToRemoteResponse = { sha: GitSha, diff: string };
```

```rust
// Rust 定义
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct GitDiffToRemoteResponse {
    pub sha: GitSha,
    pub diff: String,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|-----|------|------|
| `sha` | `GitSha` | 本地 HEAD 的提交 SHA |
| `diff` | `string` | 与远程跟踪分支的差异文本（unified diff 格式） |

### 嵌套类型 GitSha

```rust
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, JsonSchema, TS)]
#[ts(type = "string")]
pub struct GitSha(pub String);

impl GitSha {
    pub fn new(sha: &str) -> Self {
        Self(sha.to_string())
    }
}
```

`GitSha` 是一个新类型模式（newtype）包装器，提供类型安全的同时在 TypeScript 中表现为普通字符串。

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/app-server-protocol/src/protocol/v1.rs` (lines 117-120) | Rust 类型定义 |
| `/codex-rs/app-server-protocol/src/protocol/common.rs` (lines 17-25) | `GitSha` 类型定义 |
| `/codex-rs/app-server-protocol/schema/typescript/GitDiffToRemoteResponse.ts` | TypeScript 类型定义（生成） |
| `/codex-rs/app-server-protocol/schema/typescript/GitSha.ts` | GitSha TypeScript 定义 |

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `GitSha`：提交 SHA 类型
- `serde`：序列化/反序列化
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 相关 API

- `GitDiffToRemoteParams`：对应的请求参数
- Git 命令行：执行 `git diff HEAD..@{upstream}` 或类似命令

### diff 格式

返回的 diff 通常采用 unified diff 格式：
```diff
--- a/file.txt
+++ b/file.txt
@@ -1,5 +1,5 @@
 line 1
 line 2
-line 3
+line 3 modified
 line 4
 line 5
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **已弃用**：该 API 已被标记为 DEPRECATED
2. **大 diff 问题**：大型差异可能导致响应过大，影响性能
3. **编码问题**：diff 文本的编码处理（非 UTF-8 文件）
4. **二进制文件**：二进制文件的 diff 处理

### 改进建议

1. **分页支持**：对大 diff 添加分页或截断选项
2. **统计信息**：添加变更统计（添加/删除行数、文件数）
3. **文件列表**：单独提供变更文件列表
4. **格式选项**：支持不同 diff 格式（如 `--stat`）

### 替代方案

建议使用 v2 API 或直接使用 Git 命令：
```bash
git diff HEAD..@{upstream}
git diff --stat HEAD..@{upstream}
```

### 性能考虑

- 对大型仓库，diff 计算可能较慢
- 考虑添加超时机制
- 缓存最近计算的 diff 结果
