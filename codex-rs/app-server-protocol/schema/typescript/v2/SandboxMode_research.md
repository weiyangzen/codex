# SandboxMode 研究文档

## 1. 场景与职责

`SandboxMode` 是 Codex app-server-protocol v2 协议中的沙箱模式类型，用于定义代码执行的安全级别。该类型提供三种预设的安全模式，从严格的只读访问到完全访问，满足不同场景下的安全与功能需求平衡。

### 使用场景
- **安全执行环境**：为 AI 工具执行提供隔离环境
- **权限分级**：根据任务类型选择合适的安全级别
- **用户控制**：允许用户选择可接受的安全风险级别

## 2. 功能点目的

该类型的核心目的是：
1. **简化权限配置**：提供预设的安全模式，降低配置复杂度
2. **安全分级**：明确区分不同级别的安全风险
3. **用户透明**：使用清晰的命名让用户理解权限含义

### 沙箱模式对比
| 模式 | 文件系统 | 网络 | 适用场景 |
|------|----------|------|----------|
| `read-only` | 只读 | 受限 | 安全分析、代码阅读 |
| `workspace-write` | 工作区写入 | 可选 | 代码生成、文件修改 |
| `danger-full-access` | 完全访问 | 完全 | 系统管理、危险操作 |

## 3. 具体技术实现

### TypeScript 类型定义
```typescript
export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
```

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[ts(rename_all = "kebab-case", export_to = "v2/")]
pub enum SandboxMode {
    ReadOnly,
    WorkspaceWrite,
    DangerFullAccess,
}
```

### 核心协议定义
```rust
// codex-rs/protocol/src/protocol.rs
pub enum SandboxMode {
    ReadOnly,
    WorkspaceWrite,
    DangerFullAccess,
}
```

### 字段说明
| 值 | 说明 |
|----|------|
| `"read-only"` | 只读模式，文件系统只读，网络受限 |
| `"workspace-write"` | 工作区写入模式，允许修改工作区文件 |
| `"danger-full-access"` | 危险完全访问模式，无限制访问 |

### 类型转换实现
```rust
impl SandboxMode {
    pub fn to_core(self) -> CoreSandboxMode {
        match self {
            SandboxMode::ReadOnly => CoreSandboxMode::ReadOnly,
            SandboxMode::WorkspaceWrite => CoreSandboxMode::WorkspaceWrite,
            SandboxMode::DangerFullAccess => CoreSandboxMode::DangerFullAccess,
        }
    }
}

impl From<CoreSandboxMode> for SandboxMode {
    fn from(value: CoreSandboxMode) -> Self {
        match value {
            CoreSandboxMode::ReadOnly => SandboxMode::ReadOnly,
            CoreSandboxMode::WorkspaceWrite => SandboxMode::WorkspaceWrite,
            CoreSandboxMode::DangerFullAccess => SandboxMode::DangerFullAccess,
        }
    }
}
```

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 298-325)
- **核心协议**: `codex-rs/protocol/src/protocol.rs`
- **TypeScript 文件**: `codex-rs/app-server-protocol/schema/typescript/v2/SandboxMode.ts`

### 使用位置

#### 配置要求
- **文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 作为 `ConfigRequirements` 的 `allowedSandboxModes` 字段元素

#### 审批配置
- **文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 用于 `AskForApproval` 枚举

#### Windows 沙箱
- **文件**: `codex-rs/windows-sandbox-rs/src/`
  - 多个文件使用 `SandboxPolicy` 进行权限控制

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json`

## 5. 依赖与外部交互

### 导入依赖
- 无直接导入的类型

### 被依赖类型
- `ConfigRequirements` - 包含 `allowedSandboxModes: Array<SandboxMode> | null`
- `AskForApproval` - 沙箱模式相关的审批配置

### 核心协议映射
- `CoreSandboxMode::ReadOnly` ↔ `SandboxMode::ReadOnly`
- `CoreSandboxMode::WorkspaceWrite` ↔ `SandboxMode::WorkspaceWrite`
- `CoreSandboxMode::DangerFullAccess` ↔ `SandboxMode::DangerFullAccess`

### 与 SandboxPolicy 的关系
`SandboxMode` 是高层抽象，对应到 `SandboxPolicy` 的具体实现：
- `read-only` → `SandboxPolicy::ReadOnly`
- `workspace-write` → `SandboxPolicy::WorkspaceWrite`
- `danger-full-access` → `SandboxPolicy::DangerFullAccess`

## 6. 风险、边界与改进建议

### 潜在风险
1. **命名误导**：`danger-full-access` 的命名虽警示但仍可能被误用
2. **模式降级**：某些操作可能需要比当前模式更高的权限
3. **平台差异**：不同操作系统对沙箱的实现有差异

### 边界情况
- **嵌套执行**：子进程的沙箱模式继承问题
- **动态切换**：执行过程中切换沙箱模式的复杂性
- **外部工具**：调用外部工具时的沙箱边界

### 改进建议
1. **添加中间模式**：
   ```typescript
   export type SandboxMode = 
     | "read-only" 
     | "workspace-write" 
     | "network-enabled"  // 新增：工作区写入 + 网络
     | "danger-full-access";
   ```

2. **添加描述信息**：
   ```typescript
   export const SandboxModeDescriptions: Record<SandboxMode, string> = {
     "read-only": "只能读取文件，无法修改或访问网络",
     "workspace-write": "可以修改工作区文件，网络访问受限",
     "danger-full-access": "完全访问权限，请谨慎使用"
   };
   ```

3. **运行时检查**：
   - 在危险操作前进行二次确认
   - 提供当前沙箱状态的视觉指示

4. **审计日志**：
   - 记录沙箱模式的使用情况
   - 对 `danger-full-access` 模式进行特别审计

5. **渐进式权限**：
   - 支持临时提升权限的请求机制
   - 用户可以批准单次操作的权限提升

### 使用示例
```typescript
// 配置允许的模式
const config: ConfigRequirements = {
  allowedSandboxModes: ["read-only", "workspace-write"],
  // 不允许 danger-full-access
};

// 根据任务选择模式
function selectSandboxMode(task: Task): SandboxMode {
  switch (task.type) {
    case "analyze":
      return "read-only";
    case "generate":
      return "workspace-write";
    case "system":
      return "danger-full-access";
    default:
      return "read-only";
  }
}

// UI 展示
function renderSandboxMode(mode: SandboxMode) {
  const icons = {
    "read-only": "🔒",
    "workspace-write": "✏️",
    "danger-full-access": "⚠️"
  };
  return `${icons[mode]} ${mode}`;
}
```

### 相关类型关系
```
ConfigRequirements
├── allowedSandboxModes: Array<SandboxMode> | null  <-- 本类型
│   ├── "read-only"
│   ├── "workspace-write"
│   └── "danger-full-access"
└── ...

SandboxPolicy (底层实现)
├── ReadOnly { access, network_access }
├── WorkspaceWrite { writable_roots, network_access, ... }
├── DangerFullAccess
└── ExternalSandbox { network_access }
```
