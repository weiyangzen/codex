# bridge.js 研究文档

## 场景与职责

`bridge.js` 是 Code Mode 执行环境的**桥梁脚本**，负责在 Node.js VM 上下文中为用户代码准备运行时环境。它作为用户 JavaScript 代码与宿主环境（Rust 端）之间的粘合层，将 Rust 端提供的运行时能力暴露给隔离的 VM 环境。

**核心定位**：
- 在 VM 上下文中定义全局 API（`tools`, `text`, `image`, `store`, `load` 等）
- 接收来自 Rust 端的运行时数据（`__codexRuntime`）并转换为全局变量
- 提供一个安全的、受控的 JavaScript 执行环境
- 禁用原生 `console` 对象以防止未经授权的输出

## 功能点目的

### 1. 内容项管理
```javascript
const __codexContentItems = Array.isArray(globalThis.__codexContentItems)
  ? globalThis.__codexContentItems
  : [];
```
- 维护 `__codexContentItems` 数组，用于收集脚本执行过程中的输出内容
- 使用 `Object.defineProperty` 将其设置为不可枚举但可配置，防止用户代码意外修改

### 2. 运行时数据消费
```javascript
const __codexRuntime = globalThis.__codexRuntime;
delete globalThis.__codexRuntime;
```
- 从全局上下文中提取 Rust 端注入的运行时数据
- 立即删除原始属性，防止用户代码直接访问内部运行时对象

### 3. 全局 API 暴露
通过 `defineGlobal` 函数将以下 API 暴露为全局变量：

| 全局变量 | 来源 | 用途 |
|---------|------|------|
| `ALL_TOOLS` | `__codexRuntime.ALL_TOOLS` | 可用工具的元数据列表 |
| `exit` | `__codexRuntime.exit` | 立即终止脚本执行 |
| `image` | `__codexRuntime.image` | 添加图像输出项 |
| `load` | `__codexRuntime.load` | 从存储中读取值 |
| `notify` | `__codexRuntime.notify` | 发送即时通知到模型 |
| `store` | `__codexRuntime.store` | 存储键值对供后续使用 |
| `text` | `__codexRuntime.text` | 添加文本输出项 |
| `tools` | `__codexRuntime.tools` | 嵌套工具调用命名空间 |
| `yield_control` | `__codexRuntime.yield_control` | 主动让出控制权 |

### 4. Console 禁用
```javascript
defineGlobal('console', Object.freeze({
  log() {}, info() {}, warn() {}, error() {}, debug() {}
}));
```
- 完全禁用原生 `console` 方法，确保输出通过受控的 `text()` API 进行
- 这是安全沙箱的一部分，防止信息泄露

## 具体技术实现

### 代码结构
```
bridge.js
├── 内容项初始化（__codexContentItems）
├── 运行时数据提取（__codexRuntime）
├── IIFE 立即执行函数
│   ├── 运行时可用性检查
│   ├── defineGlobal 辅助函数
│   ├── 全局 API 注册
│   └── Console 对象替换
└── 用户代码占位符（__CODE_MODE_USER_CODE_PLACEHOLDER__）
```

### 关键流程

1. **初始化阶段**：
   - 检查 `__codexContentItems` 是否存在，不存在则创建空数组
   - 提取 `__codexRuntime` 对象

2. **属性锁定阶段**：
   - 使用 `Object.defineProperty` 锁定 `__codexContentItems`
   - 设置为 `configurable: true`（允许后续修改）、`enumerable: false`（隐藏）、`writable: false`（只读）

3. **API 暴露阶段**：
   - IIFE 内部验证 `__codexRuntime` 存在且为对象
   - 遍历运行时方法，逐个注册为全局变量
   - 所有全局变量设置为 `writable: false` 防止篡改

4. **代码注入阶段**：
   - `__CODE_MODE_USER_CODE_PLACEHOLDER__` 会被替换为实际用户代码

### 数据结构

