# frame_27.txt 研究文档

## 场景与职责

`frame_27.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的第 27 帧，属于 `codex` 变体动画序列。

**动画序列位置**：第 27/36 帧
**时序位置**：2080ms（第 27 个 80ms 间隔）

## 功能点目的

1. **动画序列延续**：作为 36 帧循环的第 27 帧，达到 75% 周期点（3/4）
2. **旋转展示**：展示 Codex 图标旋转约 260° 后的状态
3. **视觉反馈**：在终端启动期间提供持续的视觉变化

## 具体技术实现

### 3/4 周期点特性
```
frame_27 是第 27 帧（索引 26）
时间：2080ms
周期进度：27/36 = 75%（正好 3/4）
剩余帧数：9 帧
旋转角度：260°
```

### 帧索引
```rust
const FRAME_27_INDEX: usize = 26;
let content = FRAMES_CODEX[FRAME_27_INDEX];
```

### 时间计算
```rust
let elapsed_ms = 2080;
let idx = (elapsed_ms / 80) % 36;  // = 26
let frame = FRAMES_CODEX[idx as usize];  // frame_27
```

## 关键代码路径与文件引用

### 文件引用链
```
frame_27.txt
  └─> frames.rs (include_str!)
      └─> FRAMES_CODEX[26]
          └─> ascii_animation.rs
              └─> welcome.rs
                  └─> 终端显示
```

### 关键代码
```rust
// frames.rs
pub(crate) const FRAMES_CODEX: [&str; 36] = frames_for!("codex");

// ascii_animation.rs
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]  // 可能返回 frame_27
}
```

## 依赖与外部交互

### 上游
- `frame_26.txt`
- 时间流逝

### 下游
- `frame_28.txt`
- 终端显示

### 外部控制
- 变体切换
- 动画开关

## 风险、边界与改进建议

### 3/4 周期考虑
1. **关键节点**：3/4 周期是动画的关键节点
2. **视觉一致性**：需要确保与前后帧的平滑过渡
3. **循环准备**：还有 9 帧回到 frame_1

### 改进建议
1. **关键帧标记**：在代码中标记 3/4 周期点
2. **帧验证**：验证 frame_27 与 frame_9 的关系（如果动画对称）
3. **性能优化**：确保关键节点的渲染性能

### 测试建议
```rust
#[test]
fn frame_27_is_three_quarters() {
    // 验证 frame_27 是第 27 帧
    assert_eq!(FRAMES_CODEX.len(), 36);
    let three_quarters_idx = FRAMES_CODEX.len() * 3 / 4;  // = 27
    // frame_27 在索引 26
    let frame_27 = FRAMES_CODEX[26];
    assert!(!frame_27.is_empty());
}
```
