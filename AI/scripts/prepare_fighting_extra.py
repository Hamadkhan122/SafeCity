import os
import shutil
import random

SOURCE_DIR = r".\dataset\train\fighting_extra"

TRAIN_DIR = r".\dataset\train\fighting"
VAL_DIR = r".\dataset\validation\fighting"
TEST_DIR = r".\dataset\test\fighting"

SEED = 42

TRAIN_EXTRA = 480
VAL_EXTRA = 60
TEST_EXTRA = 60

VALID_EXTENSIONS = (
    ".jpg",
    ".jpeg",
    ".png",
    ".jfif",
    ".webp"
)

print("=" * 70)
print("ADDING EXTRA FIGHTING DATA")
print("=" * 70)

images = [
    f for f in os.listdir(SOURCE_DIR)
    if f.lower().endswith(VALID_EXTENSIONS)
]

print(f"\nExtra images found: {len(images)}")

expected = TRAIN_EXTRA + VAL_EXTRA + TEST_EXTRA

if len(images) != expected:
    raise ValueError(
        f"Expected {expected} images, but found {len(images)}."
    )

random.seed(SEED)
random.shuffle(images)

train_images = images[:TRAIN_EXTRA]
val_images = images[
    TRAIN_EXTRA:TRAIN_EXTRA + VAL_EXTRA
]
test_images = images[
    TRAIN_EXTRA + VAL_EXTRA:
]

os.makedirs(TRAIN_DIR, exist_ok=True)
os.makedirs(VAL_DIR, exist_ok=True)
os.makedirs(TEST_DIR, exist_ok=True)

def copy_images(image_list, destination):
    copied = 0

    for filename in image_list:
        source = os.path.join(
            SOURCE_DIR,
            filename
        )

        new_name = "extra_" + filename

        destination_path = os.path.join(
            destination,
            new_name
        )

        shutil.copy2(
            source,
            destination_path
        )

        copied += 1

    return copied


train_count = copy_images(
    train_images,
    TRAIN_DIR
)

val_count = copy_images(
    val_images,
    VAL_DIR
)

test_count = copy_images(
    test_images,
    TEST_DIR
)

print("\n" + "=" * 70)
print("RESULT")
print("=" * 70)

print(f"Added to TRAIN      : {train_count}")
print(f"Added to VALIDATION : {val_count}")
print(f"Added to TEST       : {test_count}")

print("\nFinal Fighting counts:")
print(f"TRAIN      : 1000 + {train_count} = {1000 + train_count}")
print(f"VALIDATION : 200 + {val_count} = {200 + val_count}")
print(f"TEST       : 200 + {test_count} = {200 + test_count}")

# Remove temporary folder
shutil.rmtree(SOURCE_DIR)

print("\nTemporary fighting_extra folder removed.")

print("=" * 70)
print("DONE")
print("=" * 70)