import os
import sys
import numpy as np
import tensorflow as tf
from PIL import Image


# ============================================================
# Evaluates the image model on ALL images in the test_images folder.
# The true class is taken from the start of the file name:
#   accident*  -> accident
#   fight*     -> fighting
#   fire*      -> fire
#   road*, pothole*, damage* -> road_damage
# Other file names are skipped.
#
# Usage:
#   python scripts\evaluate_external.py
#   python scripts\evaluate_external.py <other_model>.keras
# ============================================================

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = os.path.join(BASE_DIR, "models")
TEST_DIR = os.path.join(BASE_DIR, "test_images")

MODEL_NAME = (
    sys.argv[1]
    if len(sys.argv) > 1
    else "safecity_mobilenetv2_fighting_finetuned.keras"
)

IMG_SIZE = (224, 224)
EXTENSIONS = (".jpg", ".jpeg", ".jfif", ".png", ".webp")

PREFIXES = [
    ("accident", "accident"),
    ("fighting", "fighting"),
    ("fight", "fighting"),
    ("fire", "fire"),
    ("road", "road_damage"),
    ("pothole", "road_damage"),
    ("damage", "road_damage"),
]


def true_class_from_name(filename):
    name = filename.lower()
    for prefix, label in PREFIXES:
        if name.startswith(prefix):
            return label
    return None


with open(os.path.join(MODELS_DIR, "class_names.txt"), "r", encoding="utf-8") as f:
    class_names = [line.strip() for line in f if line.strip()]

model = tf.keras.models.load_model(os.path.join(MODELS_DIR, MODEL_NAME))

files = sorted(f for f in os.listdir(TEST_DIR) if f.lower().endswith(EXTENSIONS))

print("\n" + "=" * 70)
print("EXTERNAL (UNSEEN) IMAGE EVALUATION")
print("Model:", MODEL_NAME)
print("=" * 70)

per_class = {}
total = 0
correct = 0

for filename in files:

    true_label = true_class_from_name(filename)
    if true_label is None:
        print(f"SKIPPED (unknown class in file name): {filename}")
        continue

    try:
        image = Image.open(os.path.join(TEST_DIR, filename)).convert("RGB")
        image = image.resize(IMG_SIZE)

        # The model has its own Rescaling layer: pass raw 0-255 pixels.
        image_array = np.expand_dims(np.array(image, dtype=np.float32), axis=0)

        probs = model.predict(image_array, verbose=0)[0]
        idx = int(np.argmax(probs))
        predicted = class_names[idx]
        confidence = probs[idx] * 100

        ok = predicted == true_label
        total += 1
        correct += int(ok)

        stats = per_class.setdefault(true_label, [0, 0])
        stats[0] += int(ok)
        stats[1] += 1

        print(
            f"{filename:20s} true={true_label:12s} "
            f"pred={predicted:12s} {confidence:6.2f}%  "
            f"{'CORRECT' if ok else 'WRONG'}"
        )

    except Exception as e:
        print(f"ERROR: {filename}: {e}")

print("\n" + "=" * 70)
print("SUMMARY")
print("=" * 70)

for label in class_names:
    if label in per_class:
        c, n = per_class[label]
        print(f"{label:12s}: {c}/{n} correct")
    else:
        print(f"{label:12s}: no images")

if total > 0:
    print(f"\nOverall: {correct}/{total} correct ({correct / total * 100:.2f}%)")
print("=" * 70)
print("Note: a small image set gives only a rough idea.\n")