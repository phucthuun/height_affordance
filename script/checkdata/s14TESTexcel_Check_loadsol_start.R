# Load necessary library
library(readr); library(readxl)
library(tidyverse)
library(ggplot2)
library(scatterplot3d)
library(gganimate)
library(av)

# LOADSOL ----
## 1. Setup file path ----
file_path <- file.choose()
  
## 2. Extract Sensor IDs (Line 3) ----
# We read the first 3 lines and take the last one to know which columns belong to which sensor
headers <- readLines(file_path, n = 3)
sensor_ids <- unlist(strsplit(headers[3], "\t"))

## 3. Read the Data----
# We skip 4 lines (File, Comment, IDs, and the redundant "Time/Force" row)
# We will define our own clean names
ls_data <- read_tsv(file_path, skip = 4, col_names = FALSE)

## 4. Manually Assign Clean Column Names----
# Based on your structure: 
# Cols 1-4: KGW305-L (Heel, Medial, Lateral, Full)
# Col 5: Empty/Separator
# Cols 6-9: KGW304-R (Lateral, Medial, Heel, Full)
# Col 10: Empty/Separator
# Cols 11-13: KYN058 (Full Area, Trigger)
colnames(ls_data) <- c(
  "Time", "L_Heel", "L_Medial", "L_Lateral", "L_Total",
  "Time_R_unused", "R_Lateral", "R_Medial", "R_Heel", "R_Total",
  "Time_T_unused", "Trigger_Full", "Trigger_Sync"
)

## 5. Clean up----
# Remove the redundant time columns and empty columns if they exist
ls_data <- ls_data %>%
  select(-contains("unused")) %>%
  filter(!is.na(Time)) # Ensure no trailing empty rows


## 6. Visualization
ggplot(ls_data)+
  geom_point(aes(x=Time,y=Trigger_Full))

# Find indices where the trigger signal changes significantly
# Adjust 'threshold' based on your specific noise floor (e.g., 1.0)
threshold <- 0
events <- which(abs(diff(ls_data$Trigger_Sync)) > threshold)

# Get the timestamps of these events
event_times <- ls_data$Time[events]

# Label them based on sequence
cat("Start Trigger detected at:", event_times[1], "s\n")
if(length(event_times) > 2) {
  cat("Interval Triggers detected at:", event_times[2:(length(event_times)-1)], "s\n")
}
cat("Stop Trigger detected at:", event_times[length(event_times)], "s\n")

# XSENS ----
file_path <- file.choose()
xsens_data <- read_xlsx(file_path, sheet = "Segment Position")

# SYNC ----
## Normalize data ----
#  1. Create independent 0-100% scales based on each dataset's row count 
ls_normalized <- ls_data %>%
  filter(Time >= min(event_times) & Time <= max(event_times)) %>%
  mutate(Norm_Time = seq(0, 100, length.out = n()))

xsens_normalized <- xsens_data %>%
  mutate(Norm_Time = seq(0, 100, length.out = n()))

#  2. Extract only the force columns we want to stretch 
ls_force_data <- ls_normalized %>% 
  select(L_Heel, L_Medial, L_Lateral, L_Total, 
         R_Lateral, R_Medial, R_Heel, R_Total)

#  3. Interpolate (stretch) LOADSOL to match the exact size of XSENS 
# approx() maps the shorter timeline onto the longer timeline row-by-row
ls_stretched <- as.data.frame(lapply(ls_force_data, function(column) {
  approx(
    x = ls_normalized$Norm_Time,     # Shorter 100Hz percentage timeline
    y = column,                      # Original force rows
    xout = xsens_normalized$Norm_Time, # Target longer 240Hz percentage timeline
    rule = 2                         # Keeps edges clean
  )$y
}))

# Add the target timeline back to our new stretched dataset
ls_stretched$Norm_Time <- xsens_normalized$Norm_Time

#  4. Merge side-by-side 
# The two datasets now have the exact same number of rows and match flawlessly
aligned_data <- inner_join(xsens_normalized, ls_stretched, by = "Norm_Time")

#  5. Double check the results 
cat("Original LOADSOL rows:", nrow(ls_normalized), "\n")
cat("Original XSENS rows:", nrow(xsens_normalized), "\n")
cat("Final Aligned Data rows:", nrow(aligned_data), "\n")

## 1-min visualization ----
# 1. EXTRACT 1 MINUTE FROM THE MIDDLE

total_rows <- nrow(aligned_data)
fps_target <- 30  
xsens_hz   <- 240 

frames_needed <- 60 * xsens_hz 
start_idx     <- round((total_rows / 2) - (frames_needed / 2))
end_idx       <- start_idx + frames_needed - 1

start_idx <- max(1, start_idx)
end_idx   <- min(total_rows, end_idx)

middle_minute_data <- aligned_data[start_idx:end_idx, ]

# Downsample for rendering to match 30 FPS playback speed
downsample_factor <- xsens_hz / fps_target
video_data_clean  <- middle_minute_data %>%
  filter(row_number() %% downsample_factor == 0) %>%
  mutate(Video_Frame = row_number()) # Continuous index for looping


# 2. LONG FORMAT FOR THE SKELETON LAYER

kinematics_long <- video_data_clean %>%
  select(Video_Frame, Norm_Time, L_Total, R_Total, everything()) %>%
  pivot_longer(
    cols = contains(" "), 
    names_to = c("Segment", ".value"), 
    names_pattern = "(.*) (x|y|z)"
  )
