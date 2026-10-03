import os
import numpy as np
import tensorflow as tf
from PIL import Image

MODEL_PATH = r".\models\safecity_mobilenetv2_fighting_finetuned.keras"
TEST_DIR = r".\test_images"

model = tf.keras.models.load_model(MODEL_PATH)

class_names = [
    "accident",
    "fighting",
    "fire",
    "road_damage"
]

image_extensions = (
    ".jpg",
    ".jpeg",
    ".jfif",
    ".png",
    ".webp"
)

fighting_images = [
    f for f in os.listdir(TEST_DIR)
    if f.lower().endswith(image_extensions)
    and f.lower().startswith(("fight", "fighting"))
]

fighting_images.sort()

print("\n" + "=" * 70)
print("FINE-TUNED MODEL - EXTERNAL FIGHTING EVALUATION")
print("=" * 70)

correct = 0
total = len(fighting_images)

for filename in fighting_images:

    path = os.path.join(TEST_DIR, filename)

    try:
        image = Image.open(path).convert("RGB")
        image = image.resize((224, 224))

        # IMPORTANT:
        # Model already contains its own Rescaling layer.
        image_array = np.array(
            image,
            dtype=np.float32
        )

        image_array = np.expand_dims(
            image_array,
            axis=0
        )

        predictions = model.predict(
            image_array,
            verbose=0
        )[0]

        predicted_index = np.argmax(predictions)
        predicted_class = class_names[predicted_index]
        confidence = predictions[predicted_index] * 100

        is_correct = predicted_class == "fighting"

        if is_correct:
            correct += 1

        status = "CORRECT" if is_correct else "WRONG"

        print("\n" + "-" * 70)
        print(f"Image      : {filename}")
        print(f"Prediction : {predicted_class}")
        print(f"Confidence : {confidence:.2f}%")
        print(f"Status     : {status}")

        print("\nProbabilities:")

        for cls, prob in zip(class_names, predictions):
            print(
                f"  {cls:12s}: "
                f"{prob * 100:6.2f}%"
            )

    except Exception as e:
        print(f"\n{filename}")
        print(f"ERROR: {e}")

print("\n" + "=" * 70)
print("FINAL EXTERNAL RESULT")
print("=" * 70)

if total > 0:

    accuracy = (
        correct / total
    ) * 100

    print(f"Total images : {total}")
    print(f"Correct      : {correct}")
    print(f"Wrong        : {total - correct}")
    print(f"Accuracy     : {accuracy:.2f}%")

print("=" * 70)