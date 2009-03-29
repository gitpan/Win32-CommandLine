@_[0] = '\\"t\\est';

for (@_ ? @_ : $_) { s/\\\"/\"/g }	# replace \"'s with "'s

print "@_";
