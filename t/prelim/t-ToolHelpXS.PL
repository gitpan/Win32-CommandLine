#!perl -w  -- -*- tab-width: 4; mode: perl -*-

# t/00.load.t - check module loading

use strict;
use warnings;

{
## no critic ( ProhibitOneArgSelect RequireLocalizedPunctuationVars )
my $fh = select STDIN; $|++; select STDOUT; $|++; select STDERR; $|++; select $fh;	# DISABLE buffering (enable autoflush) on STDIN, STDOUT, and STDERR (keeps output in order)
}

#use Test::More tests => 4;
use Test::More;

use lib qw{ blib\arch };		# use build directory XS module { NOTE: must rebuild new .DLL before testing }

use_ok( $ENV{_BUILD_module_name} );

diag("Win32::CommandLine::_info_SIZEOF_HANDLE() = ".Win32::CommandLine::_info_SIZEOF_HANDLE());

diag("Win32::CommandLine::_const_MAX_PATH() = ".Win32::CommandLine::_const_MAX_PATH());

use constant TH32CS_SNAPPROCESS =>  0x00000002;
use constant INVALID_HANDLE_VALUE =>  -1;
use constant MAX_PATH =>  260;

is( Win32::CommandLine::_const_MAX_PATH(), MAX_PATH, "Verify MAX_PATH == 260");
is( Win32::CommandLine::_const_INVALID_HANDLE_VALUE(), INVALID_HANDLE_VALUE, "Verify INVALID_HANDLE_VALUE == -1");
is( Win32::CommandLine::_const_TH32CS_SNAPPROCESS(), TH32CS_SNAPPROCESS, "Verify TH32CS_SNAPPROCESS");

my @info_PROCESSENTRY32 = @{Win32::CommandLine::_info_PROCESSENTRY32()};

my $joined_info_PROCESSENTY32;
for my $element ( @info_PROCESSENTRY32 )
	{
	$joined_info_PROCESSENTY32 .= "[ @{$element} ]";
	}
diag("info_PROCESSENTRY32 = $joined_info_PROCESSENTY32");

my @info_PROCESSENTRY32_struct = @info_PROCESSENTRY32[ 1 .. @info_PROCESSENTRY32-1 ];
my $PROCESSENTRY32_template;
for my $element ( @info_PROCESSENTRY32_struct )
	{
	$PROCESSENTRY32_template .= ( $PROCESSENTRY32_template ? q{ } : q{} );
	$PROCESSENTRY32_template .= q{@}.join(q{}, @{$element}[ 2 .. @{$element}-1]);
	}
diag("PROCESSENTRY32_template = $PROCESSENTRY32_template");

# Take a snapshot of all processes in the system.

my $hProcessSnap = Win32::CommandLine::_wrap_CreateToolhelp32Snapshot( TH32CS_SNAPPROCESS, 0 );
#die "CreateToolhelp32Snapshot: $!($^E)" if $hProcessSnap == INVALID_HANDLE_VALUE;

diag("hProcessSnap = $hProcessSnap");

ok( $hProcessSnap != INVALID_HANDLE_VALUE, "Snapshot handle is NOT INvalid" );

# URLrefs: Perl pack Tutorial - Integers [ http://perldoc.perl.org/perlpacktut.html#Integers ; http://www.webcitation.org/5xnyRJ6fv @2011-04-08.2059 ] , MSDN Common Data Types (Definitions) [ http://msdn.microsoft.com/en-us/library/aa505945.aspx ; http://www.webcitation.org/5xnyIZN5p @2011-04-08.2058 ] 

# DWORD == unsigned long => L
# ULONG_PTR == pointer (same size as long long) => Q 	## ?? same on 32-bit platforms? 

#my $pack_template = '@0L! @4L! @8L! @16P @24L! @28L! @32L! @36l! @40L! @44Z260';

my $dwSize = length pack $PROCESSENTRY32_template;  								## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove

diag ("PROCESSENTRY32_template = $PROCESSENTRY32_template [length = $dwSize]");

is( Win32::CommandLine::_info_PROCESSENTRY32()->[0]->[1], $dwSize, "Verify PROCESSENTRY32 vs pack template [size]");

# URLref: http://www.perlmonks.org/?node_id=807366

