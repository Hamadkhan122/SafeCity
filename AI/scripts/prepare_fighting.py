import os
import shutil
import random

# Source folders
TRAIN_SOURCE = r"F:\archive\Train\Fighting"
TEST_SOURCE = r"F:\archive\Test\Fighting"

# Destination folders
BASE_DEST = r".\dataset"

TRAIN_DEST = os.path.join(BASE_DEST, "train", "fighting")
VAL_DEST = os.path.join(BASE_DEST, "validation", "fighting")
TEST_DEST = os.path.join(BASE_DEST, "test", "fighting")

# Required counts
TRAIN_COUNT = 1000
VAL_COUNT = 200
TEST_COUNT = 200

random.seed(42)


def get_images(folder):
    extensions = (".jpg", ".jpeg", ".png", ".bmp", ".webp")

    return [
        os.path.join(folder, file)
        for file in os.listdir(folder)
        if file.lower().endswith(extensions)
    ]


def copy_images(images, destination, count):
    os.makedirs(destination, exist_ok=True)

    random.shuffle(images)

    copied = 0
    skipped = 0

    for image in images:
        if copied >= count:
            break

        try:
            filename = os.path.basename(image)
            destination_file = os.path.join(destination, filename)

            if os.path.exists(destination_file):
                continue

            shutil.copy2(image, destination_file)
            copied += 1

        except Exception:
            skipped += 1

    return copied, skipped


# Get source images
train_images = get_images(TRAIN_SOURCE)
test_images = get_images(TEST_SOURCE)

print("\n========== FIGHTING DATASET ==========\n")

print(f"Train source images : {len(train_images)}")
print(f"Test source images  : {len(test_images)}")

# Train
train_copied, train_skipped = copy_images(
    train_images,
    TRAIN_DEST,
    TRAIN_COUNT
)

# Validation
val_copied, val_skipped = copy_images(
    train_images[TRAIN_COUNT:],
    VAL_DEST,
    VAL_COUNT
)

# Test
test_copied, test_skipped = copy_images(
    test_images,
    TEST_DEST,
    TEST_COUNT
)

print("\n========== RESULT ==========\n")

print(f"Train      : {train_copied} / {TRAIN_COUNT}")
print(f"Validation : {val_copied} / {VAL_COUNT}")
print(f"Test       : {test_copied} / {TEST_COUNT}")

print(f"\nTotal copied: {train_copied + val_copied + test_copied}")

print("\nSkipped:")
print(f"Train      : {train_skipped}")
print(f"Validation : {val_skipped}")
print(f"Test       : {test_skipped}")

print("\n======================================")