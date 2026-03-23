# osRelease.test.ts 研究文档

## 场景与职责

`osRelease.test.ts` 是 shell-tool-mcp 项目中负责测试 Linux 操作系统发行版信息解析功能的测试文件。该模块的核心职责是解析 `/etc/os-release` 文件的内容，提取关键的系统识别信息（发行版 ID、版本号、相关发行版家族等），为后续的 Bash 二进制文件选择提供决策依据。

在 Codex CLI 的沙箱化 shell 执行架构中，准确识别宿主 Linux 发行版至关重要，因为：
1. 不同发行版使用不同的 C 库版本（glibc/musl）
2. 预编译的 Bash 二进制文件需要与宿主系统的 ABI 兼容
3. 衍生发行版（如 Rocky Linux、AlmaLinux）需要正确识别其父发行版（RHEL/CentOS）

## 功能点目的

测试文件覆盖 `parseOsRelease` 函数的三个核心功能：

1. **基本字段解析** - 从 `/etc/os-release` 格式内容中提取 `ID`、`ID_LIKE`、`VERSION_ID` 字段
2. **缺失字段处理** - 当关键字段不存在时返回默认值（空字符串/空数组）
3. **ID_LIKE 标准化** - 将空格分隔的发行版家族字符串规范化为小写数组

## 具体技术实现

### 测试框架配置

- **测试框架**: Jest + ts-jest
- **配置文件**: `jest.config.cjs`
- **TypeScript 配置**: `tsconfig.json`（严格模式启用）

### /etc/os-release 文件格式

`/etc/os-release` 是 systemd 引入的标准文件，采用简单的 `KEY=value` 格式：

```bash
# 示例：Ubuntu 24.04
ID="ubuntu"
ID_LIKE="debian"
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04.1 LTS"
```

关键字段说明：
- `ID` - 发行版唯一标识符（小写，如 "ubuntu"、"centos"）
- `ID_LIKE` - 相关发行版家族（空格分隔，如 "rhel fedora"）
- `VERSION_ID` - 版本号（如 "24.04"、"9"）

### 解析算法实现

被测代码位于 `src/osRelease.ts`：

```typescript
export function parseOsRelease(contents: string): OsReleaseInfo {
  // 1. 按行分割并过滤空行
  const lines = contents.split("\n").filter(Boolean);
  const info: Record<string, string> = {};
  
  // 2. 逐行解析 KEY=value 格式
  for (const line of lines) {
    const [rawKey, rawValue] = line.split("=", 2);
    if (!rawKey || rawValue === undefined) continue;
    
    const key = rawKey.toLowerCase();
    // 去除首尾引号（处理 ID="ubuntu" 和 ID=ubuntu 两种格式）
    const value = rawValue.replace(/^"/, "").replace(/"$/, "");
    info[key] = value;
  }
  
  // 3. 标准化 ID_LIKE 为数组
  const idLike = (info.id_like || "")
    .split(/\s+/)           // 按空白字符分割
    .map(item => item.trim().toLowerCase())
    .filter(Boolean);       // 过滤空字符串
  
  // 4. 返回结构化数据
  return {
    id: (info.id || "").toLowerCase(),
    idLike,
    versionId: info.version_id || "",
  };
}
```

### 关键测试用例分析

#### 测试用例1：基本字段解析

```typescript
const contents = `ID="ubuntu"
ID_LIKE="debian"
VERSION_ID=24.04
OTHER=ignored`;

const info = parseOsRelease(contents);
expect(info).toEqual({
  id: "ubuntu",
  idLike: ["debian"],
  versionId: "24.04",
});
```

验证点：
- 正确处理带引号的值（`"ubuntu"` → `"ubuntu"`）
- 正确处理无引号的值（`24.04` → `"24.04"`）
- 忽略未定义字段（`OTHER` 被忽略）

#### 测试用例2：缺失字段处理

```typescript
const contents = "SOMETHING=else";
const info = parseOsRelease(contents);
expect(info).toEqual({ id: "", idLike: [], versionId: "" });
```

验证点：
- 缺失 `ID` 时返回空字符串
- 缺失 `ID_LIKE` 时返回空数组
- 缺失 `VERSION_ID` 时返回空字符串

#### 测试用例3：ID_LIKE 标准化

```typescript
const contents = `ID="rhel"
ID_LIKE="CentOS   Rocky"`;

const info = parseOsRelease(contents);
expect(info.idLike).toEqual(["centos", "rocky"]);
```

验证点：
- 多个空格被正确处理（`"CentOS   Rocky"`）
- 大小写转换为小写（`"CentOS"` → `"centos"`）
- 结果按数组形式返回

### 数据结构定义

```typescript
// src/types.ts
interface OsReleaseInfo {
  id: string;           // 发行版 ID（小写）
  idLike: string[];     // 相关发行版家族（小写数组）
  versionId: string;    // 版本号（原始字符串）
}
```

## 关键代码路径与文件引用

### 文件依赖关系

```
osRelease.test.ts
  ├── ../src/osRelease (被测模块)
  │       ├── parseOsRelease()  # 解析函数（纯函数，可测试）
  │       └── readOsRelease()   # 文件读取包装（未测试）
  └── ../src/types (类型定义)
          └── OsReleaseInfo
```

