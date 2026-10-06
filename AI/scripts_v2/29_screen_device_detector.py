# Screen device detector (v12 screen decision)
# =============================================
# Problem: live photos of a real (staged) fight in a misty park were rejected
# as "photo of a screen". Test: hazy / low-contrast photos raise the picture
# model's "screen" score (haze 0.45 -> 22 % of normal photos >= 0.50).
# Fix: a photo is a screen photo only with EVIDENCE:
#   a) picture model screen >= 0.90, or
#   b) a laptop / TV / phone / keyboard is visible (this detector) and screen >= 0.30, or
#   c) screen-texture model >= 0.90 and screen >= 0.30.
#
# 1. Export the free YOLOv8n COCO detector to TFLite, input 320 (same letterbox
#    input as the pose model):
#       from ultralytics import YOLO
#       YOLO("yolov8n.pt").export(format="tflite", imgsz=320)
#    -> assets/models/device_yolov8n.tflite  (input [1,3,320,320], output [1,84,2100])
# 2. Device score = best score of class 62 tv, 63 laptop, 66 keyboard, 67 cell phone
#    with a box >= 2 % of the photo, score >= 0.25.
#
# Results (picture model v11 + rule):
#   set                          old rule   new rule
#   photos of screens (test vid) 95-100 %   58-90 %
#   web photos of screens          88 %       74 %
#   our misty park fight (live)    66 %        0 %
#   live camera frames              0 %        0 %
#   normal / incident photos      0-9 %      0-2 %
#   hazy photos (haze 0.45)        22 %        3 %
import numpy as np, tensorflow as tf
from PIL import Image

S = 320; DEVICES = (62, 63, 66, 67)
it = tf.lite.Interpreter("device_yolov8n.tflite"); it.allocate_tensors()

def letterbox(im):
    W, H = im.size; s = S / max(W, H); w, h = max(1, round(W * s)), max(1, round(H * s))
    c = Image.new("RGB", (S, S), (114, 114, 114)); c.paste(im.resize((w, h), Image.BOX), ((S - w) // 2, (S - h) // 2))
    return c, w, h

def device_score(path):
    c, w, h = letterbox(Image.open(path).convert("RGB"))
    x = (np.asarray(c, np.float32) / 255.).transpose(2, 0, 1)[None]
    it.set_tensor(it.get_input_details()[0]["index"], x); it.invoke()
    y = it.get_tensor(it.get_output_details()[0]["index"])[0]; best = 0.0
    for cls in DEVICES:
        for j in np.where(y[4 + cls] >= 0.25)[0]:
            if y[2, j] * S * y[3, j] * S / (w * h) >= 0.02: best = max(best, float(y[4 + cls, j]))
    return best

if __name__ == "__main__":
    import sys
    for f in sys.argv[1:]: print(f, round(device_score(f), 2))
