import os
import shutil
import random

SOURCE = r"F:\Accident\Accident\Accident_Detection\Dataset"
DEST = r"F:\SafeCity_FYP\AI\dataset"

TRAIN_COUNT = 1000
VALIDATION_COUNT = 200
TEST_COUNT = 200


def get_images(folder):
    extensions = (".jpg", ".jpeg", ".png", ".bmp", ".webp")

    return [
        os.path.join(folder, file)
        for file in os.listdir(folder)
        if file.lower().endswith(extensions)
    ]


def copy_images(source_folder, destination_folder, count, prefix):
    images = get_images(source_folder)
    random.shuffle(images)

    os.makedirs(destination_folder, exist_ok=True)

    copied = 0
    skipped = 0

    for source_file in images:

        if copied >= count:
            break

        extension = os.path.splitext(source_file)[1]

        destination_file = os.path.join(
            destination_folder,
            f"{prefix}_{copied + 1:04d}{extension}"
        )

        try:
            shutil.copy2(source_file, destination_file)
            copied += 1

        except (FileNotFoundError, PermissionError, OSError):
            skipped += 1
            continue

    print(f"{prefix}:")
    print(f"  Required : {count}")
    print(f"  Copied   : {copied}")
    print(f"  Skipped  : {skipped}")
    print()


def main():

    print("Preparing Accident dataset...")
    print()

    train_source = os.path.join(SOURCE, "train", "images")
    valid_source = os.path.join(SOURCE, "valid", "images")
    test_source = os.path.join(SOURCE, "test", "images")

    train_destination = os.path.join(
        DEST, "train", "accident"
    )

    validation_destination = os.path.join(
        DEST, "validation", "accident"
    )

    test_destination = os.path.join(
        DEST, "test", "accident"
    )

    copy_images(
        train_source,
        train_destination,
        TRAIN_COUNT,
        "accident_train"
    )

    copy_images(
        valid_source,
        validation_destination,
        VALIDATION_COUNT,
        "accident_validation"
    )

    copy_images(
        test_source,
        test_destination,
        TEST_COUNT,
        "accident_test"
    )

    print("===================================")
    print("Accident dataset preparation DONE!")
    print("===================================")


if __name__ == "__main__":
    main()