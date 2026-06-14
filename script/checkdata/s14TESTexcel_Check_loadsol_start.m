%% Xsens-Loadsol Final Integration
clear; clc; close all;

%% 1. File Selection
[xFile, xPath] = uigetfile('*.xlsx', 'Select Xsens XLSX File');
[lFile, lPath] = uigetfile('*.txt', 'Select Loadsol TXT File');
if isequal(xFile,0) || isequal(lFile,0); return; end

% Construct full path for Excel
fullXsensPath = fullfile(xPath, xFile);

% Get all sheet names from the Excel file
[~, sheets] = xlsfinfo(fullXsensPath);

%% 2. Load Xsens Data (Excel Version)
% Load the data table

opts = spreadsheetImportOptions("NumVariables", 1); 
opts.Sheet = "Segment Position";

xsens_data = readtable("//mpib-berlin.mpg.de/Share/Projects/1130-id-grap/private/02_Task/height_affordance/test_data/sub-JOLANDE/ses-S001/mocap/sub-JOLANDE_ses-S001_task-heightaffordance_run-002_data.xlsx", ...
    opts);

% Assuming Xsens columns are numeric - adapt as needed
xData = xTable{:, 2:end}'; % Transpose to match your [channels x samples] logic
xTime = xTable{:, 1};      % Assuming first column is Time

%% 3. Load & Map Loadsol (Dynamic Column Mapping)
opts = detectImportOptions(fullfile(lPath, lFile), 'FileType', 'text');
opts.VariableNamingRule = 'preserve';
lsTable = readtable(fullfile(lPath, lFile), opts);

fid = fopen(fullfile(lPath, lFile), 'rt');
fgetl(fid); fgetl(fid); 
lineID = fgetl(fid); % Row 3 contains sensor IDs
fclose(fid);
idCells = strsplit(lineID, '\t');

idxL = find(contains(idCells, 'KGW305') & ~contains(idCells, '::'), 1);
idxR = find(contains(idCells, 'KGW304') & ~contains(idCells, '::'), 1);
idxT = find(contains(idCells, 'KYN058') & ~contains(idCells, '::'), 1, 'last');

lsTime    = lsTable{:, 1};
lsTrigger = lsTable{:, idxT};
lsForceL  = lsTable{:, idxL};
lsForceR  = lsTable{:, idxR};