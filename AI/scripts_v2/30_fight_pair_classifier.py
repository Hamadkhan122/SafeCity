# Fight-pair classifier: friendly contact (handshake, hug, high five, dancing) vs real fight
# =========================================================================================
# Problem: the fight-pose rule (17_pose_fight_rule.py) fires on any arm reaching into the other
# person, so handshakes (16 %), high fives (87 %), hugs (10 %) and dancing (39 %) were accepted
# as "Fight".
# Fix: when the pose rule fires, the upper-body crop of the two people is checked by a second
# model. Fight = incident model "fighting" >= 0.80  OR  (pose rule >= 0.5 AND fight-pair >= 0.70).
#
# 1. For every photo: YOLOv8n-pose -> the pair of people that triggered the rule ->
#    crop = their joint box, upper 65 %, 8 % margin -> 224 x 224 (same as _pairCrop in Dart).
# 2. Features: frozen MobileNetV2 backbone of the incident model (1280 numbers), crop + mirror.
# 3. Logistic regression (C = 0.5, balanced classes) -> Dense(1, sigmoid) on the backbone
#    -> assets/models/fight_pair.tflite (float16, 4.5 MB). Source model: AI/models/safecity_fight_pair.keras
#
# Training data (web photos downloaded with 20_/26_ scripts):
#   fight   : street fights, brawls, pushing, punching (UFC / boxing excluded)
#   friendly: people shaking hands, greeting handshake, hugging, high five, standing / talking
#             together, laughing, playing, dancing, arguing, man posing with fists
#
# Results
#   leave-one-query-out cross validation (whole query held out), pose rule + pair model:
#     handshake 16 % -> 3 %   high five 87 % -> 7 %   hug 10 % -> 2 %   dancing / arguing 39 % -> 15 %
#   unseen photos: our staged park fight (phone camera) 83 % accepted, staged fight photos 5/8,
#     CCTV fights 87 % (incident model path, unchanged)
import numpy as np, tensorflow as tf
from PIL import Image

it = tf.lite.Interpreter("../safecity/assets/models/fight_pair.tflite"); it.allocate_tensors()

def pair_crop(photo, box):
    """photo: PIL image (max side 896), box: x1, y1, x2, y2 relative to the photo"""
    W, H = photo.size; x1, y1, x2, y2 = box[0]*W, box[1]*H, box[2]*W, box[3]*H
    y2 = y1 + 0.65*(y2-y1); px, py = 0.08*(x2-x1), 0.08*(y2-y1)
    return photo.crop((int(round(max(0, x1-px))), int(round(max(0, y1-py))),
                       int(round(min(W, x2+px))), int(round(min(H, y2+py))))).resize((224, 224), Image.BOX)

def fight_pair_score(photo, box):
    x = np.asarray(pair_crop(photo.convert("RGB"), box), np.float32)[None]
    it.set_tensor(it.get_input_details()[0]["index"], x); it.invoke()
    return float(it.get_tensor(it.get_output_details()[0]["index"])[0][0])
