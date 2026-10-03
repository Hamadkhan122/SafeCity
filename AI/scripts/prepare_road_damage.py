import os
import random
import shutil

# ==========================================
# ROAD DAMAGE DATASET
# ==========================================

SOURCE = r"F:\Road damage and defect\N-RDD2024Road damage and defect"

TRAIN_SOURCE = os.path.join(
    SOURCE,
    "Training and Validation Dataset",
    "train",
    "images"
)

VALIDATION_SOURCE = os.path.join(
    SOURCE,
    "Training and Validation Dataset",
    "valid",
    "images"
)

# We will search all folders inside Test Dataset
TEST_SOURCE = os.path.join(
    SOURCE,
    "Test Dataset"
)

# ==========================================
# SAFECITY DESTINATION
# ==========================================

DEST = r".\dataset"

TRAIN_COUNT = 1000
VALIDATION_COUNT = 200
TEST_COUNT = 200

random.seed(42)


# ==========================================
# GET IMAGES FROM ONE FOLDER
# ==========================================

def get_images(folder):

    images = []

    if not os.path.exists(folder):

        print("Folder not found:")
        print(folder)

        return images

    for filename in os.listdir(folder):

        file_path = os.path.join(
            folder,
            filename
        )

        if not os.path.isfile(file_path):
            continue

        name, ext = os.path.splitext(filename)

        if ext.lower() not in [
            ".jpg",
            ".jpeg",
            ".png",
            ".bmp",
            ".webp"
        ]:
            continue

        images.append(file_path)

    return images


# ==========================================
# GET IMAGES RECURSIVELY
# ==========================================

def get_images_recursive(folder):

    images = []

    if not os.path.exists(folder):

        print("Folder not found:")
        print(folder)

        return images

    for root, dirs, files in os.walk(folder):

        for filename in files:

            file_path = os.path.join(
                root,
                filename
            )

            name, ext = os.path.splitext(filename)

            if ext.lower() not in [
                ".jpg",
                ".jpeg",
                ".png",
                ".bmp",
                ".webp"
            ]:
                continue

            images.append(file_path)

    return images


# ==========================================
# COPY IMAGES
# ==========================================

def copy_images(
    image_list,
    destination,
    required_count
):

    os.makedirs(
        destination,
        exist_ok=True
    )

    random.shuffle(image_list)

    copied = 0
    skipped = 0

    for image_path in image_list:

        if copied >= required_count:
            break

        filename = os.path.basename(
            image_path
        )

        destination_path = os.path.join(
            destination,
            filename
        )

        # Avoid duplicate filename problem
        if os.path.exists(destination_path):

            base, ext = os.path.splitext(
                filename
            )

            filename = (
                base
                + "_"
                + str(copied)
                + ext
            )

            destination_path = os.path.join(
                destination,
                filename
            )

        try:

            shutil.copy2(
                image_path,
                destination_path
            )

            copied += 1

        except (
            FileNotFoundError,
            PermissionError,
            OSError
        ):

            skipped += 1

    return copied, skipped


# ==========================================
# START
# ==========================================

print()
print("===================================")
print("Preparing Road Damage Dataset")
print("===================================")
print()


# ==========================================
# TRAIN
# ==========================================

print("Scanning TRAIN Road Damage images...")

train_images = get_images(
    TRAIN_SOURCE
)

print(
    f"Images found in TRAIN: {len(train_images)}"
)

print()


if len(train_images) < TRAIN_COUNT:

    print("ERROR!")

    print(
        f"Required: {TRAIN_COUNT}"
    )

    print(
        f"Found: {len(train_images)}"
    )

    exit()


# ==========================================
# VALIDATION
# ==========================================

print(
    "Scanning VALIDATION Road Damage images..."
)

validation_images = get_images(
    VALIDATION_SOURCE
)

print(
    f"Images found in VALIDATION: {len(validation_images)}"
)

print()


if len(validation_images) < VALIDATION_COUNT:

    print("ERROR!")

    print(
        f"Required: {VALIDATION_COUNT}"
    )

    print(
        f"Found: {len(validation_images)}"
    )

    exit()


# ==========================================
# TEST
# ==========================================

print("Scanning TEST Road Damage images...")

test_images = get_images_recursive(
    TEST_SOURCE
)

print(
    f"Images found in TEST: {len(test_images)}"
)

print()


if len(test_images) < TEST_COUNT:

    print("ERROR!")

    print(
        f"Required: {TEST_COUNT}"
    )

    print(
        f"Found: {len(test_images)}"
    )

    exit()


# ==========================================
# DESTINATIONS
# ==========================================

train_destination = os.path.join(
    DEST,
    "train",
    "road_damage"
)

validation_destination = os.path.join(
    DEST,
    "validation",
    "road_damage"
)

test_destination = os.path.join(
    DEST,
    "test",
    "road_damage"
)


# ==========================================
# COPY TRAIN
# ==========================================

print("Copying TRAIN Road Damage images...")

train_copied, train_skipped = copy_images(
    train_images,
    train_destination,
    TRAIN_COUNT
)

print(
    f"  Required : {TRAIN_COUNT}"
)

print(
    f"  Copied   : {train_copied}"
)

print(
    f"  Skipped  : {train_skipped}"
)

print()


# ==========================================
# COPY VALIDATION
# ==========================================

print(
    "Copying VALIDATION Road Damage images..."
)

validation_copied, validation_skipped = copy_images(
    validation_images,
    validation_destination,
    VALIDATION_COUNT
)

print(
    f"  Required : {VALIDATION_COUNT}"
)

print(
    f"  Copied   : {validation_copied}"
)

print(
    f"  Skipped  : {validation_skipped}"
)

print()


# ==========================================
# COPY TEST
# ==========================================

print("Copying TEST Road Damage images...")

test_copied, test_skipped = copy_images(
    test_images,
    test_destination,
    TEST_COUNT
)

print(
    f"  Required : {TEST_COUNT}"
)

print(
    f"  Copied   : {test_copied}"
)

print(
    f"  Skipped  : {test_skipped}"
)

print()


# ==========================================
# DONE
# ==========================================

print("===================================")
print("Road Damage Dataset DONE!")
print("===================================")

print()

print("Final structure:")

print()

print(train_destination)

print(validation_destination)

print(test_destination)

print()

print("Expected:")

print(
    f"Train      : {TRAIN_COUNT}"
)

print(
    f"Validation : {VALIDATION_COUNT}"
)

print(
    f"Test       : {TEST_COUNT}"
)

print()

print(
    "Total      :",
    TRAIN_COUNT
    + VALIDATION_COUNT
    + TEST_COUNT
)

print()