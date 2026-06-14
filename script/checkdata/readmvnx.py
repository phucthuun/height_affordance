import xml.etree.ElementTree as ET
import numpy as np
import os
import time

def parse_massive_mvnx(file_path):
    print(f"Starting memory-safe streaming of: {os.path.basename(file_path)}")
    start_time = time.time()
    
    # 1. First Pass: Fast-scan for structural metadata setup
    frame_rate = None
    segment_count = None
    
    context = ET.iterparse(file_path, events=('start',))
    for event, elem in context:
        # Strip namespaces if present in tags
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        
        if tag == 'frameRate' and frame_rate is None:
            frame_rate = float(elem.attrib.get('frameRate', 60))
        if tag == 'segmentCount' and segment_count is None:
            segment_count = int(elem.attrib.get('segmentCount', 23))
            
        # Break early once metadata constants are caught
        if frame_rate and segment_count:
            break
            
    del context # Clear first iterator
    
    print(f"Metadata Located -> Frame Rate: {frame_rate} Hz | Segments: {segment_count}")
    
    # 2. Second Pass: Stream the actual positional and orientation data blocks
    # Pre-allocating incremental lists to dynamically build arrays safely
    orientations_list = []
    positions_list = []
    
    context = ET.iterparse(file_path, events=('end',))
    
    frame_counter = 0
    for event, elem in context:
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        
        if tag == 'frame':
            # Check if this frame contains standard tracking data
            # (Filtering out 'normal' frame types, skipping setup/identity frames)
            if elem.attrib.get('type') == 'normal':
                frame_counter += 1
                
                # Find orientation and position text nodes
                orient_elem = elem.find('.//{*}orientation')
                pos_elem = elem.find('.//{*}position')
                
                if orient_elem is not None and pos_elem is not None:
                    # Convert space-separated text blocks straight to flat float arrays
                    quat_data = np.fromstring(orient_elem.text, sep=' ', dtype=np.float32)
                    pos_data = np.fromstring(pos_elem.text, sep=' ', dtype=np.float32)
                    
                    orientations_list.append(quat_data)
                    positions_list.append(pos_data)
                
                # Status update every 50,000 frames so you know it's moving
                if frame_counter % 50000 == 0:
                    print(f"Processed {frame_counter} tracking frames safely...")

            # CRITICAL LAYER: This wipes the parsed frame out of the JVM/C heap memory instantly
            elem.clear()
            
    print(f"Data streaming finished. Constructing consolidated matrices...")
    
    # Convert lists into solid NumPy Arrays [Frames x TotalChannels]
    # For 23 segments: orientations will be [Frames x 92], positions will be [Frames x 69]
    all_quats = np.array(orientations_list, dtype=np.float32)
    all_poss = np.array(positions_list, dtype=np.float32)
    
    n_frames = all_quats.shape[0]
    
    # 3. Restructure to match Script 1 Layout: [ (Segments * 7) x Time ]
    # Preallocating final matrix directly
    xData_from_mvnx = np.zeros((segment_count * 7, n_frames), dtype=np.float32)
    
    for s in range(segment_count):
        row_start = s * 7
        
        # Slicing blocks out of the streamed arrays
        # Orientation: 4 channels per segment
        quat_stream = all_quats[:, (s * 4):(s * 4 + 4)].T # Transposing to make it [Dim x Time]
        # Position: 3 channels per segment
        pos_stream = all_poss[:, (s * 3):(s * 3 + 3)].T
        
        # Pack into flat consolidated array matching your original MATLAB layout
        xData_from_mvnx[row_start : row_start + 4, :] = quat_stream
        xData_from_mvnx[row_start + 4 : row_start + 7, :] = pos_stream

    elapsed = time.time() - start_time
    print(f"\nTransformation Complete in {elapsed:.2f} seconds!")
    print(f"Final matrix size: {xData_from_mvnx.shape}")
    
    return xData_from_mvnx

# Execution Guard
if __name__ == "__main__":
    # Point this to your massive 2.75 GB file path
    target_file = r"\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\sub-Maximilian\ses-S001\mocap\sub-Maximilian_ses-S001_task-heightaffordance_run-001_mocap-001_MVN System 1.mvnx"
    
    matrix_out = parse_massive_mvnx(target_file)
    
    # Save the flattened matrix straight out to a compressed file format
    # This allows you to load it into Python or back into MATLAB instantly without parsing text again!
    output_name = target_file.replace(".mvnx", "_processed.npz")
    np.savez_compressed(output_name, xData_mvnx=matrix_out)
    print(f"Saved binary array safely to: {output_name}")