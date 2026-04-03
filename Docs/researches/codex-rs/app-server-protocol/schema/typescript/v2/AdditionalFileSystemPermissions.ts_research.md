# AdditionalFileSystemPermissions.ts 研究文档

## 1. 场景与职责

`AdditionalFileSystemPermissions` 定义了**额外的文件系统权限配置**，用于在标准沙箱策略之外，为特定操作授予额外的文件读写权限。

### 使用场景
- **权限请求**: 当 Agent 需要访问沙箱外的文件时，向用户请求额外权限
- **动态权限授予**: 在会话期间根据用户需求动态扩展文件访问范围
- **项目特定配置**: 为特定项目或工作流配置额外的可读/可写路径
- **安全策略**: 细粒度控制 Agent 可以访问的文件系统范围

### 职责
- 定义额外的可读路径列表（`read`）
- 定义额外的可写路径列表（`write`）
- 作为权限请求和授予的数据载体

---

## 2. 功能点目的

### 2.1 细粒度文件权限

```typescript
export type AdditionalFileSystemPermissions = { 
  read: Array<AbsolutePathBuf> | null,   // 额外可读路径
  write: Array<AbsolutePathBuf> | null,  // 额外可写路径
};
```

### 2.2 字段语义

| 字段 | 类型 | 说明 |
|------|------|------|
| `read` | `Array<AbsolutePathBuf> \| null` | 允许读取的绝对路径列表 |
| `write` | `Array<AbsolutePathBuf> \| null` | 允许写入的绝对路径列表 |

### 2.3 设计意图

1. **最小权限原则**: 默认沙箱限制严格，仅在需要时授予额外权限
2. **路径隔离**: 使用 `AbsolutePathBuf` 确保路径规范化，防止路径遍历攻击
3. **读写分离**: 分别控制读和写权限，支持只读访问场景

---

## 3. 具体技术实现

### 3.1 数据结构

```typescript
interface AdditionalFileSystemPermissions {
  read: string[] | null;   // AbsolutePathBuf 是 string 的别名
  write: string[] | null;
}
```

### 3.2 依赖类型: AbsolutePathBuf

```typescript
// AbsolutePathBuf.ts
/**
 * A path that is guaranteed to be absolute and normalized (though it is not
 * guaranteed to be canonicalized or exist on the filesystem).
 */
export type AbsolutePathBuf = string;
```

### 3.3 Rust 源类型

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AdditionalFileSystemPermissions {
    pub read: Option<Vec<AbsolutePathBuf>>,
    pub write: Option<Vec<AbsolutePathBuf>>,
}

// 与 CoreFileSystemPermissions 的转换
impl From<CoreFileSystemPermissions> for AdditionalFileSystemPermissions {
    fn from(value: CoreFileSystemPermissions) -> Self {
        Self {
            read: value.read,
            write: value.write,
        }
    }
}
```

### 3.4 在权限系统中的位置

```
PermissionProfile
  ├── network: NetworkPermissions
  ├── file_system: FileSystemPermissions  ← AdditionalFileSystemPermissions 映射自此
  └── macos: MacOsPermissions
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（约第 1036-1057 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AdditionalFileSystemPermissions.ts` | 生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/typescript/AbsolutePathBuf.ts` | 路径类型定义 |

### 4.2 类型依赖图

```
AdditionalFileSystemPermissions.ts
  └── AbsolutePathBuf.ts (../AbsolutePathBuf)
```

### 4.3 使用位置

| 类型 | 用途 |
|------|------|
| `RequestPermissionProfile` | 权限请求时的文件系统部分 |
| `AdditionalPermissionProfile` | 完整的额外权限配置 |
| `PermissionsRequestApprovalParams` | 权限请求审批参数 |

### 4.4 权限请求流程

