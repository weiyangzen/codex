# CommandExecTerminalSize.ts 研究文档

## 场景与职责

`CommandExecTerminalSize.ts` 定义了PTY（伪终端）会话的终端尺寸类型，以字符单元格为单位。这是配置PTY初始大小和调整现有PTY尺寸的基础类型。

## 功能点目的

1. **终端尺寸定义**: 以字符行数和列数定义终端大小
2. **PTY配置**: 用于`CommandExecParams`设置初始PTY大小
3. **动态调整**: 用于`CommandExecResizeParams`调整运行中的PTY
4. **兼容性**: 与Unix终端尺寸模型（TIOCGWINSZ）保持一致

## 具体技术实现

### 数据结构

```typescript
/**
 * PTY size in character cells for `command/exec` PTY sessions.
 */
export type CommandExecTerminalSize = { 
  /**
   * Terminal height in character cells.
   */
  rows: number, 
  /**
   * Terminal width in character cells.
   */
  cols: number, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `rows` | `number` | 终端高度（字符行数） |
| `cols` | `number` | 终端宽度（字符列数） |

### 典型值

| 场景 | rows | cols |
|------|------|------|
| 标准终端 | 24 | 80 |
| 大终端 | 50 | 120 |
| 全屏 | 60 | 200 |

## 关键代码路径与文件引用

### 生成源

- `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的命令执行模块

### 引用关系

**被引用方**:
- `CommandExecParams.ts` - 作为`size`字段类型
- `CommandExecResizeParams.ts` - 作为`size`字段类型

**引用**: 无

### 相关文件

```
codex-rs/app-server-protocol/schema/typescript/v2/
├── CommandExecTerminalSize.ts       # 本文件
├── CommandExecParams.ts             # 初始PTY参数
├── CommandExecResizeParams.ts       # 调整参数
└── ...
```

## 依赖与外部交互

### 使用场景

```
启动PTY会话
        ↓
设置初始尺寸
        ↓
┌───────┴───────┐
↓               ↓
24x80        自定义尺寸
(默认)       (用户指定)
        ↓
运行终端应用
        ↓
窗口大小变化
        ↓
发送 resize 请求
        ↓
更新尺寸
```

### 与SIGWINCH的关系

```
设置/调整尺寸
        ↓
内核更新窗口大小
        ↓
发送 SIGWINCH 给前台进程组
        ↓
应用响应尺寸变化
(vim重绘, htop调整列宽)
```

## 风险、边界与改进建议

### 潜在风险

1. **零尺寸**: rows或cols为0可能导致应用错误
2. **超大尺寸**: 过大的尺寸可能导致内存问题
3. **非整数**: 浮点数尺寸无意义但类型允许

### 边界情况

1. **最小尺寸**: 某些应用需要最小尺寸（如vim需要至少2行）
2. **最大尺寸**: 系统可能有最大终端尺寸限制
3. **比例变化**: 尺寸变化可能导致布局问题

### 改进建议

1. **添加验证**: 使用 branded type 确保有效值
   ```typescript
   type ValidRows = number & { __brand: 'ValidRows' };
   type ValidCols = number & { __brand: 'ValidCols' };
   
   export type CommandExecTerminalSize = { 
     rows: ValidRows;
     cols: ValidCols;
   };
   
   function createTerminalSize(rows: number, cols: number): CommandExecTerminalSize {
     if (rows < 1 || rows > 9999) throw new Error('Invalid rows');
     if (cols < 1 || cols > 9999) throw new Error('Invalid cols');
     return { rows: rows as ValidRows, cols: cols as ValidCols };
   }
   ```

2. **添加像素尺寸**: 支持图形应用
   ```typescript
   export type CommandExecTerminalSize = { 
     rows: number;
     cols: number;
     pixelWidth?: number;   // 像素宽度
     pixelHeight?: number;  // 像素高度
   };
   ```

3. **添加默认值常量**
   ```typescript
   export const DEFAULT_TERMINAL_SIZE: CommandExecTerminalSize = {
     rows: 24,
     cols: 80
   };
   ```

### 使用示例

```typescript
// 创建终端尺寸
const size: CommandExecTerminalSize = {
  rows: 30,
  cols: 100
};

// 用于PTY启动
const ptyParams: CommandExecParams = {
  command: ['bash'],
  tty: true,
  size: size
};

// 用于调整尺寸
const resizeParams: CommandExecResizeParams = {
  processId: 'pty-123',
  size: {
    rows: 40,
    cols: 120
  }
};

// 从实际终端获取尺寸
function getTerminalSize(): CommandExecTerminalSize {
  return {
    rows: process.stdout.rows || 24,
    cols: process.stdout.columns || 80
  };
}
```
