# 同梱動画の作り方

`VideoPlayback/Resources/loop.mp4` は、チュートリアル第 3 部 3.4 の実行結果
（[`docs/tutorial/images/03-Motion/04-Trigonometry.webp`](../../../../docs/tutorial/images/03-Motion/04-Trigonometry.webp)）
を変換したものです。metaphor 自身が描いた絵なので、読者が「どう作られた動画か」を追えます。

作り直すときはリポジトリ直下で次を実行します（`brew install webp ffmpeg` が要ります）。

```bash
SRC=docs/tutorial/images/03-Motion/04-Trigonometry.webp
mkdir -p /tmp/loop-frames
for i in $(seq 1 48); do
  webpmux -get frame $i "$SRC" -o /tmp/loop-frames/f.webp >/dev/null
  dwebp -quiet /tmp/loop-frames/f.webp -o "/tmp/loop-frames/$(printf %03d $i).png"
done
ffmpeg -y -framerate 15 -i /tmp/loop-frames/%03d.png -vf scale=320:-2 \
  -c:v libx264 -pix_fmt yuv420p -crf 28 -an \
  Examples/Tutorial/07-Media/04-VideoPlayback/VideoPlayback/Resources/loop.mp4
```

320x180・15fps・約 3 秒で 23KB です。リポジトリを太らせないよう、この程度に収めます。
