import os
import tensorflow as tf
from tensorflow.keras.callbacks import (
    EarlyStopping,
    ModelCheckpoint,
    ReduceLROnPlateau
)

MODEL_DIR = r".\models"
DATASET_DIR = r".\dataset"

TRAIN_DIR = os.path.join(DATASET_DIR, "train")
VAL_DIR = os.path.join(DATASET_DIR, "validation")
TEST_DIR = os.path.join(DATASET_DIR, "test")

IMG_SIZE = (224, 224)
BATCH_SIZE = 32
SEED = 42

OLD_MODEL = os.path.join(
    MODEL_DIR,
    "safecity_mobilenetv2_final.keras"
)

NEW_MODEL = os.path.join(
    MODEL_DIR,
    "safecity_mobilenetv2_fighting_finetuned.keras"
)

print("=" * 70)
print("SAFE CITY - FIGHTING FINE-TUNING")
print("=" * 70)

# --------------------------------------------------
# DATASETS
# --------------------------------------------------

train_ds = tf.keras.utils.image_dataset_from_directory(
    TRAIN_DIR,
    image_size=IMG_SIZE,
    batch_size=BATCH_SIZE,
    shuffle=True,
    seed=SEED
)

val_ds = tf.keras.utils.image_dataset_from_directory(
    VAL_DIR,
    image_size=IMG_SIZE,
    batch_size=BATCH_SIZE,
    shuffle=False
)

test_ds = tf.keras.utils.image_dataset_from_directory(
    TEST_DIR,
    image_size=IMG_SIZE,
    batch_size=BATCH_SIZE,
    shuffle=False
)

class_names = train_ds.class_names

print("\nClasses:")
print(class_names)

expected_classes = {
    "accident",
    "fighting",
    "fire",
    "road_damage"
}

if set(class_names) != expected_classes:
    raise ValueError(
        f"Unexpected classes: {class_names}"
    )

# --------------------------------------------------
# PREFETCH
# --------------------------------------------------

AUTOTUNE = tf.data.AUTOTUNE

train_ds = train_ds.prefetch(AUTOTUNE)
val_ds = val_ds.prefetch(AUTOTUNE)
test_ds = test_ds.prefetch(AUTOTUNE)

# --------------------------------------------------
# CLASS WEIGHTS
# --------------------------------------------------
# Fighting has more images now.
# These weights reduce the effect of class imbalance.

class_counts = {
    "accident": 1000,
    "fighting": 1480,
    "fire": 1000,
    "road_damage": 1000
}

total_samples = sum(class_counts.values())
num_classes = len(class_counts)

class_weight = {}

for index, class_name in enumerate(class_names):
    class_weight[index] = (
        total_samples /
        (num_classes * class_counts[class_name])
    )

print("\nClass weights:")
for index, weight in class_weight.items():
    print(
        f"{class_names[index]:12s}: "
        f"{weight:.4f}"
    )

# --------------------------------------------------
# LOAD EXISTING MODEL
# --------------------------------------------------

print("\nLoading existing MobileNetV2 model...")

model = tf.keras.models.load_model(
    OLD_MODEL
)

print("Existing model loaded.")

# --------------------------------------------------
# FREEZE / UNFREEZE
# --------------------------------------------------

# Find MobileNetV2 base model
base_model = None

for layer in model.layers:
    if "mobilenetv2" in layer.name.lower():
        base_model = layer
        break

if base_model is None:
    raise ValueError(
        "MobileNetV2 base model not found."
    )

# Fine-tune deeper layers.
base_model.trainable = True

fine_tune_from = 100

for layer in base_model.layers[:fine_tune_from]:
    layer.trainable = False

# Keep BatchNorm frozen for stable fine-tuning.
for layer in base_model.layers:
    if isinstance(
        layer,
        tf.keras.layers.BatchNormalization
    ):
        layer.trainable = False

print(
    f"\nFine-tuning MobileNetV2 from layer "
    f"{fine_tune_from} onward."
)

# --------------------------------------------------
# COMPILE
# --------------------------------------------------

model.compile(
    optimizer=tf.keras.optimizers.Adam(
        learning_rate=5e-6
    ),
    loss="sparse_categorical_crossentropy",
    metrics=["accuracy"]
)

# --------------------------------------------------
# CALLBACKS
# --------------------------------------------------

callbacks = [
    EarlyStopping(
        monitor="val_accuracy",
        patience=5,
        mode="max",
        restore_best_weights=True
    ),

    ModelCheckpoint(
        NEW_MODEL,
        monitor="val_accuracy",
        mode="max",
        save_best_only=True
    ),

    ReduceLROnPlateau(
        monitor="val_loss",
        factor=0.5,
        patience=2,
        min_lr=1e-8
    )
]

# --------------------------------------------------
# TRAIN
# --------------------------------------------------

print("\nStarting fine-tuning...\n")

history = model.fit(
    train_ds,
    validation_data=val_ds,
    epochs=15,
    class_weight=class_weight,
    callbacks=callbacks
)

# --------------------------------------------------
# TEST
# --------------------------------------------------

print("\n" + "=" * 70)
print("FINAL TEST")
print("=" * 70)

test_loss, test_accuracy = model.evaluate(
    test_ds,
    verbose=1
)

print(
    f"\nTest Loss     : {test_loss:.4f}"
)

print(
    f"Test Accuracy : "
    f"{test_accuracy * 100:.2f}%"
)

# --------------------------------------------------
# SAVE FINAL BEST MODEL
# --------------------------------------------------

model.save(NEW_MODEL)

# --------------------------------------------------
# CLASS NAMES
# --------------------------------------------------

class_file = os.path.join(
    MODEL_DIR,
    "class_names.txt"
)

with open(class_file, "w") as f:
    for name in class_names:
        f.write(name + "\n")

print("\n" + "=" * 70)
print("FINE-TUNING COMPLETE")
print("=" * 70)

print(
    f"Model saved at:\n{NEW_MODEL}"
)

print("=" * 70)