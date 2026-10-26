function [EEG, info] = judo_highpass(EEG, passband_edge_hz)
%JUDO_HIGHPASS  Final zero-phase FIR high-pass, as in bemobil (EEGLAB pop_eegfiltnew, default design).
%
%   [EEG, info] = judo_highpass(EEG, 0.1)
%
%   Hamming-windowed sinc FIR with EEGLAB's default transition band (0.1 Hz edge -> 0.05 Hz cutoff,
%   about 33 s long). Each continuous segment is extended with its first/last value while filtering
%   (EEGLAB's default). The runs start 1 s before the first trial, so the first and last epochs see some of
%   the filter's edge response; in simulations this was about 0.5 uV RMS within a baseline-corrected epoch,
%   and mirroring the data instead made it worse. info records the actual filter for the QC report.

[EEG, ~, b] = pop_eegfiltnew(EEG, 'locutoff', passband_edge_hz, 'usefftfilt', judo_use_fftfilt(), 'plotfreqz', 0);
EEG.icaact = [];

order = numel(b) - 1;
tbw = 3.3 / order * EEG.srate;
info = struct();
info.filter                  = 'zero-phase Hamming-windowed sinc FIR (EEGLAB firfilt, pop_eegfiltnew)';
info.passband_edge_hz        = passband_edge_hz;
info.transition_bandwidth_hz = tbw;
info.cutoff_hz               = passband_edge_hz - tbw / 2;
info.order                   = order;
info.length_s                = order / EEG.srate;
info.padding                 = 'edge value (EEGLAB default)';

if ~isfield(EEG.etc, 'filter') || ~isstruct(EEG.etc.filter)
    EEG.etc.filter = struct();
end
EEG.etc.filter.type = 'Hamming windowed zero-phase FIR filter';
EEG.etc.filter.highpass = struct('cutoff', info.cutoff_hz, 'transition_bandwidth', tbw, ...
    'passband', passband_edge_hz, 'order', order);
end
