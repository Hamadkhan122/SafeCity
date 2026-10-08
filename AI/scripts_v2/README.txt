SafeCity - AI models (training record)
=======================================
Run every script from this AI\ folder, e.g.  python scripts_v2\25_train_head_v10.py v6,old 2 head_v10.keras  (with ALLLIVE=1)
The app itself only uses the three .tflite files in ..\safecity\assets\models\.

MODELS IN THE APP
-----------------
1. incident_mobilenetv2.tflite  (source: models\safecity_incident_v11.keras)
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
   Fight passes when the fight-pose check finds two people really fighting
   (punch/push contact, kick, or BOTH in a fighting guard, nobody sitting)
   OR the incident model alone is very sure (fighting >= 0.80).
   One person posing with fists next to a calm / sitting friend is rejected.
4. screen_texture.tflite  (small CNN, scripts 27-28)
   Looks at 8 patches of 128x128 px of the ORIGINAL full-resolution photo for the
   pixel grid / moire of a screen - independent of what picture the screen shows.
   Mean of the 3 highest patches >= 0.90 -> rejected as "may show a screen"
   (no strike). About 1.4% of held-out real photos reach 0.90.
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
Step 3 (scripts_v2\, v10 - current app model):
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
  16   train head v9 (uses 15, 19, 22 and 23; real screen photos weighted 2.5x)
  24   real photos OF screens from our own test videos (UFC / news pictures on a laptop,
       accident picture on a phone) + live camera frames
  25   train head v10 = v9 data + 24; UFC / MMA / boxing relabelled "normal"
       (a sports match is not an incident)
  26   (run on the laptop) more web fight / no-fight photos and videos. Tested:
       the extra data did NOT improve the unseen-data results (the web labels are
       too noisy), so the app keeps head v10.
  27-28 screen-texture model (see model 4) The RDD street-view "road_damage" photos are left out: most
       of them show a normal-looking road (the damage is too small to see), so
       the old model accepted ANY road photo (our own normal campus road was
       verified as road damage). Now the damage must be visible.
  17   YOLOv8n-pose export + fight-pose rule (same rule as the Dart code)
  18   build models\safecity_incident_v10.keras and convert to TFLite float16
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

RESULTS (v10)
-------------
AIVE photo decision (photo must pass; same thresholds as the app):
  real photos accepted: accident ~90%, fire 94.5%, road damage (visible) 99%
  Fight: posed/staged fight photos 7 of 8, CCTV fights 92%
  Fake fights rejected: one person posing next to a calm friend 4 of 4;
         hugs/handshakes/people together 2%; street people 1%; man standing 0%
  Photos of another screen (our test videos): UFC picture on a laptop 97% and
         accident picture on a phone 93-96% of frames caught as "screen";
         0 live camera frames flagged; real incident photos flagged about 2%;
         everyday indoor scenes with a monitor/TV visible about 12%
  IMPORTANT: when we trained on one test video and tested on the other, only
  5-80% of the unseen video was caught. The screen-texture model (4) was added
  for unseen screens; its real-world catch rate still has to be measured with
  real phone photos of screens. The screen check is learned from the
  picture and can miss a NEW kind of screen photo. More real screen photos
  (taken with a phone camera) make it stronger.
Screen check: reject from 0.50, strike from 0.60.

SAFETY SCORE WEIGHTS (lowered on team request, see ..\SCORING_RULES.md):
  Fire 3 · Accident 3 · Fight 2 · Harassment 2 · Road Damage 2
  (small points: a few incidents in one place no longer push the score to 0)

SCREEN DECISION v12 (29_screen_device_detector.py)
--------------------------------------------------
Live photos of a real fight on a misty day were rejected as screen photos:
haze / low contrast raises the picture model's "screen" score. Now a photo is
a screen photo only with evidence: picture model >= 0.90, OR a laptop / TV /
phone / keyboard visible (YOLOv8n detector, device_yolov8n.tflite) with
screen >= 0.30, OR the screen-texture model >= 0.90 with screen >= 0.30.
Misty park fight photos: 66 % -> 0 % rejected. Photos of screens caught:
58-90 % (before 95-100 %, but with false rejections of real photos).

FIGHT-PAIR MODEL (30_fight_pair_classifier.py)
----------------------------------------------
Handshakes, hugs and high fives were accepted as Fight by the pose rule. Now
the upper-body crop of the two people is checked by fight_pair.tflite:
Fight = model "fighting" >= 0.80 OR (pose rule >= 0.5 AND fight-pair >= 0.55)
OR (hand on the other person's face / neck AND fight-pair >= 0.40).
Fight-pair score = average of the crop and its mirror image.
Held-out tests: handshake 16 % -> 4 %, high five 87 % -> 11 %, hug 10 % -> 3 %;
staged fights (park, choke while sitting) accepted; people talking rejected.

KNOWN LIMITS
------------
- A still photo cannot always tell a hug or dance from a fight. The rules are
  now strict, so a real fight must show contact (punch / push) or both people
  fighting; a fight photographed from far away (small people) may be rejected.
- A very close photo of another phone, where the phone edge/hand is not visible,
  can still miss the screen check; it is then usually rejected because the
  incident itself is not recognised.
- Road damage must be clearly visible (cracks, potholes). A far-away street view
  with small damage is rejected - take the photo closer to the damage.
- Small gas-stove flames are not treated as a fire incident.
- Test images come from public datasets; real-world accuracy can be lower.
