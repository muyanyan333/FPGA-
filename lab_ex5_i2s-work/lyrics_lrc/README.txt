最快的方式：直接运行交互式粘贴工具

    python tools/paste_lyrics.py

- 输入歌名或曲目号
- 粘贴歌词，最后单独一行输入 END
- 支持三种粘贴内容：
  1. 标准 LRC：`[00:12.34]歌词`
  2. 时间前缀：`00:12.34 歌词`
  3. 纯文本：按 WAV 时长自动均分，或输入首句时间和每行间隔
- 可以连续粘贴多首；结束后可选择直接渲染 LYR2 并写入卡
- 输入的歌名如果不在当前 playlist，会去 media/playlist_12tracks.csv 查原始
  曲目号（例如“静悄悄”=11），并自动从 MUSIC/source_mp4/removed_songs/
  恢复对应的 WAV，再追加到 playlist

歌词只在本机处理，脚本不会把歌词打印到日志。

也可以手动把 LRC 按下面的文件名放在这个文件夹里：

    01.lrc  ->  01.wav / 01.lyr
    02.lrc  ->  02.wav / 02.lyr
    ...
    12.lrc  ->  12.wav / 12.lyr

支持的格式是标准 LRC：

    [00:12.34]第一句歌词
    [00:15.80]第二句歌词
    [00:18.00]          <- 空行会清空显示

可以带多个时间标签：
    [00:12.34][00:20.00]重复的一句

也支持 [offset:+/-毫秒]。

如果你的 LRC 是逐个从网站下载的，文件名不一定是 01.lrc…12.lrc，
可以先批量导入（只做匹配/重命名/时长对照，不下载任何内容）：

    python tools/import_lrc.py --src "C:\Users\Lenovo\Downloads\lrc"

它会按序号或歌名匹配到 12 首，打印每首 LRC 的最后时间与 WAV 时长的差值，
然后把文件复制成 lyrics_lrc/01.lrc … 12.lrc。没有匹配到的曲目会保留卡上的
v2 抽取版本。

放好之后运行（TF 卡插回 E: 后）：

    python tools/prepare_card.py --dry-run
    python tools/prepare_card.py

脚本会优先使用这里的 .lrc，用统一的 16 px 字体重新渲染到屏幕顶部；
没有对应 .lrc 的曲目会继续使用原来从视频里提取的歌词点阵。

注意：LRC 文本的版权归原权利人所有，请使用你有权使用的歌词文件。
