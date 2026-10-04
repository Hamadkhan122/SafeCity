SafeCity - AI models (training record)
=======================================
Run every script from this AI\ folder, e.g.  python scripts_v2\16_train_head_v8.py nordd 1.0 head_v8.keras
The app itself only uses the three .tflite files in ..\safecity\assets\models\.

MODELS IN THE APP
-----------------
1. incident_mobilenetv2.tflite  (source: models\safecity_incident_v8.keras)
   Input : 224x224 RGB, raw 0..255 (rescaling is inside the model)
   Output: 7 values
     accident, fighting, fire, normal, road_damage, screen  (softmax)
     person                                                 (sigmoid: people visible?)
   normal = no incident in the photo; screen = photo taken of a laptop/phone screen.
2. harassment_mobilenetv2.tflite  (notebooks\harassment_model_training.ipynb)
   Output: normal, harassment. Used for the Harassment category.
3. pose_yolov8n.tflite  (YOLOv8n-pose, Ultralytics, free / AGPL-3.0; script 17)
   Finds people and 17 body keypoints. Used for Fight: two people close together
   in a punching / pushing / fighting-guard pose (lib\services\pose_fight_detector.dart).
   Fight photo confidence = max(incident "fighting", fight pose).
   (The harassment model is no longer used for Fight: it called 13% of hug /
   handshake photos violent.)

HOW THE INCIDENT MODEL WAS BUILT
--------------------------------
Step 1 (scripts\, teammate's work): MobileNetV2 trained on accident / fighting /
  fire / road_damage (train_mobilenet.py), then fine-tuned for fighting
  (finetune_mobilenet_fighting.py) -> models\safecity_mobilenetv2_fighting_finetuned.keras
  Problem found: no "normal" class, so every photo (cup, wall, noise) was
  labelled as an incident with 90-100% confidence.
Step 2 (scripts_v2\): backbone of step 1 kept frozen; new output layers trained.
  01   add "normal" class (people in streets, objects, normal roads, ImageNet
       sample photos, blank/blurred/dark images) and re-split fighting BY VIDEO
  02   add airtlab violence dataset frames (violent -> fighting, non-violent -> normal)
  03   "screen" class part 1: synthetic photos of laptop / monitor screens
  03b  "screen" class part 2: phone held in hand showing a picture, and
       close-up photos of a screen (glare, washed-out colours)
  04-06, 05b  extract 1280-d features (x3 augmentation for training)
  07   train the 6-class head (v3)
  08   train the "person" head (people visible yes/no)
  09   build the v3 model, 10 convert to TFLite, 11 simulate the AIVE photo decision
Step 3 (scripts_v2\, v8 - current app model):
  12   "screen" class part 3: close-up photos where a phone / monitor screen fills
       the frame (pixel grid, colour cast, glare, bezel, fingers)
  13   normal roads with tree shadows (shadows were mistaken for cracks)
  14   road damage from the "Cracks and Potholes in Road Images" dataset
       (github.com/biankatpas/Cracks-and-Potholes-in-Road-Images-Dataset):
       crops around marked cracks / potholes = road_damage, crops of the same
       roads without marked damage = normal
  15   features for 12-14
  19   more real photos: fire + smoke + normal scenes (offices, buses, traffic)
       from the DeepQuestAI Fire-Smoke-Dataset, and street/CCTV fight and
       no-fight videos from the surveillance fight dataset (features included)
  20   (run on the laptop) download fight photos from Google/Bing and fight
       videos from YouTube (street fights, CCTV, UFC, MMA, boxing) plus no-fight
       photos (hugging, handshakes, people standing together)
  21   (run on the laptop) download real photos taken of screens
  22   clean the web fight photos with the pose model (2+ people close together),
       features, split by search query / video
  23   features for the real screen photos from 21 (phones in hand, monitors,
       TVs, laptops)
  16   train head v8 (uses 15, 19, 22 and 23). The RDD street-view "road_damage" photos are left out: most
       of them show a normal-looking road (the damage is too small to see), so
       the old model accepted ANY road photo (our own normal campus road was
       verified as road damage). Now the damage must be visible.
  17   YOLOv8n-pose export + fight-pose rule (same rule as the Dart code)
  18   build models\safecity_incident_v8.keras and convert to TFLite float16
Note: models\class_names.txt belongs to the step-1 model (4 classes). The app
model's labels (7) are in ..\safecity\assets\models\incident_labels.txt.
Data: scripts expect the dataset in .\data\<split>\<class>\ and .\data_extra\
(kept outside the project because of its size).

APP CHANGE THAT MATTERS FOR ACCURACY
------------------------------------
The app now shrinks the camera photo to 224x224 with AREA AVERAGING (like the
training images). Before, it used plain linear sampling, which on a 12 MP photo
reads only 1 of every ~18 pixels -> noisy, aliased input the models never saw.
On our own phone video frames this alone raised screen detection from 43% to 61%.

RESULTS (v8)
------------
AIVE photo decision (photo must pass; same thresholds as the app):
  real photos accepted: accident 88.5%, fire 94.5%, fighting (CCTV) 97.3%,
                        road damage (cracks/potholes, visible) 99%
  unseen web fight photos/videos: ~93% accepted
  posed / phone-style fight photos: 7 of 8 accepted
  unseen Fire-Smoke test photos: fire 98%, smoke 87% accepted as Fire
  wrong photos accepted: normal->Accident 1.4%, normal->Fire 0.7%,
                        normal->Road damage 0%, street people->Fight 2.7%,
                        synthetic screens->Accident 0.9%
  Our own phone video: 24 of 28 frames showing a picture on another phone are
  flagged as a screen (the other 4 are still rejected: no accident visible);
  0 of 76 live camera frames flagged; man standing calmly -> Fight: 0 of 56;
  normal campus road -> Road damage: 0 of 20.
  Real incident photos wrongly flagged as a screen: about 1.5%.
Screen check: reject from 0.45, strike from 0.60.

KNOWN LIMITS
------------
- A still photo cannot always tell a hug or dance from a fight (two people close
  with arms up). The description check and the score threshold still apply.
- A very close photo of another phone, where the phone edge/hand is not visible,
  can still miss the screen check; it is then usually rejected because the
  incident itself is not recognised.
- Road damage must be clearly visible (cracks, potholes). A far-away street view
  with small damage is rejected - take the photo closer to the damage.
- Small gas-stove flames are not treated as a fire incident.
- Test images come from public datasets; real-world accuracy can be lower.
