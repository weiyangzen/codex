# osRelease.ts 研究文档

## 场景与职责

`osRelease.ts` 负责解析 Linux 系统的 `/etc/os-release` 文件，这是现代 Linux 发行版遵循 systemd 规范的标准标识文件。该模块为 `bashSelection.ts` 提供必要的操作系统元数据，以支持精确的 Bash 变体匹配。

**核心职责：**
1. 读取 `/etc/os-release` 文件内容
2. 解析 KEY="value" 格式的配置项
3. 规范化数据（小写化、去引号、分割数组）
4. 提供容错机制（文件不存在时返回空值而非抛出）

## 功能点目的

### 1. `parseOsRelease(contents)` - 内容解析器

**目的：** 将 `/etc/os-release` 的原始文本转换为结构化的 `OsReleaseInfo` 对象。

**解析规则：**
- **行过滤**：空行被忽略（`filter(Boolean)`）
- **键值分割**：按第一个 `=` 分割，限制为 2 部分（`split("=", 2)`）
- **键规范化**：转为小写（`ID` → `id`）
- **值去引号**：移除首尾的 `"`（`VERSION_ID="24.04"` → `24.04`）
- **数组分割**：`ID_LIKE` 按空白字符分割为数组

**示例转换：**
```
ID="ubuntu"              →  info.id = "ubuntu"
ID_LIKE="debian"         →  info.idLike = ["debian"]
VERSION_ID="24.04"       →  info.versionId = "24.04"
SUPPORT_URL="..."        →  忽略（未使用字段）
```

### 2. `readOsRelease(pathname)` - 文件读取器

**目的：** 提供安全的文件读取接口，处理文件不存在的情况。

**容错设计：**
- 文件存在且可读 → 解析并返回 `OsReleaseInfo`
- 文件不存在或不可读 → 返回空对象 `{ id: "", idLike: [], versionId: "" }`
- 使用 `try/catch` 捕获所有 `readFileSync` 异常

**默认路径：** `/etc/os-release`（systemd 标准路径）

## 具体技术实现

### 解析算法详解

```typescript
const lines = contents.split("\n").filter(Boolean);
// 1. 按行分割，过滤空行

const [rawKey, rawValue] = line.split("=", 2);
// 2. 限制分割为 2 部分，避免值中包含 = 被错误分割

const key = rawKey.toLowerCase();
// 3. 键名统一小写，实现大小写不敏感

const value = rawValue.replace(/^"/, "").replace(/"$/, "");
// 4. 移除首尾双引号（简单实现，不支持转义引号）

const idLike = (info.id_like || "")
  .split(/\s+/)      // 按任意空白分割
  .map(item => item.trim().toLowerCase())
  .filter(Boolean);  // 过滤空字符串
// 5. ID_LIKE 规范化："CentOS   Rocky" → ["centos", "rocky"]
```

### 数据结构

```typescript
// 原始文件格式（示例）
NAME="Ubuntu"
VERSION="24.04.1 LTS (Noble Numbat)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 24.04.1 LTS"
VERSION_ID="24.04"

// 解析后结构
{
  id: "ubuntu",
  idLike: ["debian"],
  versionId: "24.04"
}
```

### 字段选择理由

| 字段 | 来源 | 用途 |
|------|------|------|
| `id` | `ID` | 主要发行版标识（如 ubuntu、debian） |
| `idLike` | `ID_LIKE` | 派生关系（如 ubuntu → debian，rocky → rhel） |
| `versionId` | `VERSION_ID` | 版本匹配（如 24.04、12） |

**未使用但可能相关的字段：**
- `NAME`：人类可读名称（含空格，不适合匹配）
- `VERSION`：完整版本字符串（含代号，格式不统一）
- `PRETTY_NAME`：显示用名称（本地化，不可靠）

## 关键代码路径与文件引用

### 内部依赖

| 导入 | 来源 | 用途 |
|------|------|------|
| `OsReleaseInfo` | `./types` | 返回类型定义 |

### Node.js 内置模块

| 模块 | 用途 |
|------|------|
| `node:fs` | `readFileSync` 同步文件读取 |

### 消费者

- **`src/index.ts`**：调用 `readOsRelease()` 获取 Linux OS 信息
- **`src/bashSelection.ts`**：接收 `OsReleaseInfo` 进行变体匹配

### 测试覆盖

- **`tests/osRelease.test.ts`**：
  - 基本字段解析
  - 缺失字段处理
  - `id_like` 规范化（空白分割、大小写）

