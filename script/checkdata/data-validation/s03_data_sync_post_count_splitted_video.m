# This script checks for missing video files in a specified directory based on expected runs, trials, and camera views.
# Usage: After syncing videos by LSL and split by trials

# Load required libraries
library(stringr)
library(dplyr)
library(tidyr)

# 1. Set path to your data folder
# Replace with the actual path to your folder containing the files
data_dir <- "//mpib-berlin.mpg.de/Share/Projects/1223-xplo-judo/private/10_Data/derivatives/syncdata/sub-EG231A/ses-S001/video"

# 2. List all files in the folder
# Adjust the pattern if your files have specific extensions (e.g., "_beh.csv")
files <- list.files(data_dir, pattern = "_beh")

# 3. Parse metadata from filenames using regular expressions
file_df <- data.frame(filename = files) %>%
  mutate(
    run = str_extract(filename, "run-([0-9]+)", group = 1),
    trial = str_extract(filename, "trial-([0-9]+)", group = 1),
    camera = str_extract(filename, "acq-([A-Za-z]+)_beh", group = 1)
  ) %>%
  drop_na(run, trial, camera)

# Convert run and trial to numeric for accurate matching
file_df$run <- as.integer(file_df$run)
file_df$trial <- as.integer(file_df$trial)

# 4. Create a complete grid of expected combinations 
# (5 runs, 64 trials per run, 3 cameras)
expected_grid <- expand_grid(
  run = 1:5,
  trial = 1:64,
  camera = c("GroundView", "SideView", "UpperView")
)

# 5. Find missing files using anti_join
missing_files <- expected_grid %>%
  anti_join(file_df, by = c("run", "trial", "camera"))

# 6. Print summary report
cat("--- DATA COMPLETENESS REPORT ---\n")
cat("Total expected files:", nrow(expected_grid), "\n")
cat("Total found files:   ", nrow(file_df), "\n\n")

if (nrow(missing_files) == 0) {
  cat("Success: All data is complete! No missing files found.\n")
} else {
  cat(sprintf("Warning: Found %d missing file(s):\n\n", nrow(missing_files)))
  print(missing_files, n = Inf)
}
