# ConfigWarningNotification.ts Research Document

## 场景与职责

`ConfigWarningNotification` 是 Codex App-Server V2 API 中用于向客户端发送配置相关警告的通知类型。它是服务器主动推送给客户端的消息，用于提醒用户配置文件中的问题或潜在风险。

该类型的典型使用场景包括：
- **配置解析警告**: 配置文件存在语法问题但还能继续解析
- **弃用提醒**: 使用的配置项已被弃用
- **安全风险警告**: 配置设置可能导致安全问题
- **性能影响提示**: 某些配置可能影响系统性能
- **冲突检测**: 多个配置层之间存在冲突

## 功能点目的

`ConfigWarningNotification` 的主要目的是：

1. **非阻塞式提醒**: 在不中断工作流的情况下通知用户配置问题
2. **精确定位**: 提供文件路径和文本范围，帮助用户快速定位问题
3. **分级信息**: 通过 `summary` 和 `details` 提供简洁和详细两个层次的信息
4. **上下文感知**: 可选的位置信息支持 IDE 风格的内联提示

## 具体技术实现

### 数据结构定义

```typescript
import type { TextRange } from "./TextRange";

export type ConfigWarningNotification = { 
  /**
   * Concise summary of the warning.
   */
  summary: string, 
  /**
   * Optional extra guidance or error details.
   */
  details: string | null, 
  /**
   * Optional path to the config file that triggered the warning.
   */
  path?: string, 
  /**
   * Optional range for the error location inside the config file.
   */
  range?: TextRange, 
};
```

### 关键字段说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `summary` | `string` | 是 | 警告的简洁摘要，适合在通知栏或状态栏显示 |
| `details` | `string \| null` | 是 | 详细的警告说明或修复建议，可为 `null` |
| `path` | `string` | 否 | 触发警告的配置文件路径，用于文件定位 |
| `range` | `TextRange` | 否 | 配置文件中问题位置的文本范围，支持精确高亮 |

### TextRange 结构

```typescript
// TextRange 定义（来自 TextRange.ts）
type TextRange = { 
  start: TextPosition, 
  end: TextPosition 
};

// TextPosition 定义（来自 TextPosition.ts）
type TextPosition = { 
  line: number,      // 1-based 行号
  column: number,    // 1-based 列号（Unicode 标量值）
};
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ConfigWarningNotification.ts`
- **Rust 源文件**: 该类型为通知类型，通常在服务端配置解析模块中构造

### 依赖类型

| 类型 | 文件路径 | 说明 |
|------|----------|------|
| `TextRange` | `v2/TextRange.ts` | 文本范围定义 |
| `TextPosition` | `v2/TextPosition.ts` | 文本位置定义（通过 TextRange 间接依赖） |

### 相关通知类型

| 类型 | 说明 |
|------|------|
| `DeprecationNoticeNotification` | 弃用通知，用于 API 或功能弃用提醒 |
| `ErrorNotification` | 错误通知，用于更严重的错误 |

## 依赖与外部交互

### 上游依赖

1. **ts-rs 生成**: 该文件由 Rust 的 `ts-rs` 库自动生成
2. **配置解析器**: 服务端配置解析模块在发现问题时构造此通知
3. **TOML/JSON 解析库**: 底层解析库提供的错误位置信息

### 下游使用

1. **客户端通知系统**: 在 UI 中显示警告信息
2. **IDE 集成**: 在代码编辑器中高亮显示问题位置
3. **日志系统**: 记录警告历史供后续分析

### 通知流程

```
Server Config Parser
        |
        v
Detect Warning Condition
        |
        v
Construct ConfigWarningNotification
        |
        v
Send via WebSocket/SSE
        |
        v
Client Notification Handler
        |
        +---> UI Toast Notification
        +---> IDE Diagnostics Panel
        +---> Log Entry
```

## 风险、边界与改进建议

### 潜在风险

1. **通知疲劳**: 过多的警告通知可能导致用户忽视重要信息
2. **位置不准确**: 解析器提供的文本范围可能与用户感知的位置有偏差
3. **国际化缺失**: 当前设计未考虑多语言警告消息
4. **重复警告**: 相同问题可能多次触发警告

### 边界情况

1. **范围越界**: 
   - 如果配置文件在警告生成后被修改，存储的范围可能失效
   - 客户端需要优雅处理无效范围

2. **多文件配置**: 
   - 配置可能分散在多个文件中
   - 需要确保 `path` 指向正确的文件

3. **空 details**: 
   - `details: null` 表示没有额外信息
   - 客户端应仅显示 `summary`

4. **无位置信息**: 
   - 某些警告可能无法提供 `path` 和 `range`
   - 客户端需要支持纯文本警告显示

### 改进建议

1. **警告级别**: 增加 `level` 字段区分 `info`、`warning`、`critical`
2. **错误代码**: 添加 `code` 字段便于程序化处理和文档链接
3. **快速修复**: 增加 `suggestedFix` 字段提供自动修复建议
4. **去重机制**: 添加 `id` 字段用于客户端去重
5. **国际化**: 支持消息模板和参数，便于本地化
6. **静默期**: 允许用户暂时忽略特定类型的警告

### 代码示例

```typescript
// 示例：处理配置警告通知
function handleConfigWarning(notification: ConfigWarningNotification): void {
  // 显示简洁摘要
  showToast({
    type: 'warning',
    message: notification.summary,
    duration: 5000
  });
  
  // 如果有详细信息，记录到日志
  if (notification.details) {
    console.warn('Config Warning:', notification.details);
  }
  
  // 如果有位置信息，在 IDE 中显示
  if (notification.path && notification.range) {
    addDiagnostic({
      file: notification.path,
      range: notification.range,
      message: notification.summary,
      severity: 'warning'
    });
  }
}

// 示例警告场景
const deprecationWarning: ConfigWarningNotification = {
  summary: "配置项 'auto_approve' 已弃用",
  details: "请使用 'approval_policy' 替代。'auto_approve' 将在 v3.0 中移除。",
  path: "/home/user/.codex/config.toml",
  range: {
    start: { line: 15, column: 1 },
    end: { line: 15, column: 20 }
  }
};

const securityWarning: ConfigWarningNotification = {
  summary: "检测到危险的沙箱配置",
  details: "当前配置允许完整系统访问，建议限制为 workspace-write 模式。",
  path: "/home/user/.codex/config.toml",
  range: {
    start: { line: 8, column: 1 },
    end: { line: 8, column: 30 }
  }
};

const syntaxWarning: ConfigWarningNotification = {
  summary: "配置文件包含未知键",
  details: "键 'unknwon_key' 不是有效的配置项，将被忽略。",
  path: "/home/user/.codex/config.toml",
  range: {
    start: { line: 25, column: 1 },
    end: { line: 25, column: 15 }
  }
};
```

### 与 DeprecationNoticeNotification 的区别

| 特性 | ConfigWarningNotification | DeprecationNoticeNotification |
|------|---------------------------|-------------------------------|
| 用途 | 通用配置警告 | 专门的弃用提醒 |
| 位置信息 | 支持 | 不支持 |
| 严重程度 | 一般警告 | 功能生命周期相关 |
| 触发时机 | 配置解析时 | API 调用时 |
| 字段 | summary, details, path, range | summary, details |

虽然两者都用于通知，但 `ConfigWarningNotification` 更侧重于配置文件本身的问题，而 `DeprecationNoticeNotification` 用于运行时 API 弃用提醒。
