# SafeCity - download real photos taken OF a screen (laptop / phone / TV) for the screen check.
# Run on your laptop (run_download_screens.bat). Saves to D:\Downloads\fight_data\screen (outside the project).
import os, glob
from PIL import Image
from icrawler.builtin import BingImageCrawler
OUT = r"D:\Downloads\fight_data"
QUERIES = [
    "photo of laptop screen taken with phone", "moire pattern photo of screen",
    "picture of computer monitor screen photo", "phone screen photo close up moire",
    "taking photo of tv screen", "photo of phone screen showing picture",
    "screen moire camera", "photographing a monitor screen", "hand holding phone showing photo",
    "smartphone screen showing image close up", "laptop screen showing news photo",
]
for q in QUERIES:
    d = os.path.join(OUT, "_raw_img", "screen", q.replace(" ", "_")); os.makedirs(d, exist_ok=True)
    try:
        BingImageCrawler(storage={"root_dir": d}, log_level=40).crawl(keyword=q, max_num=80, min_size=(300, 300))
    except Exception as e:
        print("skipped", q, e)
    print("images: screen", q, len(os.listdir(d)), flush=True)
dst = os.path.join(OUT, "screen"); os.makedirs(dst, exist_ok=True); n = 0
for f in glob.glob(os.path.join(OUT, "_raw_img", "screen", "*", "*")):
    try:
        Image.open(f).convert("RGB").save(os.path.join(dst, f"img_{n:05d}.jpg"), quality=95); n += 1
    except Exception:
        pass
print("screen", n, "photos. Done")
