function fp = judo_eeg_fingerprint(EEG)
%JUDO_EEG_FINGERPRINT  Content-based ID of a continuous dataset.
%
%   Combines the channel labels, number of samples, sampling rate, interpolated channels and every 997th
%   sample of the data (rounded to single precision, so the ID does not depend on how the file was loaded).
%   Step 2A stores it for preprocessed.set, step 2B stores it with the manual marks, and step 2C only uses
%   the marks if the preprocessed data still has the same fingerprint.

interp = [];
if isfield(EEG, 'etc') && isfield(EEG.etc, 'interpolated_channels')
    interp = EEG.etc.interpolated_channels;
end
sample = double(single(EEG.data(:, 1:997:EEG.pnts)));
fp = judo_hash({sprintf('%d|%d|%.6f', EEG.nbchan, EEG.pnts, EEG.srate), ...
    strjoin({EEG.chanlocs.labels}, ','), double(interp), sample});
end