## 依赖与外部交互

### 文件系统接口

**读取路径：** `/etc/os-release`

**文件格式规范：** 遵循 systemd `os-release` 标准
- 纯文本文件，UTF-8 编码
- 每行 `KEY=value` 或 `KEY="value"` 格式
- `#` 开头的注释行（当前实现未处理，会被尝试解析）

**权限要求：**
- 通常 `/etc/os-release` 为 644 权限，任意用户可读
- 容器环境中可能不存在或路径不同

### 容器/特殊环境考量

| 环境 | 行为 | 影响 |
|------|------|------|
| Docker 容器 | 继承宿主或基础镜像的 os-release | 可能匹配基础镜像而非宿主 |
| chroot | 读取 chroot 内的文件 | 符合预期 |
| WSL | 读取 Linux 发行版的文件 | 正确识别 WSL 发行版 |
| 非 systemd 发行版 | 可能不存在或格式不同 | 回退到空值 |

## 风险、边界与改进建议

### 已知风险

1. **注释行处理缺陷**
   - 当前实现不识别 `#` 开头的注释行
   - 若注释中包含 `=`，会被错误解析
   - 实际 `/etc/os-release` 通常无注释，风险较低

2. **引号处理不完整**
   - 仅处理简单双引号包裹
   - 不支持：
     - 单引号（`'value'`）
     - 嵌套/转义引号（`"say \"hello\""`）
     - 无引号但含特殊字符的值

3. **空值与缺失值混淆**
   - `VERSION_ID=`（显式空）和缺失 `VERSION_ID` 都映射到 `""`
   - 调用方无法区分"未知版本"和"无版本概念"

4. **编码问题**
   - 使用 `utf8` 编码读取
   - 非 UTF-8 系统（如某些嵌入式 Linux）可能出现乱码

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 文件不存在 | 返回空对象 | ✅ 正确 |
| 文件权限不足 | 返回空对象 | ✅ 正确（但可能静默失败） |
| 空文件 | 返回空对象 | ✅ 正确 |
| 键无值（`ID=`） | 值为空字符串 | ⚠️ 可接受 |
| 值含多个等号（`A=b=c`） | 正确分割为 `['A', 'b=c']` | ✅ 正确 |
| `ID_LIKE` 为空 | 返回 `[]` | ✅ 正确 |
| `ID_LIKE=""` | 返回 `[]` | ✅ 正确 |
| 大小写混合（`Id=Ubuntu`） | 键转为小写 | ✅ 正确 |

### 改进建议

1. **添加注释支持**
   ```typescript
   const lines = contents
     .split("\n")
     .filter(line => line && !line.startsWith("#"));
   ```

2. **更健壮的引号处理**
   ```typescript
   // 支持单双引号，保留内部引号
   const value = rawValue
     .replace(/^["']/, "")
     .replace(/["']$/, "");
   ```

3. **区分空值与缺失值**
   ```typescript
   export type OsReleaseInfo = {
     id: string;
     idLike: Array<string>;
     versionId: string | null;  // null 表示字段缺失
   };
   ```

4. **添加调试日志**
   ```typescript
   export function readOsRelease(
     pathname = "/etc/os-release",
     debug = process.env.DEBUG_OS_RELEASE === "1"
   ): OsReleaseInfo {
     try {
       const contents = readFileSync(pathname, "utf8");
       if (debug) {
         console.error(`[osRelease] Read ${pathname}:`);
         console.error(contents);
       }
       return parseOsRelease(contents);
     } catch (err) {
       if (debug) {
         console.error(`[osRelease] Failed to read ${pathname}:`, err);
       }
       return { id: "", idLike: [], versionId: "" };
     }
   }
   ```

5. **支持备用路径**
   ```typescript
   const FALLBACK_PATHS = [
     "/etc/os-release",
     "/usr/lib/os-release",  // 某些发行版的备用位置
   ];
   ```

6. **验证解析结果**
   ```typescript
   if (!info.id && !info.idLike.length) {
     console.warn(`[osRelease] No valid ID found in ${pathname}`);
   }
   ```

7. **性能优化**
   - 当前使用同步读取（`readFileSync`）
   - 考虑添加简单缓存，避免多次读取同一文件
   - 但在 CLI 单次运行场景中，当前实现已足够

### 测试缺口

- 未测试注释行处理
- 未测试单引号值
- 未测试文件权限错误（模拟困难）
- 未测试大文件性能（实际文件通常 < 1KB，非问题）
