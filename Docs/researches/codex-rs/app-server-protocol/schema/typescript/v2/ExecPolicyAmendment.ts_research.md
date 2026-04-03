# ExecPolicyAmendment.ts Research Document

## 场景与职责

`ExecPolicyAmendment` 是 Codex App-Server Protocol v2 API 中用于表示执行策略修正（Exec Policy Amendment）的数据结构。它是一个字符串数组，表示用户批准命令执行时选择的持久化命令模式，用于未来类似命令的自动批准。

在 Codex 的安全模型中，当 AI 尝试执行可能具有风险的命令（如删除文件、修改系统配置等）时，需要用户明确批准。`ExecPolicyAmendment` 允许用户不仅批准当前命令，还定义一个模式，使未来匹配的命令可以自动执行而无需再次提示。

## 功能点目的

该类型的主要目的是：

1. **持久化批准规则**: 将用户的批准决策持久化为可匹配的模式
2. **提升用户体验**: 减少重复批准相似命令的摩擦
3. **安全策略扩展**: 允许用户精细控制哪些命令可以自动执行
4. **与会话状态关联**: 支持会话级别的自动批准（`AcceptForSession`）和持久化的策略修正

## 具体技术实现

### 数据结构定义

```typescript
// ExecPolicyAmendment.ts
export type ExecPolicyAmendment = Array<string>;
```

### 关键字段说明

`ExecPolicyAmendment` 是一个简单的字符串数组，每个元素代表命令模式的一个组成部分。这些字符串通常按顺序组成一个命令匹配模式。

例如：
- `["rm", "-rf", "./temp/*"]` - 匹配 `rm -rf ./temp/*` 命令
- `["git", "status"]` - 匹配 `git status` 命令
- `["npm", "install"]` - 匹配 `npm install` 命令

### 使用场景

`ExecPolicyAmendment` 主要在以下决策类型中使用：

```typescript
export type CommandExecutionApprovalDecision = 
  | "accept"
  | "acceptForSession"
  | { "acceptWithExecpolicyAmendment": { execpolicyAmendment: ExecPolicyAmendment } }
  | { "applyNetworkPolicyAmendment": { networkPolicyAmendment: NetworkPolicyAmendment } }
  | "decline"
  | "cancel";
```

当用户选择 `AcceptWithExecpolicyAmendment` 时，会提供一个 `ExecPolicyAmendment` 来定义自动批准的模式。

### Rust 端对应实现

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(transparent)]
#[ts(type = "Array<string>", export_to = "v2/")]
pub struct ExecPolicyAmendment {
    pub command: Vec<String>,
}

impl ExecPolicyAmendment {
    pub fn into_core(self) -> CoreExecPolicyAmendment {
        CoreExecPolicyAmendment::new(self.command)
    }
}

impl From<CoreExecPolicyAmendment> for ExecPolicyAmendment {
    fn from(value: CoreExecPolicyAmendment) -> Self {
        Self {
            command: value.command().to_vec(),
        }
    }
}
```

注意：Rust 端使用 `#[serde(transparent)]` 属性，使得序列化时直接展开内部的 `command` 字段，而不是包装成对象。

### 核心库对应类型

```rust
// codex_protocol::approvals::ExecPolicyAmendment
pub struct ExecPolicyAmendment {
    command: Vec<String>,
}

impl ExecPolicyAmendment {
    pub fn new(command: Vec<String>) -> Self {
        Self { command }
    }
    
    pub fn command(&self) -> &[String] {
        &self.command
    }
}
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ExecPolicyAmendment.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ExecPolicyAmendment` 结构体定义（约第 1383-1402 行）
  - `CommandExecutionApprovalDecision` 枚举定义（约第 965-984 行）
- **核心库**: `codex_protocol::approvals::ExecPolicyAmendment`

## 依赖与外部交互

### 上游依赖

1. **CoreExecPolicyAmendment**: 核心库中的执行策略修正类型
2. **CommandExecutionApprovalDecision**: 使用 `ExecPolicyAmendment` 的决策类型

### 下游消费

1. **Approval System**: 批准系统使用此类型创建持久化的批准规则
2. **Command Matching**: 命令匹配逻辑使用存储的修正模式来决定是否自动批准新命令
3. **Policy Storage**: 策略存储系统持久化这些修正规则

### 相关类型

- `NetworkPolicyAmendment`: 类似的网络策略修正类型
  ```rust
  pub struct NetworkPolicyAmendment {
      pub host: String,
      pub action: NetworkPolicyRuleAction,  // "allow" | "deny"
  }
  ```

### 序列化行为

- 使用 `#[serde(transparent)]` 直接序列化为字符串数组
- TypeScript 端表示为 `Array<string>`
- 示例序列化结果：`["git", "status"]`

## 风险、边界与改进建议

### 潜在风险

1. **过于宽泛的模式**: 用户可能创建过于宽泛的模式（如 `["rm"]`），导致意外批准危险命令
2. **模式冲突**: 多个修正规则可能相互冲突，需要明确的优先级策略
3. **安全风险**: 持久化的批准规则可能被恶意利用，需要定期审查
4. **版本兼容性**: 命令行工具的行为可能随版本变化，固定的模式可能产生意外结果

### 边界情况

1. **空数组**: 空数组 `[]` 可能匹配任何命令或完全不匹配，需要明确定义行为
2. **特殊字符**: 命令参数中的特殊字符（通配符、变量等）的转义和匹配规则
3. **参数顺序**: 命令参数的顺序是否影响匹配（`["npm", "install"]` 是否匹配 `npm install --save`）
4. **子命令**: 复杂命令的子命令处理（如 `docker container run`）

### 改进建议

1. **添加通配符支持**: 支持 `*` 和 `?` 等通配符模式匹配
2. **添加正则表达式支持**: 允许更复杂的模式匹配
3. **添加作用域限制**: 限制修正规则的作用域（特定目录、特定项目等）
4. **添加过期时间**: 为修正规则设置过期时间，强制定期重新确认
5. **添加描述字段**: 允许用户为修正规则添加描述，便于后续管理
6. **模式验证**: 在创建修正规则时验证模式的合理性，警告过于宽泛的模式
7. **审计日志**: 记录所有基于修正规则的自动批准操作

### 扩展示例

```typescript
// 建议的扩展版本
export type ExecPolicyAmendment = {
  pattern: string[];
  description?: string;  // 规则描述
  scope?: {
    directories?: string[];  // 限制的目录
    excludeDirectories?: string[];  // 排除的目录
  };
  expiresAt?: number;  // 过期时间戳
  createdAt: number;  // 创建时间
  matchMode: "exact" | "prefix" | "glob" | "regex";  // 匹配模式
  caseSensitive: boolean;  // 是否区分大小写
};

// 使用示例
const amendment: ExecPolicyAmendment = {
  pattern: ["npm", "install"],
  description: "允许在项目目录中运行 npm install",
  scope: {
    directories: ["/home/user/projects/*"]
  },
  expiresAt: Date.now() + 30 * 24 * 60 * 60 * 1000,  // 30天后过期
  createdAt: Date.now(),
  matchMode: "prefix",
  caseSensitive: false
};
```