```
┌─────────┐    ┌─────────────┐    ┌─────────┐    ┌─────────────┐
│  Agent  │───►│  Sandbox    │───►│  User   │───►│   Grant     │
│ Request │    │  Denied     │    │ Prompt  │    │  Permission │
└─────────┘    └─────────────┘    └─────────┘    └──────┬──────┘
                                                        │
                                                        ▼
┌─────────┐    ┌─────────────┐    ┌─────────┐    ┌─────────────┐
│ Execute │◄───│  Update     │◄───│  Server │◄───│ Additional  │
│  Action │    │  Sandbox    │    │  Notify │    │ FileSystem  │
│         │    │  Policy     │    │         │    │ Permissions │
└─────────┘    └─────────────┘    └─────────┘    └─────────────┘
```

---

## 5. 依赖与外部交互

### 5.1 类型依赖

```typescript
import type { AbsolutePathBuf } from "../AbsolutePathBuf";
```

### 5.2 外部系统交互

```
┌─────────────────────────────────────────────────────────────┐
│                        Sandbox Layer                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐      ┌─────────────────────────────┐  │
│  │  Seatbelt (macOS)│      │  Windows Sandbox / WSL      │  │
│  │  Landlock (Linux)│      │  seccomp (Linux)            │  │
│  └────────┬────────┘      └─────────────┬───────────────┘  │
│           │                             │                    │
│           └──────────────┬──────────────┘                    │
│                          ▼                                  │
│           ┌─────────────────────────┐                       │
│           │ AdditionalFileSystem    │                       │
│           │ Permissions Applied     │                       │
│           └─────────────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 序列化示例

**基本配置:**
```json
{
  "read": ["/home/user/documents", "/home/user/projects"],
  "write": ["/home/user/workspace"]
}
```

**只读权限:**
```json
{
  "read": ["/etc/config"],
  "write": null
}
```

**完全权限（危险）:**
```json
{
  "read": ["/"],
  "write": ["/"]
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 路径遍历 | 恶意路径如 `/safe/../../../etc/passwd` | `AbsolutePathBuf` 规范化处理 |
| 符号链接逃逸 | 通过 symlink 访问受限路径 | 沙箱层解析和验证 symlink |
| 权限扩散 | 过度授权导致安全边界失效 | UI 明确展示授权范围 |
| 竞态条件 | 授权后路径被替换为敏感文件 | 沙箱使用文件描述符而非路径 |

### 6.2 边界情况

1. **空数组**: `read: []` 表示无额外读权限，与 `null` 语义不同
2. **重叠路径**: `read: ["/a"]` 和 `write: ["/a/b"]` 的权限交集
3. **不存在的路径**: 授权时路径不存在，后续创建后的处理
4. **路径类型**: 文件 vs 目录的权限区别

### 6.3 改进建议

1. **添加递归选项**: 控制是否包含子目录
   ```typescript
   export type FileSystemPermissionEntry = {
     path: AbsolutePathBuf;
     recursive: boolean;
   };
   
   export type AdditionalFileSystemPermissions = { 
     read: Array<FileSystemPermissionEntry> | null,
     write: Array<FileSystemPermissionEntry> | null,
   };
   ```

2. **添加排除模式**: 支持在授权路径中排除特定子路径
   ```typescript
   exclude: Array<AbsolutePathBuf>;
   ```

3. **权限有效期**: 支持临时授权
   ```typescript
   expiresAt?: number;  // Unix timestamp
   ```

4. **操作审计**: 记录权限使用情况
   ```typescript
   audit?: boolean;  // 是否记录该权限的使用日志
   ```

5. **路径验证**: 添加路径存在性和类型验证
   ```typescript
   validatePaths?: boolean;  // 授权时验证路径存在
   ```

### 6.4 测试建议

- 路径规范化验证（`..`, `.`, `~` 等）
- 符号链接处理
- 权限边界测试（刚好在边界内/外）
- 并发访问场景
- 路径删除后的行为
- 跨平台路径格式（Windows vs Unix）
