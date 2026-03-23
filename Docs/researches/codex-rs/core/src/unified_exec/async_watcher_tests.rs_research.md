# async_watcher_tests.rs 深度研究文档

## 场景与职责

`async_watcher_tests.rs` 是 `async_watcher.rs` 的单元测试模块，专注于测试 UTF-8 分割逻辑的正确性。由于异步监控涉及并发和 I/O，单元测试主要覆盖可独立测试的纯函数逻辑。

## 功能点目的

测试 `split_valid_utf8_prefix_with_max` 函数的三个核心场景：
1. **ASCII 文本截断**：验证基本的分块逻辑
2. **UTF-8 多字节字符保护**：确保不在多字节字符中间截断
3. **非法 UTF-8 处理**：验证对非法字节的退化处理能力

## 具体技术实现

### 测试用例分析

```rust
// 测试1: ASCII 文本按 max_bytes 截断
fn split_valid_utf8_prefix_respects_max_bytes_for_ascii()
// 输入: b"hello word!", max=5
// 期望: 第一次返回 "hello", 剩余 " word!"
//       第二次返回 " word", 剩余 "!"

// 测试2: UTF-8 多字节字符（é = 2 bytes）
fn split_valid_utf8_prefix_avoids_splitting_utf8_codepoints()
// 输入: "ééé" (6 bytes), max=3
// 期望: 返回 "é" (2 bytes)，而非 3 bytes 导致字符截断

// 测试3: 非法 UTF-8 字节序列
fn split_valid_utf8_prefix_makes_progress_on_invalid_utf8()
// 输入: [0xff, b'a', b'b'], max=2
// 期望: 返回 [0xff]（单字节推进），剩余 "ab"
```

### 关键代码路径

- **被测函数**：`super::split_valid_utf8_prefix_with_max` (来自 async_watcher.rs)
- **测试框架**：标准 Rust test，使用 `pretty_assertions` 提供更清晰的 diff

## 依赖与外部交互

| 依赖 | 用途 |
|-----|------|
| `pretty_assertions::assert_eq` | 测试失败时显示结构化 diff |
| `super::*` | 访问被测模块的私有函数 |

## 风险、边界与改进建议

### 当前覆盖局限

1. **无并发测试**：未测试 `start_streaming_output` 的异步逻辑
2. **无集成测试**：未测试与 `HeadTailBuffer`、`Session` 的集成
3. **边界值缺失**：未测试 max_bytes=0、空输入等边界

### 改进建议

1. **添加边界测试**：
   ```rust
   #[test]
   fn split_with_zero_max_returns_none() { ... }
   
   #[test]
   fn split_empty_buffer_returns_none() { ... }
   ```

2. **添加更多 UTF-8 场景**：
   - 4 字节 UTF-8 字符（如 emoji）
   - 混合合法/非法序列
   - 不完整的 UTF-8 序列（如只收到字符的前几个字节）

3. **考虑集成测试**：在 `mod_tests.rs` 中已有更完整的集成测试覆盖
