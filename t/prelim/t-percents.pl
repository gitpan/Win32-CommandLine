#$ENV{PERL5SHELL} = undef;
##$ENV{_} = '%';
#print qx{echo %_%};

@ARGV = Win32::CommandLine::argv() if eval { require Win32::CommandLine; };

print 'command_line() = `'.Win32::CommandLine::command_line()."`\n";

print "ARGV[]:\n";
for (@ARGV) { print $_."\n"; }
