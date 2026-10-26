function h = judo_hash(data)
%JUDO_HASH  SHA-256 hex digest of text, numbers, logicals, structs (via JSON) or a cell array of those.
%   Used for settings hashes and dataset fingerprints. Needs MATLAB's Java (available in -batch mode).

if ~usejava('jvm')
    error('judo:hash', 'judo_hash needs Java. Do not start MATLAB with -nojvm.');
end
md = java.security.MessageDigest.getInstance('SHA-256');
hash_update(md, data);
digest = typecast(md.digest(), 'uint8');
h = lower(reshape(dec2hex(digest, 2).', 1, []));
end

function hash_update(md, x)
if iscell(x)
    for i = 1:numel(x)
        hash_update(md, x{i});
    end
elseif ischar(x) || isstring(x)
    bytes = unicode2native(char(x), 'UTF-8');
    if ~isempty(bytes)
        md.update(typecast(bytes(:), 'int8'));
    end
elseif isnumeric(x) || islogical(x)
    if ~isempty(x)
        md.update(typecast(double(x(:)), 'int8'));
    end
elseif isstruct(x)
    hash_update(md, jsonencode(x));
else
    error('judo:hash', 'Cannot hash values of class %s.', class(x));
end
end
