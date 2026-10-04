# SafeCity - more REAL fight / no-fight data (street fights filmed on phones, CCTV, viral videos)
# and hard negatives (hugging, greeting, playing, posing). Run with run_download_more_fight.bat.
# Saves to D:\Downloads\fight_data2 (outside the project; do not push it to git).
import os, sys, subprocess
from icrawler.builtin import BingImageCrawler
OUT = r"D:\Downloads\fight_data2"
IMG = {
 "fighting": ["street fight caught on phone", "people fighting in street photo", "college students fight",
              "fight in road pakistan", "men fighting market", "public brawl photo", "fight outside restaurant",
              "punching in street fight", "two boys fighting school", "people fighting crowd watching"],
 "normal":   ["friends hugging street", "people greeting handshake", "friends playing outdoor",
              "people dancing together", "man posing with fists", "friends laughing together",
              "group of men standing talking", "students sitting together campus", "people arguing talking", "family walking park"],
}
VID = {
 "fighting": ["street fight caught on camera phone", "real street fight video", "school fight caught on phone",
              "road rage fight pakistan", "market fight video", "cctv fight footage shop"],
 "normal":   ["friends hugging reunion video", "people walking street vlog", "friends playing cricket street",
              "people dancing wedding", "college students hanging out vlog"],
}
for cls, qs in IMG.items():
    for q in qs:
        d = os.path.join(OUT, "img", cls, q.replace(" ", "_")); os.makedirs(d, exist_ok=True)
        try:
            BingImageCrawler(storage={"root_dir": d}, log_level=40).crawl(keyword=q, max_num=80, min_size=(250, 250))
        except Exception as e:
            print("skipped", q, e)
        print("images:", cls, q, len(os.listdir(d)), flush=True)
for cls, qs in VID.items():
    for q in qs:
        d = os.path.join(OUT, "vid", cls); os.makedirs(d, exist_ok=True)
        subprocess.run([sys.executable, "-m", "yt_dlp", f"ytsearch5:{q}", "-f", "mp4[height<=480]/best[height<=480]",
                        "--max-filesize", "60M", "--match-filter", "duration < 600", "-o",
                        os.path.join(d, "%(id)s.%(ext)s"), "--no-playlist", "-i", "-q"])
        print("videos:", cls, q, flush=True)
print("Done")
