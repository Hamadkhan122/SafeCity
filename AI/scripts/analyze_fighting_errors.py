import os
import sys
import shutil
import numpy as np
import tensorflow as tf
from PIL import Image


# ============================================================
# PATHS (relative to the project folder)
# ============================================================
#
# Usage:
#   python scripts\analyze_fighting_errors.py
#       -> uses the fine-tuned model (default)
#   python scripts\analyze_fighting_errors.py <other_model>.keras
#       -> uses another model file from the models folder
# ============================================================

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = os.path.join(BASE_DIR, "models")

MODEL_NAME = (
    sys.argv[1]
    if len(sys.argv) > 1
    else "safecity_mobilenetv2_fighting_finetuned.keras"
)

MODEL_PATH = os.path.join(MODELS_DIR, MODEL_NAME)
CLASS_FILE = os.path.join(MODELS_DIR, "class_names.txt")

FIGHTING_DIR = os.path.join(BASE_DIR, "dataset", "test", "fighting")
OUTPUT_DIR = os.path.join(MODELS_DIR, "fighting_errors")

IMG_SIZE = (224, 224)


# Start from a clean output folder so old results are not mixed in
if os.path.exists(OUTPUT_DIR):
    shutil.rmtree(OUTPUT_DIR)
os.makedirs(OUTPUT_DIR, exist_ok=True)


print("\n========== LOADING MODEL ==========\n")
print("Model:", MODEL_NAME)

model = tf.keras.models.load_model(MODEL_PATH)

with open(CLASS_FILE, "r", encoding="utf-8") as f:
    class_names = [line.strip() for line in f if line.strip()]

print("Classes:")
for i, name in enumerate(class_names):
    print(i, "=", name)


# Create folders for wrong predictions
for class_name in class_names:
    os.makedirs(
        os.path.join(OUTPUT_DIR, "predicted_" + class_name),
        exist_ok=True
    )


files = [
    f for f in os.listdir(FIGHTING_DIR)
    if f.lower().endswith((".jpg", ".jpeg", ".png", ".jfif", ".webp"))
]
files.sort()

correct = 0
wrong = 0
wrong_by_class = {}


print("\n========== ANALYZING FIGHTING IMAGES ==========\n")

for filename in files:

    image_path = os.path.join(FIGHTING_DIR, filename)

    try:
        image = Image.open(image_path).convert("RGB")
        image = image.resize(IMG_SIZE)

        # The model has its own Rescaling layer: pass raw 0-255 pixels.
        image_array = np.array(image, dtype=np.float32)
        image_array = np.expand_dims(image_array, axis=0)

        prediction = model.predict(image_array, verbose=0)[0]

        predicted_index = int(np.argmax(prediction))
        predicted_class = class_names[predicted_index]
        confidence = prediction[predicted_index] * 100

        if predicted_class == "fighting":
            correct += 1
        else:
            wrong += 1
            wrong_by_class[predicted_class] = (
                wrong_by_class.get(predicted_class, 0) + 1
            )

            destination = os.path.join(
                OUTPUT_DIR, "predicted_" + predicted_class, filename
            )
            shutil.copy2(image_path, destination)

            print(
                f"[WRONG] {filename} -> "
                f"{predicted_class} ({confidence:.2f}%)"
            )

    except Exception as e:
        print(f"[ERROR] {filename}: {e}")


print("\n==========================================")
print("FIGHTING ERROR ANALYSIS COMPLETE")
print("==========================================")

print(f"\nModel                  : {MODEL_NAME}")
print(f"Total Fighting images : {len(files)}")
print(f"Correct                : {correct}")
print(f"Wrong                  : {wrong}")

if len(files) > 0:
    print(f"Fighting accuracy      : {(correct / len(files)) * 100:.2f}%")

if wrong_by_class:
    print("\nWrong predictions by class:")
    for name, count in sorted(wrong_by_class.items()):
        print(f"  {name:12s}: {count}")

print("\nWrong images saved in:")
print(OUTPUT_DIR)

print("\n========== DONE ==========\n")