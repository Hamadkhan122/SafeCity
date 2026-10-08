import os
import tensorflow as tf
from tensorflow.keras import layers, models
from tensorflow.keras.applications import MobileNetV2
from tensorflow.keras.callbacks import (
    EarlyStopping,
    ModelCheckpoint,
    ReduceLROnPlateau
)

# ============================================================
# PATHS
# ============================================================

DATASET_DIR = r".\dataset"
MODEL_DIR = r".\models"

TRAIN_DIR = os.path.join(DATASET_DIR, "train")
VAL_DIR = os.path.join(DATASET_DIR, "validation")
TEST_DIR = os.path.join(DATASET_DIR, "test")

IMG_SIZE = (224, 224)
BATCH_SIZE = 32
SEED = 42

os.makedirs(MODEL_DIR, exist_ok=True)

# ============================================================
# LOAD DATASETS
# ============================================================

print("\n========== LOADING DATASETS ==========\n")

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
for i, name in enumerate(class_names):
    print(i, "=", name)

print("\nNumber of classes:", len(class_names))

# Safety check
expected_classes = {
    "accident",
    "fighting",
    "fire",
    "road_damage"
}

if set(class_names) != expected_classes:
    raise ValueError(
        f"\nUnexpected classes found: {class_names}\n"
        f"Expected exactly: {sorted(expected_classes)}"
    )

# ============================================================
# PERFORMANCE
# ============================================================

AUTOTUNE = tf.data.AUTOTUNE

train_ds = train_ds.prefetch(AUTOTUNE)
val_ds = val_ds.prefetch(AUTOTUNE)
test_ds = test_ds.prefetch(AUTOTUNE)

# ============================================================
# DATA AUGMENTATION
# ============================================================

data_augmentation = tf.keras.Sequential([
    layers.RandomFlip("horizontal"),
    layers.RandomRotation(0.08),
    layers.RandomZoom(0.15),
    layers.RandomTranslation(
        height_factor=0.08,
        width_factor=0.08
    ),
    layers.RandomContrast(0.15),
], name="data_augmentation")

# ============================================================
# MOBILENETV2
# ============================================================

print("\n========== BUILDING MOBILENETV2 ==========\n")

base_model = MobileNetV2(
    input_shape=(224, 224, 3),
    include_top=False,
    weights="imagenet"
)

# Stage 1: frozen
base_model.trainable = False

model = models.Sequential([
    layers.Input(shape=(224, 224, 3)),

    data_augmentation,

    layers.Rescaling(
        1.0 / 127.5,
        offset=-1
    ),

    base_model,

    layers.GlobalAveragePooling2D(),

    layers.Dropout(0.35),

    layers.Dense(
        len(class_names),
        activation="softmax"
    )
])

# ============================================================
# STAGE 1 TRAINING
# ============================================================

model.compile(
    optimizer=tf.keras.optimizers.Adam(
        learning_rate=1e-4
    ),
    loss="sparse_categorical_crossentropy",
    metrics=["accuracy"]
)

stage1_path = os.path.join(
    MODEL_DIR,
    "safecity_mobilenetv2_stage1.keras"
)

callbacks_stage1 = [
    EarlyStopping(
        monitor="val_loss",
        patience=4,
        restore_best_weights=True
    ),

    ModelCheckpoint(
        stage1_path,
        monitor="val_accuracy",
        save_best_only=True
    ),

    ReduceLROnPlateau(
        monitor="val_loss",
        factor=0.5,
        patience=2,
        min_lr=1e-7
    )
]

print("\n==========================================")
print("STAGE 1: FROZEN MOBILENETV2")
print("==========================================\n")

history1 = model.fit(
    train_ds,
    validation_data=val_ds,
    epochs=12,
    callbacks=callbacks_stage1
)

# ============================================================
# STAGE 2: FINE-TUNING
# ============================================================

print("\n==========================================")
print("STAGE 2: FINE-TUNING MOBILENETV2")
print("==========================================\n")

base_model.trainable = True

# Freeze early layers.
# Only the later feature-extraction layers will be fine-tuned.
fine_tune_from = 100

for layer in base_model.layers[:fine_tune_from]:
    layer.trainable = False

# Keep BatchNorm layers frozen for stable fine-tuning.
for layer in base_model.layers:
    if isinstance(layer, layers.BatchNormalization):
        layer.trainable = False

model.compile(
    optimizer=tf.keras.optimizers.Adam(
        learning_rate=1e-5
    ),
    loss="sparse_categorical_crossentropy",
    metrics=["accuracy"]
)

final_model_path = os.path.join(
    MODEL_DIR,
    "safecity_mobilenetv2_final.keras"
)

callbacks_stage2 = [
    EarlyStopping(
        monitor="val_loss",
        patience=5,
        restore_best_weights=True
    ),

    ModelCheckpoint(
        final_model_path,
        monitor="val_accuracy",
        save_best_only=True
    ),

    ReduceLROnPlateau(
        monitor="val_loss",
        factor=0.5,
        patience=2,
        min_lr=1e-8
    )
]

history2 = model.fit(
    train_ds,
    validation_data=val_ds,
    epochs=15,
    callbacks=callbacks_stage2
)

# ============================================================
# TEST
# ============================================================

print("\n==========================================")
print("FINAL TEST")
print("==========================================\n")

test_loss, test_accuracy = model.evaluate(
    test_ds,
    verbose=1
)

print("\n==========================================")
print("FINAL RESULTS")
print("==========================================")

print(f"\nTest Loss     : {test_loss:.4f}")
print(f"Test Accuracy : {test_accuracy * 100:.2f}%")

# ============================================================
# SAVE FINAL MODEL
# ============================================================

model.save(
    os.path.join(
        MODEL_DIR,
        "safecity_mobilenetv2_final.keras"
    )
)

# ============================================================
# SAVE CLASS NAMES
# ============================================================

class_file = os.path.join(
    MODEL_DIR,
    "class_names.txt"
)

with open(class_file, "w") as f:
    for name in class_names:
        f.write(name + "\n")

print("\n==========================================")
print("MODEL TRAINING COMPLETE")
print("==========================================")

print("\nFinal model:")
print(
    os.path.join(
        MODEL_DIR,
        "safecity_mobilenetv2_final.keras"
    )
)

print("\nClass names:")
print(class_file)

print("\nClasses:")
for name in class_names:
    print("-", name)

print("\n========== DONE ==========\n")