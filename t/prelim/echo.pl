#!perl -w   -*- tab-width: 4; mode: perl -*-
use strict; use diagnostics;

use Win32::CommandLine;

print "command_line() = `".Win32::CommandLine::command_line()."`\n";
#print "-- ORIGINAL\n";
#print join(" ",@ARGV)."\n";

#@ARGV = Win32::CommandLine::argv() if eval { require Win32::CommandLine; };
#print "argv() = {@ARGV}\n";

@ARGV = Win32::CommandLine::_argv( Win32::CommandLine::command_line() ) if eval { require Win32::CommandLine; };
print "_argv() = {@ARGV}\n";

@ARGV = Win32::CommandLine::_argv( Win32::CommandLine::command_line(), {dosify => 1}  ) if eval { require Win32::CommandLine; };
print "_argv(dosify=t) = {@ARGV}\n";

#@ARGV = Win32::CommandLine::_argv_NEW( Win32::CommandLine::command_line() ) if eval { require Win32::CommandLine; };
#print "_argvNEW() = {@ARGV}\n";
#@ARGV = Win32::CommandLine::_argv_NEW( Win32::CommandLine::command_line(), {dosify => 1} ) if eval { require Win32::CommandLine; };
#print "_argvNEW(dosify=t) = {@ARGV}\n";

#print "-- REINTERPRETED\n";

#print "-- COMMANDLINE\n";
#print Win32::CommandLine::command_line()."\n";

#print "-- ENV{CMDLINE}\n";
#print $ENV{CMDLINE}."\n";
