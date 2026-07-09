"""
RTMPose Human Pose Estimation Pipeline — VS Code / local Python
Tested against DLC 3.0.0rc10+

Pipeline:
  1. GUI folder picker
  2. Download RTMPose-X body7 from HuggingFace (cached after first run)
  3. Per video:
      a. FasterRCNN person detection → xywh bounding boxes
      b. DLC VideoIterator + get_pose_inference_runner → keypoints
      c. Save CSV (DLC multi-level format)
      d. Save labeled MP4 with full 17-point skeleton (rainbow coloured)
"""

import tkinter as tk
from pathlib import Path
from tkinter import filedialog

import cv2
import huggingface_hub
import numpy as np
import torch
import torchvision.models.detection as detection
import yaml
from tqdm import tqdm

import deeplabcut.pose_estimation_pytorch as dlc_torch

# ──────────────────────────────────────────────────────────────
# TUNEABLE PARAMETERS
# ──────────────────────────────────────────────────────────────
MAX_DETECTIONS = 2          # max people tracked per frame
DETECTION_THRESHOLD = 0.2   # FasterRCNN confidence cutoff
BATCH_SIZE = 8              # reduce to 4 or 2 if you get OOM errors
MODEL_DIR = Path("hf_files").resolve()
SCORE_THRESHOLD = 0.1       # minimum keypoint confidence to draw

# ──────────────────────────────────────────────────────────────
# FOLDER PICKER
# ──────────────────────────────────────────────────────────────
def pick_folder() -> Path:
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    folder = filedialog.askdirectory(title="Select folder containing MP4 videos")
    root.destroy()
    if not folder:
        raise SystemExit("No folder selected — exiting.")
    return Path(folder)


# ──────────────────────────────────────────────────────────────
# MODEL DOWNLOAD
# ──────────────────────────────────────────────────────────────
def download_models() -> tuple[Path, Path]:
    MODEL_DIR.mkdir(exist_ok=True)
    print("Downloading/verifying RTMPose model from HuggingFace...")
    config = Path(huggingface_hub.hf_hub_download(
        "DeepLabCut/HumanBody",
        "rtmpose-x_simcc-body7_pytorch_config.yaml",
        local_dir=MODEL_DIR,
    ))
    snapshot = Path(huggingface_hub.hf_hub_download(
        "DeepLabCut/HumanBody",
        "rtmpose-x_simcc-body7.pt",
        local_dir=MODEL_DIR,
    ))
    return config, snapshot


# ──────────────────────────────────────────────────────────────
# PERSON DETECTOR  (torchvision FasterRCNN MobileNet V3)
# ──────────────────────────────────────────────────────────────
def build_detector(device: torch.device):
    print("Loading person detector...")
    model = detection.fasterrcnn_mobilenet_v3_large_fpn(
        weights=detection.FasterRCNN_MobileNet_V3_Large_FPN_Weights.DEFAULT
    )
    model.eval().to(device)
    return model


def detect_persons_xywh(
    detector,
    frame_rgb: np.ndarray,
    device: torch.device,
) -> np.ndarray:
    """
    Returns an (N, 4) float32 array of bounding boxes in XYWH format,
    one row per detected person, clipped to MAX_DETECTIONS.
    """
    tensor = (
        torch.from_numpy(frame_rgb)
        .permute(2, 0, 1)
        .float()
        .div(255)
        .unsqueeze(0)
        .to(device)
    )
    with torch.no_grad():
        output = detector(tensor)[0]

    boxes  = output["boxes"].cpu().numpy()   # xyxy
    labels = output["labels"].cpu().numpy()
    scores = output["scores"].cpu().numpy()

    # Keep only persons above threshold
    human_boxes = [
        box for box, lbl, sc in zip(boxes, labels, scores)
        if lbl == 1 and sc >= DETECTION_THRESHOLD
    ]

    if len(human_boxes) == 0:
        return np.zeros((0, 4), dtype=np.float32)

    bboxes = np.stack(human_boxes).astype(np.float32)   # (N, 4) xyxy

    # Convert xyxy → xywh (required by DLC's RTMPose runner)
    bboxes[:, 2] -= bboxes[:, 0]   # width  = x2 - x1
    bboxes[:, 3] -= bboxes[:, 1]   # height = y2 - y1

    return bboxes[:MAX_DETECTIONS]


