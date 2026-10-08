import os
import sys
import numpy as np
import tensorflow as tf
from PIL import Image


# ============================================================
# PATHS (relative to the project folder, so they work on any laptop)
# Expected layout:  <project>/scripts/predict_image.py
#                   <project>/models/...
# ============================================================

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MODEL_PATH = os.path.join(
    BASE_DIR, "models", "safecity_mobilenetv2_fighting_finetuned.keras"
)
CLASS_FILE = os.path.join(BASE_DIR, "models", "class_names.txt")

IMG_SIZE = (224, 224)


# ============================================================
# CHECK IMAGE ARGUMENT
# ============================================================

if len(sys.argv) < 2:
    print("\nUsage:")
    print(r'python scripts\predict_image.py "C:\path\to\image.jpg"')
    sys.exit()

IMAGE_PATH = sys.argv[1]


# ============================================================
# LOAD MODEL AND CLASS NAMES
# ============================================================

print("\n========== LOADING MODEL ==========\n")

model = tf.keras.models.load_model(MODEL_PATH)

with open(CLASS_FILE, "r", encoding="utf-8") as f:
    class_names = [line.strip() for line in f if line.strip()]

print("Classes:")
for i, name in enumerate(class_names):
    print(i, "=", name)


# ============================================================
# LOAD IMAGE
# ============================================================

print("\n========== LOADING IMAGE ==========\n")
print("Image:", IMAGE_PATH)

image = Image.open(IMAGE_PATH).convert("RGB")
image = image.resize(IMG_SIZE)


# ============================================================
# PREPROCESSING
# ============================================================
#
# IMPORTANT: the model already contains its own Rescaling layer.
# Pass RAW pixel values (0-255). Do NOT divide by 255 or by 127.5
# here, otherwise the image is scaled twice and predictions become wrong.
# This is exactly what the evaluation scripts do.
# ============================================================

image_array = np.array(image, dtype=np.float32)
image_array = np.expand_dims(image_array, axis=0)


# ============================================================
# PREDICTION
# ============================================================

print("\n========== PREDICTING ==========\n")

predictions = model.predict(image_array, verbose=0)[0]
top_indices = np.argsort(predictions)[::-1]

print("Top Predictions:\n")
for rank, index in enumerate(top_indices[:len(class_names)], start=1):
    print(f"{rank}. {class_names[index]:15s} {predictions[index] * 100:.2f}%")

best_index = top_indices[0]
best_class = class_names[best_index]
best_confidence = predictions[best_index] * 100

print("\n===================================")
print("FINAL PREDICTION")
print("===================================")
print("Class      :", best_class)
print(f"Confidence : {best_confidence:.2f}%")

print("\n========== DONE ==========\n")