import os
import random
import shutil

SOURCE = r"F:\D-Fire"
DEST = r"F:\SafeCity_FYP\AI\dataset"

TRAIN_COUNT = 1000
VALIDATION_COUNT = 200
TEST_COUNT = 200

FIRE_CLASS_ID = "1"

random.seed(42)


def get_fire_images(images_dir, labels_dir):
    fire_images = []

    if not os.path.exists(images_dir):
        print(f"Images folder not found: {images_dir}")
        return fire_images

    if not os.path.exists(labels_dir):
        print(f"Labels folder not found: {labels_dir}")
        return fire_images

    for filename in os.listdir(images_dir):

        image_path = os.path.join(images_dir, filename)

        if not os.path.isfile(image_path):
            continue

        name, ext = os.path.splitext(filename)

        if ext.lower() not in [".jpg", ".jpeg", ".png", ".bmp", ".webp"]:
            continue

        label_path = os.path.join(labels_dir, name + ".txt")

        if not os.path.exists(label_path):
            continue

        try:
            with open(label_path, "r") as f:
                lines = f.readlines()

            contains_fire = False

            for line in lines:

                parts = line.strip().split()

                if not parts:
                    continue

                class_id = parts[0]

                if class_id == FIRE_CLASS_ID:
                    contains_fire = True
                    break

            if contains_fire:
                fire_images.append(image_path)

        except (OSError, UnicodeDecodeError):
            continue

    return fire_images


def copy_images(image_list, destination, required_count):

    os.makedirs(destination, exist_ok=True)

    random.shuffle(image_list)

    copied = 0
    skipped = 0

    for image_path in image_list:

        if copied >= required_count:
            break

        filename = os.path.basename(image_path)

        destination_path = os.path.join(destination, filename)

        try:
            shutil.copy2(image_path, destination_path)
            copied += 1

        except (FileNotFoundError, PermissionError, OSError):
            skipped += 1

    return copied, skipped


print()
print("===================================")
print("Preparing D-Fire Fire Dataset")
print("===================================")
print()


train_images_dir = os.path.join(SOURCE, "train", "images")
train_labels_dir = os.path.join(SOURCE, "train", "labels")

test_images_dir = os.path.join(SOURCE, "test", "images")
test_labels_dir = os.path.join(SOURCE, "test", "labels")


print("Scanning TRAIN images for Fire...")

train_fire_images = get_fire_images(
    train_images_dir,
    train_labels_dir
)

print(f"Fire images found in TRAIN: {len(train_fire_images)}")
print()


if len(train_fire_images) < TRAIN_COUNT + VALIDATION_COUNT:

    print("ERROR!")
    print("Not enough fire images in train dataset.")
    print(f"Required: {TRAIN_COUNT + VALIDATION_COUNT}")
    print(f"Found: {len(train_fire_images)}")

    exit()


random.shuffle(train_fire_images)

train_selection = train_fire_images[:TRAIN_COUNT]

validation_selection = train_fire_images[
    TRAIN_COUNT:TRAIN_COUNT + VALIDATION_COUNT
]


train_destination = os.path.join(
    DEST,
    "train",
    "fire"
)

validation_destination = os.path.join(
    DEST,
    "validation",
    "fire"
)


print("Copying TRAIN Fire images...")

train_copied, train_skipped = copy_images(
    train_selection,
    train_destination,
    TRAIN_COUNT
)

print(f"  Required : {TRAIN_COUNT}")
print(f"  Copied   : {train_copied}")
print(f"  Skipped  : {train_skipped}")
print()


print("Copying VALIDATION Fire images...")

validation_copied, validation_skipped = copy_images(
    validation_selection,
    validation_destination,
    VALIDATION_COUNT
)

print(f"  Required : {VALIDATION_COUNT}")
print(f"  Copied   : {validation_copied}")
print(f"  Skipped  : {validation_skipped}")
print()


print("Scanning TEST images for Fire...")

test_fire_images = get_fire_images(
    test_images_dir,
    test_labels_dir
)

print(f"Fire images found in TEST: {len(test_fire_images)}")
print()


if len(test_fire_images) < TEST_COUNT:

    print("ERROR!")
    print("Not enough fire images in test dataset.")
    print(f"Required: {TEST_COUNT}")
    print(f"Found: {len(test_fire_images)}")

    exit()


test_destination = os.path.join(
    DEST,
    "test",
    "fire"
)


print("Copying TEST Fire images...")

test_copied, test_skipped = copy_images(
    test_fire_images,
    test_destination,
    TEST_COUNT
)

print(f"  Required : {TEST_COUNT}")
print(f"  Copied   : {test_copied}")
print(f"  Skipped  : {test_skipped}")
print()


print("===================================")
print("D-Fire Fire Dataset DONE!")
print("===================================")

print()

print("Final structure:")
print()

print(train_destination)
print(validation_destination)
print(test_destination)

print()

print("Expected:")
print(f"Train      : {TRAIN_COUNT}")
print(f"Validation : {VALIDATION_COUNT}")
print(f"Test       : {TEST_COUNT}")

print()

print(
    "Total      :",
    TRAIN_COUNT + VALIDATION_COUNT + TEST_COUNT
)

print()