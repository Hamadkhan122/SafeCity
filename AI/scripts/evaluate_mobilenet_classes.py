import os
import numpy as np
import tensorflow as tf
from PIL import Image
from sklearn.metrics import (
    classification_report,
    confusion_matrix
)

MODEL_PATH = r".\models\safecity_mobilenetv2_fighting_finetuned.keras"
TEST_DIR = r".\dataset\test"

IMG_SIZE = (224, 224)

class_names = [
    "accident",
    "fighting",
    "fire",
    "road_damage"
]

model = tf.keras.models.load_model(MODEL_PATH)

y_true = []
y_pred = []

valid_extensions = (
    ".jpg",
    ".jpeg",
    ".png",
    ".jfif",
    ".webp"
)

print("=" * 70)
print("CLASS-WISE MOBILENET EVALUATION")
print("=" * 70)

for class_index, class_name in enumerate(class_names):

    class_dir = os.path.join(
        TEST_DIR,
        class_name
    )

    files = [
        f for f in os.listdir(class_dir)
        if f.lower().endswith(valid_extensions)
    ]

    print(
        f"{class_name:12s}: "
        f"{len(files)} images"
    )

    for filename in files:

        path = os.path.join(
            class_dir,
            filename
        )

        try:
            image = Image.open(path).convert("RGB")
            image = image.resize(IMG_SIZE)

            # IMPORTANT:
            # Model already contains Rescaling.
            image_array = np.array(
                image,
                dtype=np.float32
            )

            image_array = np.expand_dims(
                image_array,
                axis=0
            )

            prediction = model.predict(
                image_array,
                verbose=0
            )[0]

            predicted_index = int(
                np.argmax(prediction)
            )

            y_true.append(class_index)
            y_pred.append(predicted_index)

        except Exception as e:
            print(
                f"ERROR: {filename} -> {e}"
            )

print("\n" + "=" * 70)
print("CLASSIFICATION REPORT")
print("=" * 70)

print(
    classification_report(
        y_true,
        y_pred,
        target_names=class_names,
        digits=4
    )
)

print("=" * 70)
print("CONFUSION MATRIX")
print("=" * 70)

cm = confusion_matrix(
    y_true,
    y_pred
)

print("\nRows = Actual")
print("Columns = Predicted\n")

print(
    "              "
    + " ".join(
        f"{name:>12s}"
        for name in class_names
    )
)

for i, row in enumerate(cm):

    print(
        f"{class_names[i]:12s}"
        + " ".join(
            f"{value:12d}"
            for value in row
        )
    )

print("=" * 70)