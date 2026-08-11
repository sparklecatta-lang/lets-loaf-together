# ImageGen 美术提示词

以下三张图使用 Codex 内置 ImageGen 生成，没有使用本地 CLI 回退。

## 场景背景

```text
Wide 16:9 Japanese anime watercolor illustration for a cozy desktop companion app. A warm attic studio room at rainy blue-hour dusk, large window with soft rain streaks and distant city lights, wooden floor, bookshelf, houseplants, woven rug, amber table lamps, elegant clean anime background linework softened by real watercolor washes and paper grain, restrained navy/teal/ochre palette, cinematic but calm, high-quality visual-novel background. Leave a generous open floor/work area in the center-right for separate character sprites. No people, no animals, no desk, no chair, no laptop, no computer, no screen, no UI, no text, no logo. Full-bleed environment composition.
```

## 金发女孩 6 帧画画循环

```text
Character animation sprite sheet, exactly six frames arranged in a precise 3 columns by 2 rows grid, all cells equal size. The same adult Japanese-anime woman in every frame: golden-yellow blonde hair tied in a loose low ponytail, soft bangs, blue cardigan over a cream blouse, long dark skirt. She sits at the same small wooden writing desk and quietly draws by hand in an open sketchbook with a pencil; watercolor palette, brush cup, paper and a ceramic mug may sit on the desk. Subtle seamless idle cycle across the six frames: breathing, pencil hand moving a little, brief blink, tiny head tilt, return to start. Clean expressive anime line art combined with delicate transparent watercolor washes and visible paper texture, non-pixel art, refined visual-novel quality. Consistent proportions, camera, furniture and lighting across every cell. Flat solid pure magenta #FF00FF background in every cell, sharp separation from the subject, no magenta/pink/purple on the woman or props, no shadows cast onto the background. No laptop, no computer, no monitor, no phone, no tablet, no digital device. No text, labels, borders, captions or extra panels.
```

## 黄猫 6 帧待机循环

```text
Animal animation sprite sheet, exactly six frames arranged in a precise 3 columns by 2 rows grid, all cells equal size. The same small golden-yellow ginger tabby cat in every frame, Japanese anime character design with clean expressive linework and delicate transparent watercolor washes, visible paper texture, non-pixel art. The cat sits in the same three-quarter pose; subtle seamless idle cycle across six frames: gentle breathing, tail tip sways, one blink, tiny ear twitch, then returns to start. Keep anatomy, markings, proportions, camera and lighting highly consistent across every cell. Flat solid pure magenta #FF00FF background in every cell, sharp separation from the cat, no magenta/pink/purple on the cat, no shadows cast onto the background. No person, no furniture, no computer, no text, labels, borders, captions or extra panels.
```

选择纯洋红 `#FF00FF` 作为色键，是因为主体的金发和黄猫会被绿色/青色色键污染；洋红与主体主色距离更远，去背时更稳。最终运行素材已转换为透明 RGBA PNG。
