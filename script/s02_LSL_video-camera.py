import cv2
import datetime
import os
import sys
import uuid
import multiprocessing
from pylsl import StreamInfo, StreamOutlet, local_clock
import json

def create_outlet(index, filename):
    stream_name = f'FrameMarker_{index}'
    info = StreamInfo(name=stream_name,
                      type='videostream',
                      channel_format='float32',
                      channel_count=1,
                      source_id=str(uuid.uuid4()))
    info.desc().append_child_value("videoFile", filename)
    return StreamOutlet(info)

def record_camera(dev_index, cam_label, save_folder, bids_prefix, task_name, width=1280, height=720, fps=30):
    cap = cv2.VideoCapture(dev_index, cv2.CAP_DSHOW)
    
    # --- ADD THIS LINE HERE ---
    # cap.set(cv2.CAP_PROP_BUFFERSIZE, 1) 
    # --------------------------

    if not cap.isOpened():
        print(f"ERROR: Cannot open camera {dev_index} ({cam_label})")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
    cap.set(cv2.CAP_PROP_FPS, fps)

    # BIDS Filenames
    base_name = f"{bids_prefix}_acq-{cam_label}View_beh"
    video_path = os.path.join(save_folder, f"{base_name}.avi")
    json_path = os.path.join(save_folder, f"{base_name}.json")
    
    # 1. Create the JSON Sidecar
    metadata = {
        "TaskName": task_name,
        "RecordingType": "continuous",
        "VideoDetails": {
            "CameraLabel": cam_label,
            "SamplingFrequency": fps,
            "Width": width,
            "Height": height,
            "SoftwareVersions": f"OpenCV {cv2.__version__}",
            "VideoCodec": "XVID"
        },
        "AnalysisIntent": "Markerless pose estimation via DeepLabCut"
    }
    
    with open(json_path, 'w') as f:
        json.dump(metadata, f, indent=4)

    # 2. Setup Video Recording
    fourcc = cv2.VideoWriter_fourcc(*'XVID')
    out = cv2.VideoWriter(video_path, fourcc, fps, (width, height))
    outlet = create_outlet(dev_index, video_path)
    
    print(f"STARTED: {cam_label} -> {video_path}")
    
    frame_counter = 1
    window_name = f"Preview_{cam_label}"


############### ORIGINAL ###############
#    try:
#        while True:
#            ret, frame = cap.read()
#            if not ret: break
#            out.write(frame)
#            outlet.push_sample([float(frame_counter)])
#            cv2.imshow(window_name, frame)
#            frame_counter += 1
#            if cv2.waitKey(1) & 0xFF == ord('q'): break
#    finally:
#        cap.release()
#        out.release()
#        cv2.destroyWindow(window_name)

############### ALTERED ###############
    try:
        while True:
            ret, frame = cap.read()
            if not ret: break
            timestamp = local_clock()
            out.write(frame)
            outlet.push_sample([float(frame_counter)], timestamp=timestamp)
            cv2.imshow(window_name, frame)
            frame_counter += 1
            if cv2.waitKey(1) & 0xFF == ord('q'): break
    finally:
        cap.release()
        out.release()
        cv2.destroyWindow(window_name)

if __name__ == "__main__":
    ROOT_DATA_DIR = r"C:\Users\exp-idgrap\Desktop\xplo-judo-data"

    while True:
        print("\n--- NEW RECORDING SESSION ---")
        subj_id = input("Subject ID: ").strip()
        if not subj_id: continue
        
        # --- Task Mapping Logic ---
        print("Task Options: [t] training, [h] height-affordance, [e] estimate, [test] test, [Or type custom]")
        task_input = input("Task Name/Number: ").strip()
        
        task_map = {
            "t"     :"training",
            "h"     : "heightaffordance",
            "e"     : "estimate",
            "test"  : "test"
        }
        # Use map if 1/2/3, otherwise use the string they typed
        task_name = task_map.get(task_input, task_input)
        
        if not task_name: continue
        
       
        # Default session to S001, default run to 001
        raw_session = input("Session ID [S001]: ").strip() or "S001"
        
        # If the user typed '1', make it 'S001'. If they typed 'S1', make it 'S001'.
        if not raw_session.startswith("S"):
            session_id = "S" + raw_session.zfill(3)
        else:
            # Splits the 'S' from the number, pads the number, and puts it back
            num_part = raw_session[1:]
            session_id = "S" + num_part.zfill(3)

        run_id = (input("Run Number [001]: ").strip() or "001").zfill(3)


        # BIDS Pathing
        bids_subfolder = os.path.join(ROOT_DATA_DIR, f"sub-{subj_id}", f"ses-{session_id}", "video")
        bids_prefix = f"sub-{subj_id}_ses-{session_id}_task-{task_name}_run-{run_id}"

        # Overwrite Check
        test_file = os.path.join(bids_subfolder, f"{bids_prefix}_acq-UpperView_beh.avi")
        if os.path.exists(test_file):
            print(f"\n[!!!] WARNING: File exists: {test_file}")
            choice = input("Overwrite? (y/n) or 'auto' to increment run: ").lower().strip()
            if choice == 'auto':
                run_num = int(run_id)
                while os.path.exists(os.path.join(bids_subfolder, f"sub-{subj_id}_ses-{session_id}_task-{task_name}_run-{str(run_num).zfill(2)}_acq-UpperView_beh.avi")):
                    run_num += 1
                run_id = str(run_num).zfill(2)
                bids_prefix = f"sub-{subj_id}_ses-{session_id}_task-{task_name}_run-{run_id}"
            elif choice != 'y':
                continue 
        
        os.makedirs(bids_subfolder, exist_ok=True)
        break 

    # Launch Cameras
    cam_configs = [(0, "Upper"), (1, "Side")]
    processes = []
    for dev_id, cam_label in cam_configs:
        p = multiprocessing.Process(
            target=record_camera, 
            args=(dev_id, cam_label, bids_subfolder, bids_prefix, task_name)
        )
        p.start()
        processes.append(p)

    for p in processes:
        p.join()