### 调用链

```
index.ts (MCP 服务器入口)
  └── readOsRelease("/etc/os-release")
        └── parseOsRelease(fileContents)
              └── 返回 OsReleaseInfo
                    └── 被 resolveBashPath() 使用
                          └── selectLinuxBash()
```

### 相关文件

| 文件路径 | 职责 | 与本测试关系 |
|---------|------|-------------|
| `src/osRelease.ts` | OS 信息解析实现 | 被测代码 |
| `src/types.ts` | 类型定义 | 依赖 |
| `src/bashSelection.ts` | Bash 选择逻辑 | 使用解析结果 |
| `tests/bashSelection.test.ts` | Bash 选择测试 | 相关测试 |

## 依赖与外部交互

### 内部依赖

| 模块 | 导入内容 | 用途 |
|------|---------|------|
| `../src/osRelease` | `parseOsRelease` | 被测函数 |

### 外部系统交互

本测试为纯单元测试，**不依赖外部系统**：
- 不读取真实的 `/etc/os-release` 文件
- 不依赖 Node.js 文件系统 API
- 所有测试通过字符串输入进行验证

被测模块中的 `readOsRelease()` 函数（未在测试中覆盖）负责实际的文件系统访问：

```typescript
export function readOsRelease(pathname = "/etc/os-release"): OsReleaseInfo {
  try {
    const contents = readFileSync(pathname, "utf8");
    return parseOsRelease(contents);
  } catch {
    // 文件不存在或读取失败时返回空值
    return { id: "", idLike: [], versionId: "" };
  }
}
```

## 风险、边界与改进建议

### 当前风险点

1. **引号处理不完整**
   - 当前仅处理首尾双引号：`replace(/^"/, "").replace(/"$/, "")`
   - 风险：单引号（`ID='ubuntu'`）或嵌套引号无法正确处理
   - 实际 `/etc/os-release` 规范允许单引号

2. **特殊字符未转义**
   - 不处理转义序列（如 `"` 或 `\`）
   - 示例：`PRETTY_NAME="Ubuntu \"LTS\""` 会被错误解析

3. **行格式容错性**
   - 当前要求严格的 `KEY=value` 格式
   - 不处理注释行（以 `#` 开头）
   - 不处理行内空格（`ID = ubuntu`）

4. **测试覆盖不完整**
   - 未测试 `readOsRelease()` 的文件系统交互
   - 未测试空字符串输入
   - 未测试极端长的值

### 边界情况分析

| 场景 | 当前行为 | 潜在问题 |
|------|---------|---------|
| `ID=""`（空值带引号） | `id: ""` | 与缺失字段无法区分 |
| `ID_LIKE=""` | `idLike: []` | 正确 |
| 行格式为 `KEY=`（无值） | 被忽略（`rawValue === undefined` 为 false，值为空字符串） | 实际应解析为空字符串 |
| 行格式为 `=value`（无键） | 被忽略 | 正确 |
| 多行值（续行） | 无法处理 | 部分发行版可能有此格式 |

### 改进建议

1. **增强引号处理**
   ```typescript
   // 建议支持单引号和双引号
   function unquote(value: string): string {
     if ((value.startsWith('"') && value.endsWith('"')) ||
         (value.startsWith("'") && value.endsWith("'"))) {
       return value.slice(1, -1).replace(/\\(.)/g, '$1');
     }
     return value;
   }
   ```

2. **添加注释支持**
   ```typescript
   const lines = contents
     .split("\n")
     .filter(line => line && !line.startsWith("#"));
   ```

3. **完善测试覆盖**
   ```typescript
   // 建议添加的测试用例
   - 单引号值: `ID='ubuntu'`
   - 空值: `ID=""`
   - 转义字符: `PRETTY_NAME="Ubuntu \"LTS\""`
   - 注释行: `# This is a comment`
   - 多空格分隔: `ID_LIKE="debian   ubuntu"`
   ```

4. **性能优化**
   - 当前实现为同步解析，对于大文件可考虑流式处理
   - 但实际 `/etc/os-release` 通常很小（<1KB），非关键路径

5. **类型安全增强**
   - 考虑使用 `zod` 或 `io-ts` 进行运行时类型验证
   - 确保返回字段符合预期格式

### 相关规范参考

- [ freedesktop.org os-release 规范](https://www.freedesktop.org/software/systemd/man/latest/os-release.html)
- [systemd 文档](https://systemd.io/) - 包含 `/etc/os-release` 的完整格式说明

### 与 bashSelection 的协作

`osRelease` 模块的输出直接作为 `bashSelection` 模块的输入：

```typescript
// 数据流
/etc/os-release (文件)
  └── readOsRelease()
        └── parseOsRelease()
              └── OsReleaseInfo { id, idLike, versionId }
                    └── selectLinuxBash()
                          └── 匹配 LINUX_BASH_VARIANTS
                                └── 返回合适的 Bash 变体
```

这种分离设计的好处：
- `parseOsRelease` 是纯函数，易于单元测试
- `readOsRelease` 处理 IO，可在上层进行错误处理
- 测试时可以注入模拟数据，无需真实文件系统
