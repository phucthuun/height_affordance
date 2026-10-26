function tf = judo_use_fftfilt()
%JUDO_USE_FFTFILT  1 if fftfilt (Signal Processing Toolbox) is available, else 0.
%   FFT-based filtering is much faster for the long (~30 s) 0.1 Hz high-pass; without fftfilt
%   pop_eegfiltnew falls back to time-domain filtering with identical results.

persistent cached
if isempty(cached)
    cached = double(~isempty(which('fftfilt')));
end
tf = cached;
end
