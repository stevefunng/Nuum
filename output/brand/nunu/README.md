# Nunu 形象与动作素材

当前创建预览和资料卡共用 NunuPortrait。颜色、形状、材质分别读取 profile 的 avatarColor、avatarShape、avatarMaterial，换一个提供 7 色 × 5 形状 × 4 材质的独立组合；既有 profile 保持原值。

- plush.png、felt.png、matte.png、glass.png：当前使用的高清原图，直接上传 GPU，不经中间画布放大、CSS 变色滤镜或重绘身体。
- plush-body.png 与 plush-body-prompt.txt：上一版分层身体和生成提示词，保留作历史素材，当前不使用。
- actions-atlas.png：用户提供的动作参考。
- portrait-idle.png、四段 webm、motion-manifest.json：历史光流方案，当前不使用。

外观定义在 nunu-appearance.ts。nunu-rig.ts 使用连续网格，肩部权重平滑回到身体，避免分层硬切；形状在网格上应用不同轮廓比例。材质直接来自不同原图，颜色在着色器内应用并保留高光。使用原始纹理分辨率与至少 2× 的显示画布；无每帧位图切换。

动作：挥手 900ms、左右张望 1250ms、举手双跳 1050ms、打盹点头 1400ms。保持一条待播动作，连点不中断当前轨迹。静止时停止刷新，支持减少动态效果与后台停止。

玻璃 v2：glass.png 已替换为乳白半透的蛋白石玻璃，原镜面版本保存为 glass-v1-archived.png。内置 imagegen 编辑的完整提示词见 glass-v2-prompt.txt。运行时对玻璃使用浅染色，避免蜂蜜等暖色变成棕黄；全身体型的高度系数保持 0.98–1.02，不能通过压矮来制造体型差异。

正式外观、动画与 Logo 约束见 [Nunu 与品牌规范](../../../docs/coding/nunu-brand.md)。
