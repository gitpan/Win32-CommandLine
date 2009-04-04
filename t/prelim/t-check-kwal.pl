#!perl -w   -- -*- tab-width: 4; mode: perl -*-
use Module::CPANTS::Analyse;

my $analyser=Module::CPANTS::Analyse->new({
   dist=> $ARGV[0],
});
$analyser->unpack;
$analyser->analyse;
$analyser->calc_kwalitee;
# results are in $analyser->d;
for (sort keys %{${$analyser->d}{error}}) { print "d{$_} = ".${$analyser->d}{error}{$_}."\n"; }

for (@{${$analyser->d}{error}{manifest_matches_dist}}) { print "error[] = $_\n"; }
#ignored_files_list
for (@{${$analyser->d}{files_array}}) { print "files[] = $_\n"; }
for (@{${$analyser->d}{ignored_files_array}}) { print "ignored[] = $_\n"; }