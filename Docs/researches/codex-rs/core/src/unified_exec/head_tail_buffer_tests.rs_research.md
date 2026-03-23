# head_tail_buffer_tests.rs 深度研究文档

## 场景与职责

`head_tail_buffer_tests.rs` 是 `HeadTailBuffer` 的单元测试模块，全面验证缓冲区的预算管理、块处理和边界行为。

## 功能点目的

测试覆盖以下核心场景：
1. **预算超额处理**：验证头部+尾部保留、中间丢弃的语义
2. **零预算场景**：max_bytes=0 时的行为
3. **最小预算场景**：max_bytes=1 时的尾部保留
4. **状态重置**：drain_chunks 后缓冲区完全重置
5. **超大块处理**：单块超过 tail_budget 时的裁剪
6. **多块填充**：跨多个小块逐步填满 head 和 tail

## 具体技术实现

### 测试用例详解

```rust
// 测试1: 预算超额时保留前缀和后缀
fn keeps_prefix_and_suffix_when_over_budget()
// 预算: 10 bytes
// 输入1: "0123456789" (10 bytes) → 无丢弃
// 输入2: "ab" (2 bytes) → 总 12 bytes，超出 2 bytes
// 期望: 保留 "01234" + "89ab"，中间 "567" 被丢弃

// 测试2: 零预算丢弃所有
fn max_bytes_zero_drops_everything()
// 预算: 0
// 输入: "abc" → 全部丢弃
// 验证: retained_bytes=0, omitted_bytes=3, to_bytes=""

// 测试3: 最小预算只保留最后1字节
fn head_budget_zero_keeps_only_last_byte_in_tail()
// 预算: 1 (head=0, tail=1)
// 输入: "abc" → 只保留 "c"
// 验证: retained_bytes=1, omitted_bytes=2

// 测试4: drain 后状态重置
fn draining_resets_state()
// 填充缓冲区 → drain_chunks → 验证所有计数器归零

// 测试5: 单块超过 tail 预算
fn chunk_larger_than_tail_budget_keeps_only_tail_end()
// 预算: 10 (head=5, tail=5)
// 先填充: "0123456789" (head=5, tail=5)
// 超大块: "ABCDEFGHIJK" (11 bytes)
// 期望: 保留 "01234" + "GHIJK" (最后5字节)

// 测试6: 多块逐步填充
fn fills_head_then_tail_across_multiple_chunks()
// 预算: 10 (head=5, tail=5)
// 步骤1: "01" + "234" → head 满，输出 "01234"
// 步骤2: "567" + "89" → tail 满，输出 "0123456789"
// 步骤3: "a" → tail 轮换，输出 "012346789a" (丢弃 "5")
```

### 测试技巧

- 使用 `pretty_assertions::assert_eq` 获得清晰的测试失败信息
- 使用 `String::from_utf8_lossy` 将字节转换为可读的字符串断言
- 验证 `starts_with` / `ends_with` 而非完整内容，关注语义正确性

## 依赖与外部交互

| 依赖 | 用途 |
|-----|------|
| `HeadTailBuffer` | 被测类型 |
| `pretty_assertions` | 测试断言美化 |

## 风险、边界与改进建议

### 当前覆盖

✅ 已覆盖：
- 正常预算管理
- 零/最小预算
- 超大块处理
- 多块填充
- 状态重置

❌ 未覆盖：
- 并发访问（依赖 `Arc<Mutex<>>` 保证，未在此单元测试）
- 极端块大小（如 100MB 单块）
- 长时间运行后的内存碎片

### 改进建议

1. **添加并发测试**：
   ```rust
   #[tokio::test]
   async fn concurrent_push_and_snapshot() {
       // 多任务同时 push 和 snapshot，验证一致性
   }
   ```

2. **添加性能基准**：
   ```rust
   #[bench]
   fn bench_push_small_chunks(b: &mut Bencher) {
       // 测试高频小写入性能
   }
   ```

3. **添加模糊测试**：
   ```rust
   #[fuzz]
   fn fuzz_head_tail_buffer(chunks: Vec<Vec<u8>>) {
       // 随机输入序列，验证不变量：
       // - retained_bytes <= max_bytes
       // - omitted_bytes 单调递增
       // - to_bytes 内容一致性
   }
   ```