# ──────────────────────────────────────────────────────────────
# POSE RUNNER
# ──────────────────────────────────────────────────────────────
def build_pose_runner(config_path: Path, snapshot_path: Path):
    pose_cfg = dlc_torch.config.read_config_as_dict(config_path)
    runner = dlc_torch.get_pose_inference_runner(
        pose_cfg,
        snapshot_path=snapshot_path,
        batch_size=BATCH_SIZE,
        max_individuals=MAX_DETECTIONS,
    )
    return runner, pose_cfg


# ──────────────────────────────────────────────────────────────
# COMPARABLE DRAWING & SKELETON RENDERING ENGINE
# ──────────────────────────────────────────────────────────────
def draw_predictions(frame_bgr: np.ndarray, frame_preds, pose_cfg: dict) -> np.ndarray:
    out = frame_bgr.copy()

    if frame_preds is None:
        return out

    # ── Robust Keypoint Extraction ──
    poses = None
    
    # If it has a structural attribute, grab it directly
    if hasattr(frame_preds, "poses"):
        poses = frame_preds.poses
    elif hasattr(frame_preds, "predicted_positions"):
        poses = frame_preds.predicted_positions
    elif isinstance(frame_preds, dict):
        if "bodypart" in frame_preds:
            bp_data = frame_preds["bodypart"]
            poses = bp_data.get("poses") if isinstance(bp_data, dict) else getattr(bp_data, "poses", bp_data)
        elif len(frame_preds) > 0:
            # Look inside the first dictionary element
            first_val = next(iter(frame_preds.values()))
            if hasattr(first_val, "poses"):
                poses = first_val.poses
            elif isinstance(first_val, dict) and "poses" in first_val:
                poses = first_val["poses"]
            else:
                poses = first_val
    else:
        poses = frame_preds

    if poses is None:
        return out

    poses = np.array(poses)

    # Standardize dimensions to (N, 17, 3)
    if poses.ndim == 2:
        poses = poses[np.newaxis]

    if poses.ndim != 3 or poses.shape[1] == 0 or poses.shape[2] < 3:
        return out

    # ── Dynamic Skeleton Mapping ──
    bodyparts = pose_cfg["metadata"]["bodyparts"]
    skeleton_links = pose_cfg["metadata"].get("skeleton", [])
    
    num_edges = len(skeleton_links) if skeleton_links else 1
    cmap = cv2.applyColorMap(np.arange(256, dtype=np.uint8), cv2.COLORMAP_RAINBOW)
    
    def get_link_color(link_idx):
        color_pos = int((link_idx / num_edges) * 255)
        return tuple(int(c) for c in cmap[color_pos][0])

    n_individuals = poses.shape[0]

    for person_idx in range(n_individuals):
        kps = poses[person_idx]  # shape (17, 3) -> x, y, score

        if kps[:, 2].max() < 0.01:
            continue

        # ── Dynamic Link Generation Pass ──
        for edge_idx, link in enumerate(skeleton_links):
            if link[0] in bodyparts and link[1] in bodyparts:
                i = bodyparts.index(link[0])
                j = bodyparts.index(link[1])
                
                if i >= kps.shape[0] or j >= kps.shape[0]:
                    continue
                    
                xi, yi, si = kps[i]
                xj, yj, sj = kps[j]
                
                if si > SCORE_THRESHOLD and sj > SCORE_THRESHOLD:
                    edge_color = get_link_color(edge_idx)
                    cv2.line(out, (int(xi), int(yi)), (int(xj), int(yj)), edge_color, 2, cv2.LINE_AA)

        # ── Keypoint Node Pass ──
        for ki in range(kps.shape[0]):
            x, y, s = kps[ki]
            if s > SCORE_THRESHOLD:
                node_color = (0, 255, 0)
                for edge_idx, link in enumerate(skeleton_links):
                    if link[0] == bodyparts[ki] or link[1] == bodyparts[ki]:
                        node_color = get_link_color(edge_idx)
                        break
                        
                cv2.circle(out, (int(x), int(y)), 5, node_color, -1, cv2.LINE_AA)
                cv2.circle(out, (int(x), int(y)), 5, (255, 255, 255), 1, cv2.LINE_AA)

    return out