#my $iBytes = length( pack 'I', $dwSize ); diag ("iBytes = $iBytes");
#my $lBytes = length( pack 'L!', $dwSize ); diag ("lBytes = $lBytes");
#my $jBytes = length( pack 'J', $dwSize ); diag ("jBytes = $jBytes");
#my $qBytes = eval { length( pack 'Q', $dwSize ) } || 0; diag ("qBytes = $qBytes");
#my $pBytes = length( pack 'P', $dwSize ); diag ("pBytes = $pBytes");

# see: IV definition (always large enough for pointers) @ http://perldoc.perl.org/perlguts.html#What-is-an-%22IV%22? [http://www.webcitation.org/5xo8LWer1 @2011-04-08.2331]
# see: Perl pack, definition of j and J templates as IV and UV, respectively @ http://perldoc.perl.org/functions/pack.html 
# see: Length of pack 'j/J' @ http://www.perlmonks.org/?node_id=869876 [http://www.webcitation.org/5xo8iKl17 @2011-04-08.2337]

my $ptrUnpack = 'J';
#if ($qBytes && ($pBytes > $lBytes)) { 
#	$ptrUnpack = 'Q'; 
#	## ?? warn if $qBytes < $pBytes
#	}

#my $dwSize = MAX_PATH + 36;  								## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
#my $pe32 = pack 'I9C260', $dwSize, 0 x 8, '0' x MAX_PATH;  	## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
my $pe32 = pack( $PROCESSENTRY32_template, $dwSize, (0) x 2, 0x0, (0) x 3, 0, 0, '0' x MAX_PATH );  	## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
my $lppe32 = unpack( $ptrUnpack, ( pack 'P', $pe32 ));		# URLref: http://perldoc.perl.org/perlpacktut.html#Pointers-for-How-to-Use-Them

# Retrieve information about the first process, and exit if unsuccessful
my %exes;
my %ppids;
my $ret = Win32::CommandLine::_wrap_Process32First( $hProcessSnap, $lppe32 );

do {
	if (not $ret) {
		Win32::CommandLine::_wrap_CloseHandle( $hProcessSnap );
		warn "Process32First: ret=$ret, $!($^E)";
		#last;
		exit;
	}

	# return ppid if pid == my pid
	
	my $th32ProcessID;
	my $th32ParentProcessID;
	my $szEXE;
	
	(undef, undef, $th32ProcessID, undef, undef, undef, $th32ParentProcessID, undef, undef, $szEXE) = unpack( $PROCESSENTRY32_template, $pe32 );

#	my $th32ProcessID = unpack 'I', substr $pe32, 8, 4;			## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
#	my $th32ParentProcessID = unpack 'I', substr $pe32, 24, 4;	## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
#	my $szEXE = q{};
#	my $i = 36;													## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
#	my $c = unpack 'C', substr $pe32, $i, 1;
#	while ($c) { $szEXE .= chr($c); $i++; $c = unpack 'C', substr $pe32, $i, 1; }
	$ppids{$th32ProcessID} = $th32ParentProcessID;
	$exes{$th32ProcessID} = $szEXE;
	
	##diag("$szEXE [id: $th32ProcessID; parent: $th32ParentProcessID]");
	
#	if ($$ == $th32ProcessID)
#		{
#		#print "thisEXE = $szEXE\n";
#		#print "parentPID = $th32ParentProcessID\n";
#		diag("thisEXE = $szEXE ; parentPID = $th32ParentProcessID");
#		return $th32ParentProcessID;
#		}
	#return unpack ('I', substr $pe32, 24, 4) if $$ == $th32ProcessID;

} while (Win32::CommandLine::_wrap_Process32Next( $hProcessSnap, $lppe32 ));

Win32::CommandLine::_wrap_CloseHandle( $hProcessSnap );

if ($ppids{$$}) {
	#print "ENV{CMDLINE} = $ENV{CMDLINE}\n";
	#print "thisEXE = $exes{$$}\n";
	#print "parentEXE = $exes{$ppids{$$}}\n";
	#return $ppids{$$};
	##$parentEXE = $exes{$ppids{$$}};
##	return $exes{$ppids{$$}};
##	diag("ENV{CMDLINE} = $ENV{CMDLINE}");
	diag("thisEXE = $exes{$$} [id: $$]");
	diag("parentEXE = $exes{$ppids{$$}} [id: $ppids{$$}]");
	#return $ppids{$$};
	##$parentEXE = $exes{$ppids{$$}};
	}

#### #### #### ####

done_testing();
