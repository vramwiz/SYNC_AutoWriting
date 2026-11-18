"""本番AUF2の検査出力PNGを、確認用GIFと一覧画像へまとめる。製品の依存ではない。"""

from pathlib import Path
import argparse
from PIL import Image, ImageChops, ImageDraw, ImageFont


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("frames", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    paths = sorted(args.frames.glob("frame_*.png"))
    if not paths:
        parser.error("DemoFrames/frame_*.png was not found; run run_tests.ps1 -Demo first")
    args.output.mkdir(parents=True, exist_ok=True)
    frames = [Image.open(path).convert("RGB") for path in paths]
    # 全体から共通パレットを作り、フレームごとの色の揺れを抑える。
    palette_source = Image.new("RGB", (400 * 4, 225 * 4), "white")
    for index in range(16):
        sample = frames[round(index * (len(frames) - 1) / 15)].resize((400, 225))
        palette_source.paste(sample, ((index % 4) * 400, (index // 4) * 225))
    palette = palette_source.quantize(colors=128)
    # 減色時に白背景が薄い灰色へ寄らないよう、白と黒のパレット色を固定する。
    colors = palette.getpalette()
    endpoints = {}
    for target in (255, 0):
        index = min(range(128), key=lambda i: sum((colors[i * 3 + c] - target) ** 2 for c in range(3)))
        colors[index * 3:index * 3 + 3] = [target] * 3
        endpoints[target] = index
    palette.putpalette(colors)
    indexed = []
    for frame in frames:
        item = frame.quantize(palette=palette, dither=Image.Dither.NONE)
        red, green, blue = frame.split()
        # パレット参照の近似探索でも純白・純黒が別の近似色へ割り当たらないようにする。
        white = ImageChops.darker(ImageChops.darker(red, green), blue).point([0] * 255 + [255])
        black = ImageChops.lighter(ImageChops.lighter(red, green), blue).point([255] + [0] * 255)
        item.paste(endpoints[255], mask=white)
        item.paste(endpoints[0], mask=black)
        indexed.append(item)
    indexed[0].save(
        args.output / "auto_writing.gif", save_all=True, append_images=indexed[1:],
        duration=50, loop=0, disposal=2, optimize=True,
    )
    frames[-1].save(args.output / "complete.png")
    sheet = Image.new("RGB", (1200, 500), "#e9eaed")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16)
    except OSError:
        font = ImageFont.load_default()
    for index, at in enumerate((0.0, 1.2, 2.4, 3.6, 4.8, 6.5)):
        frame = frames[min(round(at * 20), len(frames) - 1)].resize((400, 225))
        x, y = (index % 3) * 400, (index // 3) * 250
        sheet.paste(frame, (x, y))
        draw.text((x + 12, y + 228), f"{at:.1f} s", fill="#30323a", font=font)
    sheet.save(args.output / "timeline.png")
    print(f"Created GIF and PNG samples from {len(frames)} production frames")


if __name__ == "__main__":
    main()
