# WindowsWorldWritableWarningNotification.json 研究文档

## 场景与职责

`WindowsWorldWritableWarningNotification` 是 Codex App-Server Protocol v2 中的服务器通知类型，专门用于 Windows 平台。当检测到系统中存在"世界可写"（world-writable）目录时发送此通知，警告用户这些目录无法被沙箱保护。

**核心职责：**
- 警告用户存在安全风险目录
- 提供受影响的示例路径
- 报告扫描结果统计
- 提醒用户注意数据安全

## 功能点目的

### 1. 安全警告机制
Windows 沙箱有特定的安全限制：
- 某些目录无法被沙箱正确保护
- "世界可写"目录可能被任意用户修改
- 需要警告用户这些安全风险

### 2. 扫描结果报告
通知包含扫描的详细结果：
- `sample_paths`: 示例受影响路径
- `extra_count`: 超出示例的额外数量
- `failed_scan`: 扫描是否失败

### 3. 用户教育
通过此通知：
- 让用户了解 Windows 沙箱的限制
- 建议用户避免在这些目录中操作敏感数据
- 提高安全意识

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct WindowsWorldWritableWarningNotification {
    pub sample_paths: Vec<String>,
    pub extra_count: usize,
    pub failed_scan: bool,
}
```

### 字段说明

| 字段 | 类型 | 描述 |
|------|------|------|
| `sample_paths` | `Vec<String>` | 示例世界可写目录路径（通常最多显示几个） |
| `extra_count` | `usize` | 除示例外还有多少类似目录 |
| `failed_scan` | `bool` | 目录扫描是否失败 |

### 关键流程

1. **启动扫描**：服务器启动时或定期扫描系统中的世界可写目录
2. **收集结果**：收集受影响的目录路径
3. **发送通知**：向客户端发送警告通知
4. **客户端处理**：客户端显示警告信息给用户

### 通知示例

**正常场景：**
```json
{
  "jsonrpc": "2.0",
  "method": "windows/worldWritableWarning",
  "params": {
    "sample_paths": [
      "C:\\Users\\Public\\Writable",
      "C:\\Temp\\Shared"
    ],
    "extra_count": 5,
    "failed_scan": false
  }
}
```

**扫描失败场景：**
```json
{
  "jsonrpc": "2.0",
  "method": "windows/worldWritableWarning",
  "params": {
    "sample_paths": [],
    "extra_count": 0,
    "failed_scan": true
  }
}
```

## 关键代码路径与文件引用

### 定义位置
- `WindowsWorldWritableWarningNotification`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4971`

### 通知注册
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:933`
  ```rust
  WindowsWorldWritableWarning => "windows/worldWritableWarning" (v2::WindowsWorldWritableWarningNotification),
  ```

### 相关类型
- 无其他直接相关类型，使用标准 `Vec<String>`、`usize`、`bool`

## 依赖与外部交互

### 上游依赖
- Windows 系统 API 用于：
  - 枚举系统中的目录
  - 检查目录权限（ACL）
  - 识别世界可写目录

### 下游消费
- Windows 客户端接收通知并显示警告 UI
- 可能以警告横幅、弹窗或日志形式呈现
- 建议用户采取的安全措施

### 协议集成
- JSON-RPC 2.0 通知格式
- 方法名: `windows/worldWritableWarning`
- 参数: `WindowsWorldWritableWarningNotification`

### 平台限制
- 仅在 Windows 平台发送
- 与 Windows 特定的沙箱限制相关

## 风险、边界与改进建议

### 已知风险

1. **误报可能**
   - 某些世界可写目录可能是正常的系统目录
   - 过度警告可能导致用户忽视真正的风险

2. **扫描性能**
   - 扫描整个文件系统可能影响启动性能
   - 需要平衡彻底性和效率

3. **通知频率**
   - 如果每次启动都发送，可能造成通知疲劳
   - 需要考虑去重或记忆机制

### 边界情况

1. **无世界可写目录**
   - 理想情况下，可能不发送此通知
   - 或者发送 `extra_count: 0` 和空 `sample_paths`

2. **大量受影响目录**
   - `extra_count` 可能很大
   - `sample_paths` 应该限制数量避免消息过大

3. **扫描部分失败**
   - `failed_scan: true` 但可能有部分结果
   - 需要决定是发送部分数据还是完全不发送

4. **权限变化**
   - 目录权限可能在运行时变化
   - 静态扫描结果可能过时

### 改进建议

1. **风险分级**
   - 添加 `risk_level` 字段区分高风险和低风险目录
   - 帮助用户优先处理重要问题

2. **可操作建议**
   - 添加 `recommendations` 字段提供具体建议
   - 如 "建议将工作目录移至 C:\\Users\\{username}\\Documents"

3. **扫描控制**
   - 添加配置选项控制扫描行为
   - 允许用户禁用或调整扫描范围

4. **持久化记忆**
   - 记住用户已确认的警告
   - 只在新增世界可写目录时再次警告

5. **实时监控**
   - 考虑监控目录权限变化
   - 在权限变为世界可写时实时通知

6. **跨平台统一**
   - 考虑为其他平台设计类似的警告机制
   - 如 Linux 上的 world-writable 目录、macOS 的特定限制

7. **详细报告**
   - 添加 `details_url` 指向详细文档
   - 帮助用户理解问题原因和解决方案
