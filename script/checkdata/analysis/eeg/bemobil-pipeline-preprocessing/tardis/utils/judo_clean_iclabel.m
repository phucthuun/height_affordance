function [EEG_clean, info] = judo_clean_iclabel(EEG, classes_to_keep, threshold)
%JUDO_CLEAN_ICLABEL  Remove independent components by ICLabel class.
%
%   [EEG_clean, info] = judo_clean_iclabel(EEG, [1 4 5 6 7], -1)
%
%   Same decision rule as bemobil_clean_with_iclabel, without its plots (which cannot be printed on the
%   cluster): with threshold -1 each IC gets its most probable class (popularity) and is kept if that class
%   is in classes_to_keep; otherwise an IC is kept if the summed probability of classes_to_keep exceeds the
%   threshold. Requires EEG.etc.ic_classification.ICLabel (run iclabel first).

C = EEG.etc.ic_classification.ICLabel.classifications;
class_names = EEG.etc.ic_classification.ICLabel.classes;
[~, popular] = max(C, [], 2);

if threshold == -1
    keep = ismember(popular, classes_to_keep);
else
    keep = sum(C(:, classes_to_keep), 2) > threshold;
end
removed = find(~keep(:))';

EEG_clean = EEG;
if ~isempty(removed)
    EEG_clean = pop_subcomp(EEG, removed, 0);
end
EEG_clean.etc.ic_cleaning = struct('classes_to_keep', classes_to_keep, 'threshold_to_keep', threshold, ...
    'ICs_keep', find(keep(:))', 'ICs_throw', removed);

info = struct();
info.classes_to_keep = classes_to_keep;
info.classes_kept_names = class_names(classes_to_keep);
info.removed = removed;
info.n_removed = numel(removed);
info.n_kept = sum(keep);
by_class = struct();
for c = 1:numel(class_names)
    by_class.(matlab.lang.makeValidName(class_names{c})) = sum(popular(removed) == c);
end
info.removed_by_class = by_class;

% Share of the channel-data variance removed (all channels, all samples), channel by channel to save memory
v_before = 0;
v_after = 0;
for ch = EEG.icachansind(:)'
    v_before = v_before + var(double(EEG.data(ch, :)));
    v_after  = v_after + var(double(EEG_clean.data(ch, :)));
end
info.variance_removed_percent = 100 * (1 - v_after / v_before);
end