# ──────────────────────────────────────────────────────────────
# VIDEO PROCESSING
# ──────────────────────────────────────────────────────────────
def process_video(
    video_path: Path,
    output_dir: Path,
    detector,
    runner,
    pose_cfg: dict,
    device: torch.device,
):
    bodyparts   = pose_cfg["metadata"]["bodyparts"]
    unique_bpts = pose_cfg["metadata"].get("unique_bodyparts", [])
    individuals = [f"idv_{i}" for i in range(MAX_DETECTIONS)]

    out_video_path = output_dir / f"{video_path.stem}_labeled.mp4"
    out_csv_path   = output_dir / f"{video_path.stem}_predictions.csv"

    # ── 1. Read every frame and build detection context ──────
    cap = cv2.VideoCapture(str(video_path))
    fps         = cap.get(cv2.CAP_PROP_FPS) or 25.0
    width       = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height      = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total       = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    print(f"\n▶  {video_path.name}  ({total} frames @ {fps:.1f} fps)")
    print("   Step 1/3 — Detecting persons...")

    frames_bgr = []
    context    = []

    for _ in tqdm(range(total), unit="frame"):
        ret, frame = cap.read()
        if not ret:
            break
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        bboxes    = detect_persons_xywh(detector, frame_rgb, device)
        frames_bgr.append(frame)
        context.append({"bboxes": bboxes})

    cap.release()

    # ── 2. Pose inference via DLC VideoIterator ───────────────
    print("   Step 2/3 — Running pose estimation...")

    video_iter = list(
        (cv2.cvtColor(f, cv2.COLOR_BGR2RGB), ctx)
        for f, ctx in zip(frames_bgr, context)
    )
    predictions = list(runner.inference(tqdm(video_iter, total=len(frames_bgr))))

    # ── 3. Save CSV ───────────────────────────────────────────
    print("   Step 3/3 — Saving CSV and labeled video...")

    df = dlc_torch.build_predictions_dataframe(
        scorer="rtmpose-body7",
        predictions={
            idx: preds for idx, preds in enumerate(predictions)
        },
        parameters=dlc_torch.PoseDatasetParameters(
            bodyparts=bodyparts,
            unique_bpts=unique_bpts,
            individuals=individuals,
        ),
    )
    df.to_csv(str(out_csv_path))

    # ── 4. Render labeled video ───────────────────────────────
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(out_video_path), fourcc, fps, (width, height))

    for frame_bgr, frame_preds in zip(frames_bgr, predictions):
        annotated = draw_predictions(frame_bgr, frame_preds, pose_cfg)
        writer.write(annotated)

    writer.release()
    print(f"   ✔ Video : {out_video_path.name}")
    print(f"   ✔ CSV   : {out_csv_path.name}")


# ──────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────
def main():
    input_folder = pick_folder()
    video_files  = sorted(input_folder.glob("*.mp4"))

    if not video_files:
        raise SystemExit(f"No .mp4 files found in: {input_folder}")

    print(f"Found {len(video_files)} video(s) in: {input_folder}")

    output_dir = input_folder / "output"
    output_dir.mkdir(exist_ok=True)

    config_path, snapshot_path = download_models()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")

    detector         = build_detector(device)
    runner, pose_cfg = build_pose_runner(config_path, snapshot_path)

    for video_path in video_files:
        process_video(
            video_path=video_path,
            output_dir=output_dir,
            detector=detector,
            runner=runner,
            pose_cfg=pose_cfg,
            device=device,
        )

    print(f"\n✅  All done!  Results saved to: {output_dir}")


if __name__ == "__main__":
    main()