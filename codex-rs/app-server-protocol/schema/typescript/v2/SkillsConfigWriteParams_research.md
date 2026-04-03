# SkillsConfigWriteParams 研究文档

## 1. 场景与职责

**SkillsConfigWriteParams** 是 app-server-protocol v2 协议中用于配置技能启用/禁用状态的请求参数类型。该类型在以下场景中使用：

- **技能管理界面**：当用户通过 TUI 或 GUI 界面启用或禁用特定技能时
- **技能配置持久化**：将用户的技能偏好设置保存到配置文件
- **动态技能控制**：在运行时切换技能的可用状态，无需重启应用

该类型属于 `skills/config/write` RPC 方法的请求参数，允许客户端修改特定技能路径的启用状态。

## 2. 功能点目的

该类型的核心目的是：

1. **精确标识技能**：通过 `path` 字段唯一标识要配置的技能（指向 SKILL.md 文件的路径）
2. **控制启用状态**：通过 `enabled` 布尔字段设置技能的启用/禁用状态
3. **支持持久化配置**：为技能配置提供标准化的写入接口

与 `SkillsListParams` 配合使用，可以实现完整的技能管理功能：先列出可用技能，再修改其启用状态。

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type SkillsConfigWriteParams = {
  path: string,
  enabled: boolean,
};
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsConfigWriteParams {
    pub path: PathBuf,
    pub enabled: bool,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `path` | `PathBuf` (string) | 技能配置文件的路径（指向 SKILL.md 或技能目录） |
| `enabled` | `bool` | 技能的启用状态，`true` 表示启用，`false` 表示禁用 |

### 序列化特性

- 使用 camelCase 命名规范进行序列化
- 路径字段使用 `PathBuf` 类型，支持跨平台路径处理
- 布尔值直接序列化，无默认值

## 4. 关键代码路径与文件引用

### 定义位置
- **主定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 第 3345-3348 行

### 协议注册
- **RPC 方法注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 339-342 行
  ```rust
  SkillsConfigWrite => "skills/config/write" {
      params: v2::SkillsConfigWriteParams,
      response: v2::SkillsConfigWriteResponse,
  }
  ```

### 相关文件
- **TypeScript 类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsConfigWriteParams.ts`
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/SkillsConfigWriteParams.json`
- **响应类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsConfigWriteResponse.ts`

### 使用场景
- **TUI 技能管理**: `codex-rs/tui/src/chatwidget/skills.rs` - 技能启用/禁用弹窗
- **TUI App Server**: `codex-rs/tui_app_server/src/chatwidget/skills.rs` - 并行实现

## 5. 依赖与外部交互

### 导入依赖

该类型本身无外部类型依赖，但作为请求参数参与以下交互：

### 上游依赖
- **技能元数据**: 与 `SkillMetadata` 类型关联，通过 `path` 字段引用技能
- **技能列表**: 通常在使用 `SkillsListResponse` 获取技能列表后调用

### 下游响应
- **SkillsConfigWriteResponse**: 写入操作的响应类型，返回实际生效的启用状态

### 相关类型关系

```
SkillsConfigWriteParams
    ├── path: PathBuf ───────> 引用 SkillMetadata.path
    └── enabled: bool
         
SkillsConfigWriteResponse
    └── effective_enabled: bool <── 返回实际生效状态
```

## 6. 风险、边界与改进建议

### 潜在风险

1. **路径有效性**
   - 风险：`path` 指向的技能可能不存在或已被删除
   - 建议：服务器应验证路径有效性并返回明确的错误信息

2. **权限问题**
   - 风险：用户可能尝试修改无权限访问的技能配置
   - 建议：根据技能 `scope`（User/Repo/System/Admin）进行权限校验

3. **并发修改**
   - 风险：多个客户端同时修改同一技能配置可能导致状态不一致
   - 建议：考虑添加版本控制或乐观锁机制

### 边界情况

1. **空路径处理**
   - 空路径应被视为无效请求，返回验证错误

2. **相对路径**
   - 路径解析应相对于合适的基础目录（如 cwd 或项目根目录）

3. **系统技能保护**
   - System 和 Admin 范围的技能可能需要额外的保护，防止误禁用

### 改进建议

1. **添加配置理由字段**
   ```rust
   pub struct SkillsConfigWriteParams {
       pub path: PathBuf,
       pub enabled: bool,
       pub reason: Option<String>, // 可选：记录修改原因
   }
   ```

2. **批量配置支持**
   - 当前仅支持单个技能配置，可考虑添加批量配置接口

3. **配置作用域限定**
   - 添加可选的 `scope` 字段，明确配置应用的作用域

4. **事务支持**
   - 对于关联技能的配置，支持原子性批量更新

### 测试覆盖

- **单元测试**: 验证序列化/反序列化正确性
- **集成测试**: 验证完整的配置写入流程
- **边界测试**: 测试无效路径、权限不足等异常情况
