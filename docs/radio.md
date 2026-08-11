# Rain Music Radio 在线电台

游戏只连接 Rain Music Radio 的连续 MP3 直播流，不携带、下载或提供任何音乐文件。安装包内仅保存电台地址和归属信息。

## 为什么改用连续流

Rain Music Radio 是以 Chillhop、Lo-fi Hip Hop 为主并混合 Jazz/Jazzhop 的连续广播。当前曲目结束后，下一首仍从同一条连接继续传输，因此曲目边界不会触发重新连接。

播放器会先在内存中积累 20 秒音频再开始播放，因此声音比直播时间晚约 20 秒；这段余量可以抵抗短时网络抖动。曲名显示使用同样的延迟。播放器还设置了 32 MB 缓冲上限，并启用 EOF、网络错误及 HTTP 4xx/5xx 的自动重连。

直播电台不会提前公开下一首音频文件，所以不能单独下载“下一首”。当前曲目和下一首始终沿同一条连接进入上述延迟队列，缓存只在播放器内存中存在，不会在磁盘留下音乐文件。

## 来源与发行边界

- 官网：<https://rain-radio.com/>
- 直播流：`https://thanasis.radioca.st/`
- 官网将风格明确列为 `lofi / chillhop / hiphop / jazz`。
- 官网说明频道音乐均为其原创，电台是免费的 Creative Commons 音乐合集，并写明 `Listen, Use, Share`。
- 游戏不转播、不录制、不代理、不提供下载，只让最终用户的播放器直接连接电台原始服务器。

发行时保留电台名称和官网入口。官网没有写明具体 Creative Commons 版本；若未来加入广告、付费版本或改变播放方式，需要重新向电台确认授权范围。

## 播放链路

- `data/stations.json`：固定电台、直播地址和归属信息。
- `scripts/music_manager.gd`：播放、暂停、状态与曲名展示。
- `scripts/radio_bridge.gd`：只接受固定清单中的白名单地址。
- `helpers/radio_player.ps1`：启动隐藏的 `ffplay`，维护读前缓冲与断线续连。
- `helpers/radio_metadata.ps1`：读取电台 ICY 曲名，并在界面显示艺术家和当前曲目。