# 3. RENDER FRAME-BY-FRAME LOOP (MATLAB STYLE WITH 3D POSITION)
library(scatterplot3d)
library(grid)

cat("Starting 3D frame generation...\n")

# Create a temporary folder to store individual frames safely
img_dir <- file.path(tempdir(), "frames")
if(!dir.exists(img_dir)) dir.create(img_dir)

# Set up global plot parameters matching your MATLAB logic
total_video_frames <- max(video_data_clean$Video_Frame)
force_max <- max(c(video_data_clean$L_Total, video_data_clean$R_Total, 200), na.rm = TRUE)

# 2-second trailing window window logic: 2 seconds * 30 FPS = 60 frames
window_size <- 2 * fps_target 

# Calculate absolute axis limits for 3D skeleton bounds across the entire selected window
x_limits <- c(min(kinematics_long$x, na.rm=TRUE) - 0.2, max(kinematics_long$x, na.rm=TRUE) + 0.2)
y_limits <- c(min(kinematics_long$y, na.rm=TRUE) - 0.2, max(kinematics_long$y, na.rm=TRUE) + 0.2)
z_limits <- c(0, 2.1) 

for (t in 1:total_video_frames) {
  
  # A. Filter current skeleton coordinates
  current_skeleton <- kinematics_long %>% filter(Video_Frame == t)
  current_time_pct <- video_data_clean$Norm_Time[video_data_clean$Video_Frame == t]
  
  # Map color tracking vectors for individual skeleton nodes
  node_colors <- case_when(
    current_skeleton$Segment == "Left Foot"  ~ "#0072B2",
    current_skeleton$Segment == "Right Foot" ~ "#D55E00",
    TRUE                                     ~ "gray70"
  )
  
  node_sizes <- if_else(current_skeleton$Segment %in% c("Left Foot", "Right Foot"), 2.5, 1.2)
  
  # B. Trailing Window Logic for Force Graph
  window_start <- max(1, t - window_size)
  current_force_window <- video_data_clean %>%
    filter(Video_Frame >= window_start & Video_Frame <= t)
  
  # --- Setup Image Canvas Export Layout ---
  img_path <- file.path(img_dir, sprintf("frame_%04d.png", t))
  png(img_path, width = 1100, height = 550, bg = "black")
  
  # Split the canvas into 2 side-by-side viewports (1 row, 2 columns)
  par(mfrow = c(1, 2), bg = "black", mar = c(4, 4, 3, 2), col.axis = "white", col.lab = "white", col.main = "white")
  
  # --- Plot Panel 1: 3D Body Positions (MATLAB Scatter3 Equivalent) ---
  # This paints IMMEDIATELY to the left panel viewport because of par(mfrow)
  s3d <- scatterplot3d(
    x = current_skeleton$x, 
    y = current_skeleton$y, 
    z = current_skeleton$z,
    xlim = x_limits, ylim = y_limits, zlim = z_limits,
    color = node_colors, 
    pch = 19, 
    cex.symbols = node_sizes,
    angle = 45,            
    scale.y = 0.7,
    grid = TRUE, 
    box = TRUE,
    xlab = "X Position (m)", ylab = "Y Position (m)", zlab = "Z Height (m)",
    main = sprintf("3D Body Position | Progress: %.1f%%", current_time_pct),
    col.grid = "gray30"
  )
  
  # --- Plot Panel 2: Continuous Oscilloscope Force ---
  p2 <- ggplot(current_force_window) +
    geom_line(aes(x = Video_Frame, y = L_Total), color = "#0072B2", linewidth = 1.5) +
    geom_line(aes(x = Video_Frame, y = R_Total), color = "#D55E00", linewidth = 1.5) +
    xlim(t - window_size, t) + 
    ylim(0, force_max) +
    theme_minimal() +
    theme(
      panel.background = element_rect(fill = "black", color = "gray30"),
      plot.background = element_rect(fill = "black", color = NA),
      panel.grid.major = element_line(color = "gray30"),
      panel.grid.minor = element_line(color = "gray20"),
      text = element_text(color = "white"),
      plot.title = element_text(size = 14, face = "bold", hjust = 0.5)
    ) +
    labs(title = "Real-Time Force (N) [2s Window]", x = "Video Frames", y = "Force (N)")
  
  # --- THE FIX: Direct Viewport Printing ---
  # We use grid to force ggplot to render specifically inside the right layout panel (panel 2)
  vp <- viewport(layout.pos.row = 1, layout.pos.col = 2)
  print(p2, vp = viewport(x = 0.75, y = 0.5, width = 0.5, height = 1))
  
  dev.off()
  
  # Progress Tracker Output
  if (t %% 90 == 0) {
    cat(sprintf("Rendering Progress: %.0f%%\n", (t / total_video_frames) * 100))
  }
}
print(Sys.time())

# 4. COMPILE IMAGES INTO MP4 VIDEO

cat("Compiling frames into video file...\n")
img_files <- list.files(img_dir, pattern = "*.png", full.names = TRUE)

av::av_encode_video(
  input = img_files,
  output = "xsens_loadsol_oscilloscope3D.mp4",
  framerate = fps_target
)

# Clean up temp directory files
unlink(img_dir, recursive = TRUE)
cat("Video successfully compiled and saved as 'xsens_loadsol_oscilloscope.mp4'\n")
print(Sys.time())
