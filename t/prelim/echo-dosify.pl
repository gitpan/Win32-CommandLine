#!perl -w   -*- tab-width: 4; mode: perl -*-

#print "-- ORIGINAL\n";
#print join(" ",@ARGV)."\n";

@ARGV = Win32::CommandLine::argv( {dosify => 1} ) if eval { require Win32::CommandLine; };

#print "-- REINTERPRETED\n";
print join(" ",@ARGV)."\n";

#print "-- COMMANDLINE\n";
#print Win32::CommandLine::command_line()."\n";

#print "-- ENV{CMDLINE}\n";
#print $ENV{CMDLINE}."\n";
