# ClientInfo.ts 研究文档

## 场景与职责

`ClientInfo.ts` 定义了客户端信息类型，用于在初始化连接时向服务端标识客户端的身份和版本。这是 Codex App Server Protocol 初始化流程的基础类型，确保服务端能够识别和适配不同的客户端。

**核心职责：**
- 标识客户端名称和版本
- 支持客户端标题的展示
- 为服务端提供客户端能力协商的基础信息

## 功能点目的

1. **客户端识别**
   - 让服务端知道连接的是哪种客户端（CLI、VS Code 扩展、Web 等）
   - 支持针对不同客户端的特定适配

2. **版本管理**
   - 传递客户端版本信息
   - 支持版本兼容性检查和功能适配

3. **用户界面展示**
   - `title` 字段支持在服务端 UI 中展示客户端的友好名称

## 具体技术实现

### 类型定义

```typescript
export type ClientInfo = { 
  name: string, 
  title: string | null, 
  version: string, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `string` | 客户端标识名称（如 `"codex_cli"`, `"codex_vscode"`） |
| `title` | `string \| null` | 客户端的友好展示标题 |
| `version` | `string` | 客户端版本号（如 `"1.0.0"`） |

### 生成信息

- **生成工具**: [ts-rs](https://github.com/Aleph-Alpha/ts-rs)
- **源文件**: `codex-rs/app-server-protocol/src/protocol/v1.rs`
- **Rust 类型**: `ClientInfo`
- **序列化**: 使用 camelCase 命名

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
pub struct ClientInfo {
    pub name: String,
    pub title: Option<String>,
    pub version: String,
}
```

## 关键代码路径与文件引用

### 使用场景

1. **InitializeParams**
   - 作为初始化请求的参数
   - 文件: `InitializeParams.ts`

2. **会话管理**
   - 用于记录会话来源和客户端类型
   - 与 `SessionSource` 类型相关

### 相关类型

- **`InitializeParams`**: 初始化参数，包含 `clientInfo` 字段
- **`InitializeResponse`**: 初始化响应，返回服务端信息
- **`SessionSource`**: 会话来源，包含客户端类型信息

### 使用示例

```typescript
// 初始化请求
const initParams: InitializeParams = {
  clientInfo: {
    name: "codex_cli",
    title: "Codex CLI",
    version: "1.0.0"
  },
  capabilities: {
    experimentalApi: true,
    optOutNotificationMethods: ["thread/started"]
  }
};
```

## 依赖与外部交互

### 上游依赖

- 无直接依赖（基础结构类型）

### 下游使用者

| 使用者 | 路径 | 用途 |
|--------|------|------|
| `InitializeParams` | `./InitializeParams` | 初始化请求参数 |
| 会话管理 | - | 记录会话来源 |
| 分析系统 | - | 客户端使用统计 |

### 序列化格式示例

```json
{
  "name": "codex_cli",
  "title": "Codex CLI",
  "version": "1.0.0"
}
```

## 风险、边界与改进建议

### 风险点

1. **客户端标识冲突**
   - 不同客户端可能使用相同的 `name`
   - 需要建立客户端名称注册机制

2. **版本格式不统一**
   - 不同客户端可能使用不同的版本格式
   - 需要规范版本号格式（建议遵循 SemVer）

3. **信息伪造**
   - 客户端可以伪造 `name` 和 `version`
   - 不应依赖这些信息进行安全决策

### 边界情况

1. **空名称**
   - `name` 为空字符串时的处理
   - 是否应该要求非空

2. **过长字符串**
   - 名称和标题的长度限制
   - 数据库字段长度考虑

3. **特殊字符**
   - 名称中包含特殊字符的处理
   - 日志记录和展示的转义需求

### 改进建议

1. **客户端注册表**
   - 建立官方客户端名称注册表
   - 避免名称冲突和伪造

2. **版本规范**
   - 明确版本号格式要求（SemVer）
   - 添加版本兼容性检查

3. **扩展信息**
   - 考虑添加更多客户端信息：
     - 操作系统信息
     - 运行时环境（Node.js 版本等）
     - 支持的协议版本

4. **验证机制**
   - 添加基本的字段验证
   - 名称格式、版本格式检查

5. **与 User-Agent 对齐**
   - `InitializeResponse` 返回 `userAgent`
   - 考虑在 `ClientInfo` 中也添加类似字段