**defineGlobal 配置**：
```javascript
{
  value,           // 要暴露的值
  configurable: true,   // 允许删除或修改描述符
  enumerable: true,     // 可枚举（出现在 for...in 中）
  writable: false       // 值不可修改
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/bridge.js`

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/protocol.rs` - `build_source()` 函数将 `bridge.js` 与用户代码合并
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/runner.cjs` - Worker 线程中实际执行合并后的代码

### 相关常量
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/mod.rs` 第 34 行：
  ```rust
  const CODE_MODE_BRIDGE_SOURCE: &str = include_str!("bridge.js");
  ```

### 数据流
```
protocol.rs:build_source()
    │
    ├──> 读取 CODE_MODE_BRIDGE_SOURCE (bridge.js)
    │
    ├──> 替换 __CODE_MODE_ENABLED_TOOLS_PLACEHOLDER__ 为工具列表 JSON
    │
    ├──> 替换 __CODE_MODE_USER_CODE_PLACEHOLDER__ 为用户代码
    │
    └──> 生成完整 source 传递给 runner.cjs
```

## 依赖与外部交互

### 输入依赖
| 来源 | 数据 | 说明 |
|------|------|------|
| `globalThis.__codexRuntime` | 运行时对象 | 由 runner.cjs 的 Worker 线程注入 |
| `globalThis.__codexContentItems` | 内容项数组 | 预初始化的输出收集器 |

### 输出暴露
| 全局变量 | 类型 | 说明 |
|---------|------|------|
| `ALL_TOOLS` | Array | 工具元数据 `{name, description}` 数组 |
| `exit` | Function | 终止执行函数 |
| `image` | Function | 图像输出函数 |
| `load` | Function | 存储读取函数 |
| `notify` | Function | 通知函数 |
| `store` | Function | 存储写入函数 |
| `text` | Function | 文本输出函数 |
| `tools` | Object | 嵌套工具命名空间 |
| `yield_control` | Function | 让出控制函数 |
| `console` | Object | 空实现对象 |

### 与 runner.cjs 的关系
- `runner.cjs` 创建 VM 上下文并注入 `__codexRuntime`
- `bridge.js` 消费 `__codexRuntime` 并转换为更友好的全局 API
- 这种分层设计允许 `runner.cjs` 保持内部实现细节，而 `bridge.js` 提供稳定的公共 API

## 风险、边界与改进建议

### 风险点

1. **运行时依赖风险**
   - 如果 `__codexRuntime` 未定义或非对象，会抛出 `"code mode runtime is unavailable"` 错误
   - 这是预期的防御性编程，但错误信息对用户不够友好

2. **全局命名空间污染**
   - 虽然使用了 `writable: false`，但仍然在全局命名空间注册了多个变量
   - 如果用户代码定义了同名变量，可能会产生冲突

3. **Console 完全禁用**
   - 完全空实现的 console 可能导致调试困难
   - 某些库可能依赖 console 存在（即使只是检查）

### 边界情况

1. **__codexContentItems 已存在**
   - 代码使用 `Array.isArray` 检查，确保不会覆盖已有数组
   - 支持增量执行场景

2. **多次执行**
   - `configurable: true` 允许后续执行重新配置属性
   - 但 `writable: false` 确保值不会被意外修改

### 改进建议

1. **错误处理增强**
   ```javascript
   // 当前
   throw new Error('code mode runtime is unavailable');
   
   // 建议：提供更详细的诊断信息
   throw new Error(`code mode runtime is unavailable: expected object, got ${typeof __codexRuntime}`);
   ```

2. **命名空间隔离**
   - 考虑将所有 API 挂载到单个全局对象（如 `codex`）下，减少全局命名空间污染
   - 例如：`codex.tools.exec_command()` 而非全局 `tools`

3. **Console 代理**
   - 考虑将 console 调用重定向到 `text()`，而非完全禁用
   - 便于调试且保持输出受控

4. **API 文档生成**
   - `ALL_TOOLS` 可以扩展包含参数类型信息，支持更好的 IDE 自动完成
