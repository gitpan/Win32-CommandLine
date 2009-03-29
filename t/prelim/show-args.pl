use Win32::CommandLine qw( command_line argv );

my $commandline = command_line();
my @ARGV2 = Win32::CommandLine::argv();

print "command_line = `$commandline`\n";
               print '--------'."\n";
$i = 0;
for (@ARGV)  { print "    ARGV[$i] = `$_`\n"; $i++; }
               print '--------'."\n";
$i = 0;
for (@ARGV2) { print "ARGV_NEW[$i] = `$_`\n"; $i++; }
