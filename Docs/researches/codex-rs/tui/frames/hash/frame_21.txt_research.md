# frame_21.txt 研究文档

## 场景与职责

`frame_21.txt` 是 Codex TUI `hash` 动画变体的第 21 帧，在 36 帧动画序列中展示哈希图案的动态演变。

### 动画序列位置
- **帧索引**: 20 (0-based)
- **时间范围**: 1600-1679ms (80ms 帧间隔)
- **动画阶段**: 后期阶段

### 视觉特征
该帧展示了图案向外扩散后的形态。

## 功能点目的

### 动画连续性
作为第 21 帧，它在动画中承担：
1. 延续前 20 帧的视觉流动
2. 展示图案的演变

## 具体技术实现

### 编译时嵌入
```rust
include_str!(concat!("../frames/", $dir, "/frame_21.txt"))
```

### 运行时访问
```rust
FRAMES_HASH[20]  // 索引 20 -> frame_21.txt
```

### 索引计算
```rust
let idx = ((elapsed_ms / 80) % 36) as usize;
// elapsed_ms = 1600..1679 -> idx = 20
```

## 关键代码路径与文件引用

### 关键代码

**帧数组** (`frames.rs`):
```rust
pub(crate) const FRAMES_HASH: [&str; 36] = frames_for!("hash");
```

## 依赖与外部交互

### 与其他帧的关系
- 前一帧: `frame_20.txt`
- 后一帧: `frame_22.txt`

## 风险、边界与改进建议

### 文件信息
```
路径: codex-rs/tui/frames/hash/frame_21.txt
大小: 708 bytes
行数: 17
索引: 20
```
