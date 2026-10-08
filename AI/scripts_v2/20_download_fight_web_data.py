# SafeCity - download extra Fight training data (Google/Bing images + YouTube videos)
# ===================================================================================
# Run on YOUR LAPTOP (Windows), not in the project. Data goes OUTSIDE the project folder
# (do not push it to git - the photos/videos belong to their owners; only the trained
# model goes into the app).
#
# 1. Install Python 3.10+ from python.org (tick "Add Python to PATH")
# 2. In a terminal:   pip install icrawler yt-dlp opencv-python pillow
# 3. Run:             python download_fight_data.py
# 4. Result: D:\Downloads\fight_data\  ->  fighting\  and  normal\   (224-640 px jpgs)
#    Takes about 20-40 minutes. Then tell Claude: "fight_data folder ready".
#
# Both FIGHT and NO-FIGHT examples are needed: without "people hugging / shaking hands /
# standing close" the model would call every group of people a fight.

import os, glob, subprocess, sys
import cv2
from PIL import Image

OUT = r"D:\Downloads\fight_data"
IMAGES_PER_QUERY = 80
VIDEOS_PER_QUERY = 6
FRAME_EVERY_SEC = 2

FIGHT_IMAGE_QUERIES = [
    "street fight photo", "people fighting street", "two men fighting punch",
    "fight caught on camera", "students fighting school", "brawl photo",
    "ufc fight punch", "mma fight photo", "boxing punch photo", "man punching man",
    "people pushing each other fight", "fight in market", "road rage fight",
]
NORMAL_IMAGE_QUERIES = [
    "two people talking street", "friends hugging", "people shaking hands",
    "friends standing together outdoor", "group of students walking campus",
    "people walking market", "couple walking street", "friends high five",
    "people waiting bus stop", "man standing street photo",
]
FIGHT_VIDEO_QUERIES = [
    "street fight caught on camera", "real fight cctv footage", "ufc knockout highlights",
    "mma fight highlights", "school fight caught on camera",
]
NORMAL_VIDEO_QUERIES = [
    "people walking street pov", "friends hanging out vlog", "crowded market walk",
]

def images(queries, cls):
    from icrawler.builtin import BingImageCrawler, GoogleImageCrawler
    for q in queries:
        d = os.path.join(OUT, "_raw_img", cls, q.replace(" ", "_"))
        os.makedirs(d, exist_ok=True)
        for Crawler in (BingImageCrawler, GoogleImageCrawler):
            try:
                Crawler(storage={"root_dir": d}, log_level=40).crawl(
                    keyword=q, max_num=IMAGES_PER_QUERY, min_size=(200, 200))
            except Exception as e:
                print("  skipped", Crawler.__name__, q, e)
        print("images:", cls, q, len(os.listdir(d)))

def videos(queries, cls):
    for q in queries:
        d = os.path.join(OUT, "_raw_vid", cls)
        os.makedirs(d, exist_ok=True)
        subprocess.run([sys.executable, "-m", "yt_dlp", f"ytsearch{VIDEOS_PER_QUERY}:{q}",
                        "-f", "mp4[height<=480]/best[height<=480]", "--max-filesize", "80M",
                        "--match-filter", "duration < 900", "-o",
                        os.path.join(d, "%(id)s.%(ext)s"), "--no-playlist", "-i", "-q"])
        print("videos:", cls, q)

def save(im, path):
    im = im.convert("RGB"); w, h = im.size; s = 640 / max(w, h)
    if s < 1: im = im.resize((int(w * s), int(h * s)), Image.BOX)
    im.save(path, quality=90)

def collect():
    for cls in ("fighting", "normal"):
        dst = os.path.join(OUT, cls); os.makedirs(dst, exist_ok=True); n = 0
        for f in glob.glob(os.path.join(OUT, "_raw_img", cls, "*", "*")):
            try:
                save(Image.open(f), os.path.join(dst, f"img_{n:05d}.jpg")); n += 1
            except Exception:
                pass
        for v in glob.glob(os.path.join(OUT, "_raw_vid", cls, "*.mp4")):
            cap = cv2.VideoCapture(v); fps = cap.get(cv2.CAP_PROP_FPS) or 25
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)); step = int(fps * FRAME_EVERY_SEC)
            vid = os.path.splitext(os.path.basename(v))[0]
            for i in range(0, total, max(step, 1)):
                cap.set(cv2.CAP_PROP_POS_FRAMES, i); ok, fr = cap.read()
                if not ok: break
                save(Image.fromarray(cv2.cvtColor(fr, cv2.COLOR_BGR2RGB)),
                     os.path.join(dst, f"vid_{vid}_{i:06d}.jpg")); n += 1
        print(cls, n, "photos")

if __name__ == "__main__":
    images(FIGHT_IMAGE_QUERIES, "fighting")
    images(NORMAL_IMAGE_QUERIES, "normal")
    videos(FIGHT_VIDEO_QUERIES, "fighting")
    videos(NORMAL_VIDEO_QUERIES, "normal")
    collect()
    print("Done ->", OUT)
