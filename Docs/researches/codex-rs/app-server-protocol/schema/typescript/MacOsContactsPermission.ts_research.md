# MacOsContactsPermission.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`MacOsContactsPermission` 是用于控制 Codex 在 macOS 系统上访问用户通讯录权限的枚举类型。它定义了三种权限级别，用于在沙箱环境中精细控制 AI 代理对 macOS 系统通讯录的访问能力。

**使用场景：**
- 在 macOS 平台上运行 Codex CLI 或 TUI 时，需要访问用户的通讯录数据
- 配置沙箱权限扩展（`MacOsSeatbeltProfileExtensions`）时指定通讯录访问级别
- 在 `PermissionProfile` 中作为 macOS 特定权限的一部分

**职责：**
- 提供标准化的权限级别定义（无访问、只读、读写）
- 支持序列化和反序列化（snake_case 格式）
- 支持类型导出到 TypeScript 用于前端/客户端类型安全

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **安全控制**：限制 AI 代理对敏感用户数据（通讯录）的访问范围，遵循最小权限原则
2. **权限分级**：提供三个明确的权限级别：
   - `none`：完全禁止访问通讯录（默认安全级别）
   - `read_only`：允许读取通讯录但不允许修改
   - `read_write`：允许读取和修改通讯录
3. **配置标准化**：在配置文件中统一表示通讯录权限，便于用户理解和配置

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/models.rs` 第 114-134 行）：

```rust
#[derive(
    Debug,
    Clone,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
    Default,
    Hash,
    Serialize,
    Deserialize,
    JsonSchema,
    TS,
)]
#[serde(rename_all = "snake_case")]
pub enum MacOsContactsPermission {
    #[default]
    None,
    ReadOnly,
    ReadWrite,
}
```

**TypeScript 生成定义**（位于 `app-server-protocol/schema/typescript/MacOsContactsPermission.ts`）：

```typescript
export type MacOsContactsPermission = "none" | "read_only" | "read_write";
```

**关键实现细节：**
- 使用 `#[serde(rename_all = "snake_case")]` 确保 JSON 序列化使用下划线格式
- 实现 `PartialOrd` 和 `Ord` trait，支持权限级别的比较（None < ReadOnly < ReadWrite）
- 默认值为 `None`，遵循安全优先原则
- 通过 `ts-rs` 的 `TS` derive 宏自动生成 TypeScript 类型

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/models.rs`（第 114-134 行）：主要定义

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/MacOsContactsPermission.ts`

**使用位置：**
- `MacOsSeatbeltProfileExtensions` 结构体（models.rs 第 193-210 行）包含此类型
- `PermissionProfile` 通过 `macos` 字段间接使用
- 测试代码（models.rs 第 1648-1651 行）验证权限顺序

**相关类型：**
- `MacOsPreferencesPermission`：类似的权限枚举，用于 macOS 偏好设置
- `MacOsAutomationPermission`：用于 macOS 自动化权限
- `MacOsSeatbeltProfileExtensions`：包含所有 macOS 沙箱扩展权限

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

**序列化格式：**
- JSON 中使用 snake_case： `"none"`, `"read_only"`, `"read_write"`

**与 macOS Seatbelt 沙箱的交互：**
- 该权限最终会被转换为 macOS Seatbelt 配置文件中的规则
- 影响 `codex-execpolicy` 和沙箱执行引擎的权限决策

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **权限提升风险**：从 `read_only` 提升到 `read_write` 可能导致数据被意外修改或删除
2. **隐私泄露**：即使是只读访问也可能暴露敏感联系人信息
3. **默认权限**：虽然默认是 `None`，但用户可能在不了解风险的情况下更改配置

**边界情况：**
1. 权限比较依赖于 `Ord` trait 的实现顺序，需要确保顺序与权限严格性一致
2. 与 `MacOsPreferencesPermission` 不同，后者默认是 `ReadOnly`（因为需要保持 cf prefs 工作）

**改进建议：**
1. **添加文档注释**：在 Rust 定义中添加更详细的文档说明，解释每个权限级别的具体含义和安全影响
2. **权限警告**：当用户设置 `read_write` 时，TUI 应该显示警告提示
3. **审计日志**：记录通讯录访问操作，便于安全审计
4. **考虑添加 `ReadOnly` 为默认**：目前默认是 `None`，但考虑到某些功能可能需要读取通讯录，可以考虑是否将默认改为 `ReadOnly`（需要安全评估）
5. **与系统权限集成**：考虑与 macOS 系统级的通讯录权限提示集成，提供双重确认
