# STEP 4: Refine Labels
# This opens napari pre-loaded with the extracted frames + SuperAnimal's placed points, per video folder. 
# ---------------------------
# Opens napari (via deeplabcut.refine_labels) pre-loaded with the
# machinelabels-iter*.h5 written by s03 for each flagged trial folder.
# Correct wrong points, delete occluded ones, SAVE each folder's Points
# layer (this writes CollectedData_<scorer>.h5 -- required before s05's
# merge_datasets will accept the folder as "manually refined").
#
# MUST be run cell-by-cell in a VS Code Interactive Window (or IPython),
# NOT via "Run Python File" / `python s04_refine-labels.py` -- napari
# will open and immediately close if run as a plain script, since there's
# no live Qt event loop keeping the process alive after the call returns.
# ---------------------------
# Labeling Instruction: For each flagged trial's frames
# (1) drag misplaced points to the correct spot
# (2) delete (middle-click) any point on an occluded/invisible body part
# (3) leave correct ones untouched. 
# TIPS: 
# >> Save frequently (napari-deeplabcut saves per-folder). 
# >> Work through all flagged trials in one or several sittings.


# %%
import re
from pathlib import Path
import deeplabcut
# Enter the subject/session/run/camera view you want to refine labels for.
subID = "sub-155T4T"    # "sub-{subLabel}"
sesID = "ses-S001"          # "ses-{sesLabel}"
camera_view = "UpperView"    # "UpperView" or "SideView"

# Base directory where heightaffordance-* project subfolder lives
base_dir = Path(rf"C:\Data\Research\10_Data\derivatives\dlc_superanimal\{subID}\{sesID}\{camera_view}")

matching_configs = list(base_dir.glob("heightaffordance-*/config.yaml"))

if matching_configs:
    config_path = str(matching_configs[0])
    print(f"Found config at: {config_path}")
else:
    raise FileNotFoundError(
        f"Could not find any 'heightaffordance-*/config.yaml' inside {base_dir}. "
        f"Run s03_dlc-project-setup.py for this subject/session/view first."
    )

# %%
# Opens napari. Work through each labeled-data/<trial> folder:
#   - correct point placed  -> leave it
#   - wrong point placed    -> drag to correct spot
#   - occluded/invisible    -> delete the point, do not guess
# Select the Points/machinelabels layer, then File -> Save Selected Layer(s)
# (Ctrl+S) for EACH folder before moving to the next one.
deeplabcut.refine_labels(config_path)


# %%
