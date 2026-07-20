# STEP 4: Refine Labels
# This opens napari pre-loaded with the extracted frames + SuperAnimal's placed points, per video folder. 
# ---------------------------
# Instruction: For each flagged trial's frames
# (1) drag misplaced points to the correct spot
# (2) delete (middle-click) any point on an occluded/invisible body part
# (3) leave correct ones untouched. 
# TIPS: 
# >> Save frequently (napari-deeplabcut saves per-folder). 
# >> Work through all flagged trials in one or several sittings.

# %%
import deeplabcut

# %%
config_path = r"C:\Data\Research\10_Data\derivatives\dlc_superanimal\sub-Maximilian\ses-S001\heightaffordance-Phuc-2026-07-19\config.yaml"
deeplabcut.refine_labels(config_path)
# %%
