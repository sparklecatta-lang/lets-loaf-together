# 一起磨洋工 / Let's Loaf Together

Godot 4.7 桌面陪伴原型。主角是伏案写字/画画的金发女孩，旁边有一只黄猫；二者都使用帧动画。界面保持无边框与置顶，只显示极简在线音乐控制。

## 直接运行

源码运行需要 Godot 4.7。可把 Godot 加入 `PATH`、放到项目根目录，或显式指定可执行文件：

```powershell
& '.\run_companion.ps1' -GodotExe 'C:\path\to\Godot_v4.7-stable_win64.exe'
```

如果 Godot 已加入 `PATH`，直接双击根目录的 `run_companion.ps1` 即可。

左键拖动画面可以移动窗口，按住 `Z` 滚轮缩放，右键显隐右上角音乐面板。启动时面板默认隐藏，但会自动播放 Rain Music Radio。窗口位置、尺寸和置顶状态保存在 Godot 的 `user://window_settings.cfg`。

## 完整版下载

普通用户使用包含全部美术、动画、本地音频和在线音乐播放器的完整包，不需要另外安装素材：

- Windows：`LetsLoafTogether-Windows.zip`，230.87 MiB，SHA-256 `6f5c86ceb90da8fd89ccdeefc1065460c142e12a575e2f4fbc656758e79f6cb0`（网盘地址待上传后填写）
- macOS：`LetsLoafTogether-macOS.zip`，243.55 MiB，SHA-256 `0d488146c084aa96dd18f37c1b2428782f7e372bb8fcf44af950fc4e76077f64`（网盘地址待上传后填写）

Windows 解压后双击 `LetsLoafTogether.exe`。macOS 解压后打开“一起磨洋工.app”；当前没有 Apple 开发者签名或公证，首次打开可能出现系统安全提示。

## 音乐

- 在线音乐使用 Rain Music Radio 的连续直播流，以 Chillhop、Lo-fi Hip Hop 为主并混合 Jazz/Jazzhop，没有搜索、推荐流或 URL 输入。
- 当前曲目和下一首沿用同一条长连接；播放器先缓存约 20 秒再播放，使用 32 MB 内存缓冲上限并自动断线重连，安装包不包含音乐文件。
- 右上角面板显示音效音量、音乐音量、当前歌名、播放暂停、置顶锁和关闭电源。
- 锁图标表示窗口保持最上方；电源图标会先显示确认框，不会直接关闭。
- 音乐音量与角色音效音量独立保存；音乐设置在 `user://music_settings.cfg`，音效设置在 `user://sound_effect_settings.cfg`。
- Windows 完整包随附独立的 `ffplay.exe`，源码开发环境仍可回退到本机 `I:\FF\bin\ffplay.exe`；导出运行时会先把控制脚本释放并校验到 `user://runtime_helpers`。
- macOS 完整包随附 Intel 与 Apple Silicon 两种 FFplay。暂停或调节音乐音量时会重新连接直播流；该平台包已完成结构与架构校验，但尚未在真实 Mac 上试听。
- 电台来源、曲库授权说明和发行边界见 `docs/radio.md`。完整包内附 FFmpeg GPL 许可证和第三方声明。

## 源码构建者素材包

这一素材包只用于从 GitHub 获取源码后自行运行或构建的开发者；普通用户直接下载上面的完整程序包。素材包包含运行所需的背景、道具、角色动画帧、帧动画音效和天气环境音，在线电台音乐不会下载或转存。

下载 `LetsLoafTogether-ArtAudio.zip`（166.75 MiB）：

- [Google Drive](https://drive.google.com/file/d/14hr-PRQ4gTomjQCN2RJvOxr4cmrr5voU/view?usp=sharing)
- [百度网盘](https://pan.baidu.com/s/1ayXlGbPS89eKCPRi9rRdvw?pwd=qdf6)（提取码：`qdf6`）

SHA-256：`53f05bad9a8557bddcc4c79254e0d543ff7f0eaf30b0202a74b47ba61666c5a6`

下载后直接解压到项目根目录，使压缩包中的 `assets` 与 `xsxb_frame_tuner` 合并到项目内同名目录，不要额外套一层文件夹。双击 `run_companion.ps1` 时，如果检测到关键素材缺失，会显示上述下载入口和目标目录。

生成素材包：

```powershell
& '.\tools\package_external_assets.ps1'
```

生成 Windows 和 macOS 完整包：

```powershell
& '.\tools\package_full_releases.ps1'
```

默认输出到同级目录 `watercolor-desk-companion-deliverables`。每个压缩包旁边都有独立的 `.sha256` 校验文件；源码构建者素材包的下载地址、文件名、校验值与关键文件列表记录在 `data/external_assets.json`。

## 美术与替换

- 当前背景：`assets/backgrounds/yellow_cat_window_room/cream_table_room_20260810/`
- 女孩帧：`xsxb_frame_tuner/workspace/projects/Watercolor_Desk_Companion/assets/desk_girl/`
- 黄猫帧：`xsxb_frame_tuner/workspace/projects/Watercolor_Desk_Companion/assets/yellow_cat/`
- 原始色键图：`assets/source/`（被 `.gdignore` 排除，不参与 Godot 导入）
- 完整 ImageGen 提示词：`docs/art-prompts.md`

动画帧暂时都是独立 RGBA PNG，场景中的 `SpriteFrames` 直接引用它们。以后重画时维持文件名和画布尺寸，就能低成本替换；若改帧数，再编辑 `scenes/main.tscn` 的对应 `SpriteFrames`。

## 已跑过的回归

- Godot 无头加载、脚本和资源导入。
- 实际透明窗口截图确认极简界面没有压住女孩面部。
- Rain Music Radio 能真实建立连续 MP3 连接，ICY 曲名和播放状态符号可见。
- 播放器开启读前缓冲、网络错误自动续连；停止后 PID 记录被清空。
- 音乐与角色音效滑杆独立生效，音效归零会真正静音。

当前完整包用于测试和无偿分享，项目仍处于原型阶段。请保留 Rain Music Radio 名称和官网入口；若以后加入广告或付费发行，需要重新确认电台授权范围。

## 许可证

仓库中的程序代码以 MIT License 开源。外置美术、动画与音频素材不随源码仓库授权；FFplay、Godot 和在线电台分别遵循各自许可证与服务条款。
