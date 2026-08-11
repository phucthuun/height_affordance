# # Transfer learning from SuperAnimal-HumanBody (not supported)
# from deeplabcut.modelzoo import build_weight_init

# deeplabcut.merge_datasets(config_path)

# weight_init = build_weight_init(
#     cfg=config_path,
#     super_animal="superanimal_humanbody",
#     model_name="rtmpose_x",
#     detector_name="fasterrcnn_resnet50_fpn_v2",
#     with_decoder=False,   # required for the transfer_learning=True path below
# )

# deeplabcut.create_training_dataset(config_path, weight_init=weight_init)

# deeplabcut.train_network(
#     config_path,
#     epochs=100,                      # small correction set → don't need thousands of epochs
#     superanimal_name="superanimal_humanbody",
#     superanimal_transfer_learning=True,
# )

# deeplabcut.evaluate_network(config_path, plotting=True)


import deeplabcut
import re
from pathlib import Path

# 1. Interactive Target Selection
print("============ SuperAnimal Zero-Shot Inference ============")
sub_in = input("Enter Subject ID (e.g., MH9HXJ): ").strip() or "MH9HXJ"
ses_in = input("Enter Session ID (e.g., S001): ").strip() or "S001"
run_in = input("Enter Run ID (e.g., 001): ").strip() or "001"
cam_in = input("Camera view - 's' for SideView, 'u' for UpperView [default: s]: ").strip().lower() or "s"
mach_in = input("Training machine - 'local' or 'tardis' [default: local]: ").strip().lower() or "local"

subLabel = re.sub(r'^sub-', '', sub_in)
sesLabel = re.sub(r'^ses-', '', ses_in)
runLabel = re.sub(r'^run-', '', run_in).zfill(3)

subID = f"sub-{subLabel}"
sesID = f"ses-{sesLabel}"
runID = f"run-{runLabel}"

camera_view = "UpperView" if cam_in == "u" else "SideView"
detector_name = "fasterrcnn_resnet50_fpn_v2" if mach_in == "tardis" else "fasterrcnn_mobilenet_v3_large_fpn"

# Base directory where heightaffordance-* subfolder lives
base_dir = Path(rf"C:\Data\Research\10_Data\derivatives\dlc_superanimal\{subID}\{sesID}\{camera_view}")

# Find matching config.yaml file(s) using wildcards
matching_configs = list(base_dir.glob("heightaffordance-*/config.yaml"))

if matching_configs:
    config_path = str(matching_configs[0])  # Takes the first match found
    print(f"\nFound config at: {config_path}")
else:
    print(f"\nError: Could not find any 'heightaffordance-*/config.yaml' inside {base_dir}")
    config_path = None

deeplabcut.merge_datasets(config_path)   # only proceeds once all folders show CollectedData_*.h5

deeplabcut.create_training_dataset(config_path)  # no weight_init -> defaults to ImageNet-pretrained backbone

deeplabcut.train_network(config_path, maxiters=20000, displayiters=100, saveiters=1000)  # budget more epochs than the transfer-learning path needed

deeplabcut.evaluate_network(config_path, plotting=True)