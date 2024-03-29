#(emacs/sublime) -*- mode: perl; tab-width: 4; -*-
# lib\Win32\CommandLine.pm, v0.9_329 ( [git:blead] r329:e39a418974aa; Roy Ivy III <RIVY.dev@gMail.com> )
package Win32::CommandLine;

# Module Summary

=head1 NAME

Win32::CommandLine - Retrieve and reparse the Win32 command line

=head1 VERSION

=over

 $Win32::CommandLine::VERSION = version->declare( 'v0.9_329' );

=back

=cut

## Perl::Critic policy exceptions
## no critic ( ProhibitUselessNoCritic ) ## ToDO: revisit/remove
## no critic ( CodeLayout::ProhibitHardTabs CodeLayout::ProhibitParensWithBuiltins ProhibitPostfixControls RequirePodAtEnd )
## no critic ( RequireArgUnpacking RequireDotMatchAnything RequireExtendedFormatting RequireLineBoundaryMatching Capitalization ProhibitUnusedPrivateSubroutines ProhibitDeepNests ProhibitBacktickOperators ProhibitExcessComplexity ProhibitConstantPragma ProhibitCascadingIfElse RequireInterpolationOfMetachars ) # ToDO: revisit/remove

# URLref: [Bash - Shell Expansions] http://www.gnu.org/software/bash/manual/bashref.html#Shell-Expansions @@ http://www.webcitation.org/66XDGrX05

# Document phases of expansion output; add example tests to testing facility for command replacement; discuss surrouding quotes (for inner shell use of special characters [redirection, continuation, etc.])

# ToDO: look at parsing bug for "edit $library.bat" (parsing not proceeding @ 281)

# ToDO: rewrite the documentation to better explain "subshell argument replacement"; internal to the subshell, no processing is done (no globbing, etc) but the output is expanded after insertion back into the command line
#     * see URLref: http://www.gnu.org/software/bash/manual/bashref.html#Command-Substitution @@ http://www.webcitation.org/66WD19t5y

# ToDO: write a note to the perl developers to add a note about Win32::CommandLine to the perl README.win32 (eg, http://search.cpan.org/~flora/perl-5.14.2/README.win32 @@ http://www.webcitation.org/66PGpLoga)

# ToDO: ANSI C-quoting :: \XHH also currently is seen as a transform sequence (although capital versions of the other DO NOT cause a transformation)... ? remove \XHH or add capitals as acceptable for the other escapes? ## this needs research

# ToDO: Add tests to make sure I/O redirection works correctly (no eaten STDIN, etc...)

# ToDO: $ENV{~NAME} overrides ~NAME expansion, replacing the usual expansion, EXCEPT for $ENV{~} which does NOT override the expansion of ~
#        :: should $ENV{~} override ~ expansion?; should ~ expand twice? (eg, == expansion of ~<CURRENTUSER> [which would allow $ENV{~CURRENTUSER} to override) or be left as a seperate direct expansion?

# ToDO: normalize the handling of {}: currently, {} is passed through (GOOD), an unmatched { disappears (ERROR? or leave it on the line?), an unmatched } is passed through (GOOD?)
# TODO: think about refactoring for taint protection

# TODO: add taking nullglob from environment $ENV{nullglob}, use it if nullglob is not given as an option to the procedures (check this only in parse()?)

# TODO: deal with % bug -- how can we reliably transmit %'s to subcommands? TCC and CMD handle "%%" differently
#       ** CMD => %x => %x if %x doesn't exist
#       ** TCC => %x or %x% => <null> if %x doesn't exist
#       == NORMALIZE % handling => %% always => % for both CMD and TCC (both within and outside quotes); %x% => <null> if x doesn't exist

# DONE[but DOCUMENT][TODO:] deal with possible reinterpretation of $() by xx.bat ... ? $(<>) vs $"$(<>)" ... THINK ABOUT IT ==>> NO interpretation => leave it to the <COMMAND> if needed so that the commands get what they expect (use xx within the <COMMAND> if needed), and DOCUMENT THIS

use strict;
use warnings;
#use diagnostics;   # invoke blabbermouth warning mode
use 5.008008;       # earliest tested perl version (v5.8.8); v5.6.1 is no longer testable/reportable

# VERSION: major.minor[.release[.build]]  { minor is ODD => alpha/beta/experimental; minor is EVEN => stable/release }
# [NOTE: perl 'Extended Version' (multi-dot) format is prefered and created from any single dotted (major.minor) or non-dotted (major) versions; see 'perldoc version']
use version 0.77 qw(); our $VERSION = version->declare('v0.9_329');  ## no critic ( RequireConstantVersion )

# Module base/ISA and Exports

## ref: Good Practices/Playing Safe in 'perldoc Exporter'
## URLrefs: [base.pm vs @ISA: http://www.perlmonks.org/?node_id=643366]; http://search.cpan.org/perldoc?base; http://search.cpan.org/perldoc?parent; http://perldoc.perl.org/DynaLoader.html; http://perldoc.perl.org/Exporter.html
## TODO?: look into using Readonly::Array and Readonly::Hash for EXPORT_OK and EXPORT_TAGS
#use base qw( DynaLoader Exporter );    # use base qw(Exporter) => requires perl v5.8 (according to Perl::MinimumVersion)
#use parent qw( DynaLoader Exporter );  # use base qw(Exporter) => requires perl v5.8 (according to Perl::MinimumVersion)
#our @EXPORT = qw( );   # no default exported symbols
our (@ISA, @EXPORT_OK, %EXPORT_TAGS);   ## no critic ( ProhibitExplicitISA )
BEGIN {require DynaLoader; require Exporter; @ISA = qw( DynaLoader Exporter );}     ## no critic ( ProhibitExplicitISA )
{no strict 'refs'; ## no critic ( ProhibitNoStrict )
#our @EXPORT = qw( );   # no default exported symbols
%EXPORT_TAGS = (
    'ALL'       => [ (grep { /^(?!bootstrap|dl_load_flags|isa|qv|bsd_glob|glob)[^_][a-zA-Z_]*[a-z]+[a-zA-Z_]*$/ } keys %{__PACKAGE__.q{::}}) ],  ## no critic ( ProhibitComplexRegexes ProhibitEnumeratedClasses ) ## all non-internal symbols [Note: internal symbols are ALL_CAPS or start with a leading '_']
#   '_INTERNAL' => [ (grep { /^(?!bootstrap|dl_load_flags|isa|qv|bsd_glob|glob)[_][a-zA-Z_]*[a-z]+[a-zA-Z_]*$/ }  keys %{__PACKAGE__.q{::}}) ],  ## no critic ( ProhibitComplexRegexes ProhibitEnumeratedClasses ) ## all internal functions [Note: internal functions start with a leading '_']
    );
@EXPORT_OK = ( map { @{$_} } values %EXPORT_TAGS );
}

# Module Interface

sub command_line;   # return Win32 command line string
sub parse;          # parse string as a "bash-like" command line (globbing and subshell command substitution are done, but no other substitions)
sub argv;           # get commandline and reparse it, returning a new ARGV array

####

# Module Implementation

##bootstrap Win32::CommandLine (($^V lt v5.8.9) ? $VERSION : $VERSION->normal);       ## no critic ( ProhibitPunctuationVars ProhibitMagicNumbers ProhibitMismatchedOperators )   ## ? ProhibitMismatchedOperators -- CHECK the comparison for correctness
bootstrap Win32::CommandLine $VERSION;

sub command_line{
    # command_line(): returns $
    my $retVal = _wrap_GetCommandLine();

    ## TODO: add %% => % test (for both TCC and CMD)
    $retVal =~ s/%%/%/g;    # %% => % [ standardize %% handling for CMD and TCC ]

    #print "c_l retVal = $retVal\n";

    # 4NT/TCC/TCMD compatibility
    my $parentEXE = _getparentname();
    if ($parentEXE && ($parentEXE =~ /(?:4nt|tcc|tcmd)[.](?:com|exe|bat)$/i) && $ENV{CMDLINE}) { $retVal = $ENV{CMDLINE}; }

    return $retVal;
}

sub argv{
    # argv( [\%] ): returns @
    return parse( command_line(), @_ );     # get commandline and reparse it returning the new ARGV array
}

sub parse{
    # parse( $ [,\%] ): returns @
    # parse scalar as a command line string (bash-like parsing of quoted strings with globbing of resultant tokens, but no other expansions or substitutions are performed [ie, no variable substitution is performed])
    return _argv( @_ );
}

use Carp qw();
use Carp::Assert qw();

#use Regexp::Autoflags;
#use Readonly;
#use Getopt::Clade;
#use Getopt::Euclid;
#use Class::Std;

use File::Spec qw();
use File::Which qw();

#use Data::Dumper::Simple;

my %_G = ( # package globals
    q                   => q{'},                    # '
    qq                  => q{"},                    # "
    single_q            => q{'},                    # '
    double_q            => q{"},                    # "
    quote               => q{'"},                   # ' and "
    quote_meta          => quotemeta q{'"},     # quotemeta ' and "
    escape_char         => q{\\},                   # escape character (\)
    glob_char           => '?*[]{}',                # glob signal characters (no '~' for Win32)
    unbalanced_quotes   => 0,
    );

#BEGIN{ ## doesn't need to be a BEGIN for COMSPEC changes
    # ToDO: create a development blog (generic is fine) backed by WebCite, so that comments like this can be shortened with a URLref to the WebCite article
    #    :: change the blog entry as needed,and WebCite it again... the reference here will show the most current iteration as well as old versions
    # ToDO: update the documentation to note this under-the-sheets change (should have little or no impact, but give out the information in the GOTCHAS section)
    ## FIX: the BUG noted below breaks STDIN redirection via <
    # so ... plan to just set COMSPEC, update the comments and notes, and be done
    # NOTE: we REQUIRE a working subshell mechanism, so enforce it (? warning if we change anything like COMSPEC for subshell execution?)
    # ToDO: rework this to better respect the users settings/wishes, but default to a working system avoiding mismatched subshell execution (eg, using "cmd.exe /x/d/c", ? prefix with unixified $ENV{SystemRoot}?)
    # ToDO: when  done, remove the extra code from the perl scripts in @bin (wrap-cpan, etc)
    # ??: but what if Win32::CommandLine is NOT installed for those scripts?
    # see this code from wrap-cpan:
    ##  # avoid differing shells for COMSPEC and Perl subshell execution; this can cause weird behavior (eg, TCC parsing a BAT file but executing it with CMD, which causes all sorts of trouble)
    ##  # assume user knows best, however; so, if Perl5Shell is set, leave it alone
    ##  $ENV{COMSPEC} = $ENV{SystemRoot}.q{\\System32\\cmd.exe} if ($^O eq 'MSWin32') and not $ENV{PERL5SHELL} and -e $ENV{SystemRoot}.q{\\System32\\cmd.exe};
    # so, leave PERL5SHELL alone, but set COMSPEC as needed?
    # _initialize_subshell_calls()
    # Test and, if needed, create a working system() call by setting PERL5SHELL
    # URLrefs:
    # [PerlDoc - PerlRUN (see PERL5SHELL)] http://perldoc.perl.org/perlrun.html @@ http://www.webcitation.org/66PEuU5YJ
    # [system call error 'Can't spawn "cmd.exe": No such file or directory at ...' ] http://www.perlmonks.org/?node=392416 @@ http://www.webcitation.org/66PEdGziA
    # [PERL5SHELL Info] http://www.perlmonks.org/bare/?node_id=112690 @@ http://www.webcitation.org/66PEjrl2y
    # NOTE: BEGIN is used because once a system() or backtick call has been issued, perl seems to ignore any changes to PERL5SHELL, so PERL5SHELL must be correct before any system() or backtick calls are done
    # NOTE: generally, assume the user knows what they are doing, PERL5SHELL will either be empty or set up correctly corresponding to an executable in the PATH, so only change it if undefined
    # NOTE: no changes to PATH (once again, user knows best)

    ## $ENV{COMSPEC} = $ENV{SystemRoot}.q{\\System32\\cmd.exe} if ($^O eq 'MSWin32') and not $ENV{PERL5SHELL} and -e $ENV{SystemRoot}.q{\\System32\\cmd.exe};   # avoid shell/sub-shell mismatches (see <BLOGPOST>)
    ## possible short comments
    ## :: avoid shell/sub-shell mismatches
    ## :: increase multishell environment robustness & avoid shell/sub-shell mismatches
    ## :: may not be necessary if we stop using TCC
    ## :: NOTE: [2013-06-24] msys uses COMSPEC=c:\Windows\SysWOW64\cmd.exe on 64-bit systems (? why: it looks like MSYS depends on "PROCESSOR_ARCHITECTURE=x86" in subshells, not sure why...)

{
## no critic ( ProhibitExcessComplexity ProhibitPunctuationVars RequireLocalizedPunctuationVars )
    my $msg;

    if (($^O eq 'MSWin32') and not $ENV{PERL5SHELL}) {
        my $regex = quotemeta( $ENV{SystemRoot}.q{\\} ) . q{(System32|SysWOW64)} . quotemeta( q{\\cmd.exe} );
        if (not $ENV{COMSPEC} =~ m/$regex/i) {
            if (-e $ENV{SystemRoot}.q{\\system32\\cmd.exe}) {
                $ENV{COMSPEC} = $ENV{SystemRoot}.q{\\system32\\cmd.exe};
                $msg = q{WARNING: $ENV{COMSPEC} has been reset and now points to CMD.exe (for compatibility, since Perl defaults to using "cmd.exe /x/d/c" for subshell execution); set $ENV{PERL5SHELL} or use the usual CMD.exe $ENV{COMSPEC} to correct this problem};
                }
            else { $msg = q{WARNING: $ENV{COMSPEC} may be incompatible with Perl subshell execution and CMD.exe was not found; set $ENV{PERL5SHELL} or use the usual CMD.exe $ENV{COMSPEC} to correct this problem}; }
            }
        }

    # my $isWorkingSystem;
    # my $cmd = q{};
    # my $exe;
    # my $p5s; my $badP5S = 0;
    # my $onPATH = 0;
    # my $msg;
    # $exe = 'CMD.exe';
    # if (defined $ENV{PERL5SHELL}) {
        # # separate PERL5SHELL into components (assumes a string which is space-delimited with possible double-quote quoting)
        # # URLref: http://perldoc.perl.org/perlfaq4.html#How-can-I-split-a-%5bcharacter%5d-delimited-string-except-when-inside-%5bcharacter%5d%3f
        # my @tokens = (); my $text = $ENV{PERL5SHELL}; my $sep = q{ };
        # push(@tokens, $+) while $text =~ m{ "([^\"\\]*(?:\\.[^\"\\]*)*)"$sep?|([^$sep]+)$sep?|$sep}g;  ## no critic ( ProhibitPunctuationVars ) # ToDO: remove/revisit
        # push(@tokens, undef) if substr($text,-1,1) eq $sep;   ## no critic ( ProhibitMagicNumbers ) # ToDO: remove/revisit
        # #print "tokens = [ ".join(',', @tokens)." ]\n";
        # $exe = $tokens[0];
        # # PERL5SHELL must use doubled backslashes as path seperators in the executable path (if any are needed)
        # if ($exe =~ m/\//) { $exe = q{}; }                        # slashes as path seperators are incorrect (the executable path will be invalid for system() and backtick execution)
        # $exe =~ s/\\\\/\//g; $exe =~ s/\\//g; $exe =~ s/\//\\/g;  # remove single slashes and turn any doubled backslashes into singles for an interpretation equivalent to system() and backtick execution
        # #print qq{exe = "$exe"\n};
        # if (@tokens < 2) { $badP5S = 1; }
        # };
    # if (-e $exe) {
        # $cmd = $exe;
        # #print "found directly @ '$cmd'\n";
        # $onPATH = 1;
        # }
    # if (not -e $cmd) {
        # # look for exe on PATH
        # my @paths = split(/;/,$ENV{PATH});
        # foreach my $path (@paths) {
            # #print qq{looking for '$exe' on PATH @ '$path'\n};
            # if (-e "$path\\$exe") {
                # $cmd = "$path\\$exe";
                # #print qq{found on PATH @ '$cmd'\n};
                # $onPATH = 1;
                # last;
                # }
            # }
        # }
    # if (not -e $cmd and defined $ENV{PERL5SHELL}) { $badP5S = 1; }
    # if (not -e $cmd and -e $ENV{SystemRoot}.'\\System32\\CMD.exe') {
        # # set full path to CMD.exe (for WindowsXP+)
        # $cmd = $ENV{SystemRoot}.'\\System32\\CMD.exe';
        # #print "found @ $cmd\n";
        # }
    # if (not -e $cmd and -e $ENV{COMSPEC}) {
        # $cmd = $ENV{COMSPEC};
        # #print "found in COMSPEC @ $cmd\n";
        # }
    # if (-e $cmd) {
        # $p5s = $cmd;
        # $p5s =~ s/\\/\\\\/g;
        # #$p5s .= ' /x/c'; ## [no /d for subshell consistency] ; /x == /E:ON == Enable command extensions ; /c  == transient shell (execute command and return) :: NOTE: this avoids concerns about autorun changing the subshell environment in unexpected ways
        # $p5s .= ' /x/d/c';    ## /x == /E:ON == Enable command extensions ; /d == Disable execution of AutoRun commands ; /c  == transient shell (execute command and return) :: NOTE: this assumes that CMD autorun doesn't modify the environment (strange unexpected things can happen if this is note true)
        # }
    # if ($badP5S) { if (not $msg) { $msg = q{ERROR: PERL5SHELL is set incorrectly}.($onPATH ? q{} : qq{; the executable [$exe] was not found (PATH was also searched)}).($p5s ? qq{; try "set PERL5SHELL=$p5s" to correct this problem} : q{}).q{\n} } };
    # if (not $onPATH and not defined $ENV{PERL5SHELL} and $p5s) {
        # $ENV{PERL5SHELL} = $p5s;      ## no critic ( RequireLocalizedPunctuationVars )
        # if (not $msg) { $msg = qq{WARNING: PERL5SHELL was not set and CMD.exe not found on PATH; autocorrected [now, PERL5SHELL="$ENV{PERL5SHELL}"]; try "set PERL5SHELL=$ENV{PERL5SHELL}" to correct this problem\n} };
        # }
    # #print "ENV{PERL5SHELL}=$ENV{PERL5SHELL}\n";
# #!# BUG: the EVAL eats all STDIN redirected with "<"
# #!#   $isWorkingSystem = eval { ``; return ( $? ? 0 : 1 ) };  # quietly test system() and backtick subshell calls
# #!#   if (not $isWorkingSystem) { if (not $msg) { $msg = q{ERROR: Unable to find a shell (eg, CMD.exe) for system(); to correct the problem, add path for CMD.exe to PATH or set PERL5SHELL}.($p5s ? qq{; try "set PERL5SHELL=$p5s" to correct this problem} : q{}).q{\n} } };
    if ($msg and not $ENV{HARNESS_ACTIVE}) { print {*STDERR} 'Win32::CommandLine :: '.$msg.qq{\n}; };  ## no critic ( RequireCheckedSyscalls ) # ToDO: remove/revisit
}

sub _getparentname {
    ## no critic ( ProhibitConstantPragma ProhibitPunctuationVars ) # ToDO: remove/revisit
    # _getparentname( <null> ): returns $
    # find parent process ID and return the exe name
    # DONE :: TODO?: add to .xs and remove Win32::API recommendation/dependence
    # ToDO: look into Win32::ToolHelp (currently, doesn't compile under later ActivePerl or strawberry 5.12)
    my $have_Win32_API = 0; #eval { require Win32::API; 1; };
    if ($have_Win32_API) {
        # modified from prior anon author
        my $CreateToolhelp32Snapshot;       # define API calls
        my $Process32First;
        my $Process32Next;
        my $CloseHandle;

        if (not defined $CreateToolhelp32Snapshot) {
            #$CreateToolhelp32Snapshot = new Win32::API ('kernel32','CreateToolhelp32Snapshot', 'II', 'N') or die "import CreateToolhelp32Snapshot: $!($^E)";
            #$Process32First = new Win32::API ('kernel32', 'Process32First','IP', 'N') or die "import Process32First: $!($^E)";
            #$Process32Next = new Win32::API ('kernel32', 'Process32Next', 'IP','N') or die "import Process32Next: $!($^E)";
            #$CloseHandle = new Win32::API ('kernel32', 'CloseHandle', 'I', 'N') or die "import CloseHandle: $!($^E)";
            {
            ## no critic ( ProhibitIndirectSyntax ) ## ToDO: remove/revisit
            $CreateToolhelp32Snapshot = new Win32::API ('kernel32','CreateToolhelp32Snapshot', 'II', 'N') or return;
            $Process32First = new Win32::API ('kernel32', 'Process32First','IP', 'N') or return;
            $Process32Next = new Win32::API ('kernel32', 'Process32Next', 'IP','N') or return;
            $CloseHandle = new Win32::API ('kernel32', 'CloseHandle', 'I', 'N') or return;
            }
        }

        use constant TH32CS_SNAPPROCESS =>  0x00000002;
        use constant INVALID_HANDLE_VALUE =>  -1;
        use constant MAX_PATH =>  260;

        # Take a snapshot of all processes in the system.

        my $hProcessSnap = $CreateToolhelp32Snapshot-> Call(TH32CS_SNAPPROCESS, 0);
        #die "CreateToolhelp32Snapshot: $!($^E)" if $hProcessSnap == INVALID_HANDLE_VALUE;
        return (undef) if $hProcessSnap == INVALID_HANDLE_VALUE;

        #   Struct PROCESSENTRY32:
        #   DWORD dwSize;           #  0 for 4
        #   DWORD cntUsage;         #  4 for 4
        #   DWORD th32ProcessID;        #  8 for 4
        #   DWORD th32DefaultHeapID;    # 12 for 4
        #   DWORD th32ModuleID;     # 16 for 4
        #   DWORD cntThreads;       # 20 for 4
        #   DWORD th32ParentProcessID;  # 24 for 4
        #   LONG  pcPriClassBase;       # 28 for 4
        #   DWORD dwFlags;          # 32 for 4
        #   char szExeFile[MAX_PATH];   # 36 for 260

        # Set the size of the structure before using it.

        my $dwSize = MAX_PATH + 36;                                 ## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
        my $pe32 = pack 'I9C260', $dwSize, 0 x 8, '0' x MAX_PATH;   ## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
        my $lppe32 = pack 'P', $pe32;

        # Retrieve information about the first process, and exit if unsuccessful
        my %exes;
        my %ppids;
        my $ret = $Process32First-> Call($hProcessSnap, $pe32);
        do {
            if (not $ret) {
                $CloseHandle-> Call($hProcessSnap);
                Carp::carp "Process32First: ret=$ret, $!($^E)";
                #last;
                return;
            }

            # return ppid if pid == my pid

            my $th32ProcessID = unpack 'I', substr $pe32, 8, 4;         ## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
            my $th32ParentProcessID = unpack 'I', substr $pe32, 24, 4;  ## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
            my $szEXE = q{};
            my $i = 36;                                                 ## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
            my $c = unpack 'C', substr $pe32, $i, 1;
            while ($c) { $szEXE .= chr($c); $i++; $c = unpack 'C', substr $pe32, $i, 1; }
            $ppids{$th32ProcessID} = $th32ParentProcessID;
            $exes{$th32ProcessID} = $szEXE;
        #   if ($$ == $th32ProcessID)
        #       {
        #       #print "thisEXE = $szEXE\n";
        #       #print "parentPID = $th32ParentProcessID\n";
        #       return $th32ParentProcessID;
        #       }
            #return unpack ('I', substr $pe32, 24, 4) if $$ == $th32ProcessID;

        } while ($Process32Next-> Call($hProcessSnap, $pe32));

        $CloseHandle-> Call($hProcessSnap);

        if ($ppids{$$}) {
            #print "ENV{CMDLINE} = $ENV{CMDLINE}\n";
            #print "thisEXE = $exes{$$}\n";
            #print "parentEXE = $exes{$ppids{$$}}\n";
            #return $ppids{$$};
            ##$parentEXE = $exes{$ppids{$$}};
            return $exes{$ppids{$$}};
            }
        #return;
        }
    return;
}

sub _dosify {
    # _dosify( <null>|$|@ ): returns <null>|$|@ ['shortcut' function]
    # dosify string, returning a string which will be interpreted/parsed by DOS/CMD as the input string when input to the command line
    # TODO: NOTE: this also changes '/' to '\' which is fine for files but not so good for strings ... LOOK INTO this...
    # CMD/DOS quirks: dosify double-quotes:: {\\} => {\\} UNLESS followed by a double-quote mark when {\\} => {\} and {\"} => {"} (and doesn't end the quote)
    #   :: EXAMPLES: {a"b"c d} => {[abc][d]}, {a"\b"c d} => {[a\bc][d]}, {a"\b\"c d} => {[a\b"c d]}, {a"\b\"c" d} => {[a\b"c"][d]}
    #                {a"\b\\"c d} => {[a\b\c][d]}, {a"\b\\"c" d} => {[a\b\c d]}, {a"\b\\"c d} => {[a\b\c][d]}, {a"\b\\c d} => {[a\b\\c d]}
    @_ = @_ ? @_ : $_ if defined wantarray;     ## no critic (ProhibitPostfixControls)  ## break aliasing if non-void return context

    ## no critic ( ProhibitUnusualDelimiters ) # ToDO: remove/revisit

    # TODO: check these characters for necessity => PIPE characters [<>|] and internal double quotes for sure, _likely_ escape character [^], [%]?, [:]?, [*?] glob chars needed?, what about glob character set chars [{}]?
    #   **  should we make the assumption that these are paths? or pass an argument to that effect (eg, path => 0/1) _OR_ separate function (ie, _dosify_path() )?
    my $dos_special_chars = '"<>|^';
    my $dc = quotemeta( $dos_special_chars );
    for (@_ ? @_ : $_)
        {
        #print "_ = $_\n";
        s:\/:\\:g;                              # forward to back slashes
        if ( $_ =~ qr{(\s|[$dc])} )
            {# found whitespace and/or special characters which must be double quoted
            #print "in qr\n";
            s:":\\":g;                          # CMD: preserve double-quotes with backslash    # TODO: change to $dos_escape
            s:([\\]+)\\":($1 x 2).q{\\"}:eg;    ## no critic ( ProhibitUnusedCapture ) ## double backslashes in front of any \" to preserve them when interpreted by DOS/CMD
            $_ = q{"}.$_.q{"};                  # quote the final token
            };
        }

    return wantarray ? @_ : "@_";
}

sub _dos_quote {
    # _dos_quote( <null>|$|@ ): returns <null>|$|@ ['shortcut' function]
    # quote string in DOS manner, returning a string which will be interpreted/parsed by DOS/CMD as the input string when input to the command line
    # CMD/DOS quirks: dosify double-quotes:: {\\} => {\\} UNLESS followed by a double-quote mark when {\\} => {\} and {\"} => {"} (and doesn't end the quote)
    #   :: EXAMPLES: {a"b"c d} => {[abc][d]}, {a"\b"c d} => {[a\bc][d]}, {a"\b\"c d} => {[a\b"c d]}, {a"\b\"c" d} => {[a\b"c"][d]}
    #                {a"\b\\"c d} => {[a\b\c][d]}, {a"\b\\"c" d} => {[a\b\c d]}, {a"\b\\"c d} => {[a\b\c][d]}, {a"\b\\c d} => {[a\b\\c d]}
    @_ = @_ ? @_ : $_ if defined wantarray;     ## no critic (ProhibitPostfixControls)  ## break aliasing if non-void return context

    ## no critic ( ProhibitUnusualDelimiters ) # ToDO: remove/revisit

    # TODO: check these characters for necessity => PIPE characters [<>|] and internal double quotes for sure, [:]?, [*?] glob chars needed?, what about glob character set chars [{}]?
    my $dos_special_chars = '"<>|';
    my $dc = quotemeta( $dos_special_chars );
    for (@_ ? @_ : $_)
        {
        #print "_ = $_\n";
        #s:\/:\\:g;                             # forward to back slashes
        if ( $_ =~ qr{(\s|[$dc])} )
            {
            #print "in qr\n";
            s:":\\":g;                          # CMD: preserve double-quotes with backslash    # TODO: change to $dos_escape
            s:([\\]+)\\":($1 x 2).q{\\"}:eg;    ## no critic ( ProhibitUnusedCapture ) ## double backslashes in front of any \" to preserve them when interpreted by DOS/CMD
            $_ = q{"}.$_.q{"};                  # quote the final token
            };
        }

    return wantarray ? @_ : "@_";
}

{
sub _decode; # _decode( <null>|$|@ ): returns <null>|$|@ ['shortcut' function]
my %table;
###
## ANSI Escape Character Sequences (based on bash ANSI-C quoting (from C/C++); URLrefs: http://www.gnu.org/software/bash/manual/html_node/ANSI_002dC-Quoting.html @@ http://www.webcitation.org/66WCe6rMT; http://msdn.microsoft.com/en-us/library/6aw8xdf2.aspx @@ http://www.webcitation.org/66WCHgnjV)
#Escape Sequences
#\\ - 0x5c - Backslash
#\' - 0x27 - Single Quote (not sure if it is hex 27 ???)
#\" - 0x22 - Double Quote (not sure if it is hex 22 ???)
#\? - 0x3f - Question Mark
#\0 - 0x00 - null
#\a - 0x07 - Alert = Produces an audible or visible alert.
#\b - 0x08 - Backspace = Moves the cursor back one position (non-destructive).
#\f - 0x0c - Form Feed = Moves the cursor to the first position of the next page.
#\n - 0x0a - New Line = Moves the cursor to the first position of the next line.
#\r - 0x0d - Carriage Return = Moves the cursor to the first position of the current line.
#\t - 0x09 - Horizontal Tab = Moves the cursor to the next horizontal tabular position.
#\v - 0x0b - Vertical Tab = Moves the cursor to the next vertical tabular position.
#
#Numeric Escape Sequences
#\nnn - n = octal digit, 8 bit
#\xnn - n = hexadecimal digit, 8 bit
#\Xnn - n = hexadecimal digit, 8 bit    # ToDO: ? remove capital (not in most specifications)
#\unnnn - n = hexadecimal digit, 16 bit
#\Unnnnnnnn - n = hexadecimal digit, 32 bit###
#              \a     alert (bell)
#              \b     backspace
#              \e     an escape character
#              \f     form feed
#              \n     new line
#              \r     carriage return
#              \t     horizontal tab
#              \v     vertical tab
#              \\     backslash
#              \'     single quote
#              \nnn   the eight-bit character whose value is the octal value  nnn  (one  to
#                     three digits)
#              \xHH   the  eight-bit character whose value is the hexadecimal value HH (one
#                     or two hex digits)
#              \XHH   the  eight-bit character whose value is the hexadecimal value HH (one
#                     or two hex digits)
#              \cx    a control-x character
#
# Not implemented (not used in bash):
#\unnnn - n = hexadecimal digit, 16 bit
#\Unnnnnnnn - n = hexadecimal digit, 32 bit
## n#o critic ( ProhibitMagicNumbers )

$table{'0'} = chr(0x00);    ## no critic ( ProhibitMagicNumbers )   # NUL (REMOVE: implemented with octal section)
$table{'a'} = "\a";                                                 # BEL
$table{'b'} = "\b";                                                 # BS
$table{'e'} = "\e";                                                 # ESC
$table{'f'} = "\f";                                                 # FF
$table{'n'} = "\n";                                                 # NL
$table{'r'} = "\r";                                                 # CR
$table{'t'} = "\t";                                                 # TAB/HT
$table{'v'} = chr(0x0b);    ## no critic ( ProhibitMagicNumbers )   # VT

$table{$_G{'single_q'}} = $_G{single_q};            # single-quote
$table{$_G{'double_q'}} = $_G{double_q};            # double-quote
$table{$_G{'escape_char'}} = $_G{escape_char};      # backslash-escape

#octal
#   for (my $i = 0; $i < oct('1000'); $i++) { $table{sprintf("%3o",$i)} = chr($i); }
for my $i (0..oct('7')) { $table{sprintf('%1o',$i)} = $table{sprintf('%0.2o',$i)} = $table{sprintf('%0.3o',$i)} = chr($i); }
for my $i (oct('10')..oct('77')) { $table{sprintf('%0.2o',$i)} = $table{sprintf('%0.3o',$i)} = chr($i); }
for my $i (oct('100')..oct('777')) { $table{sprintf('%0.3o',$i)} = chr($i); }

#hex
#   for (my $i = 0; $i < 0x10; $i++) { $table{"x".sprintf("%1x",$i)} = chr($i); $table{"X".sprintf("%1x",$i)} = chr($i); $table{"x".sprintf("%2x",$i)} = chr($i); $table{"X".sprintf("%2x",$i)} = chr($i); }
#   for (my $i = 0x10; $i < 0x100; $i++) { $table{"x".sprintf("%2x",$i)} = chr($i); $table{"X".sprintf("%2x",$i)} = chr($i); }
for my $i (0..0xf) { $table{'x'.sprintf('%1x',$i)} = $table{'X'.sprintf('%1x',$i)} = $table{'x'.sprintf('%0.2x',$i)} = $table{'X'.sprintf('%0.2x',$i)} = chr($i); }      ## no critic ( ProhibitMagicNumbers ) ##
for my $i (0x10..0xff) { $table{'x'.sprintf('%2x',$i)} = $table{'X'.sprintf('%2x',$i)} = chr($i); }                                                                                    ## no critic ( ProhibitMagicNumbers ) ##

#control characters
#   for (my $i = 0; $i < 0x20; $i++) { $table{"c".chr(ord('@')+$i)} = chr($i); }
my $base_char = ord(q{@});
for my $i (0..(0x20 - 1)) { $table{'c'.chr($base_char+$i)} = chr($i); }     ## no critic ( ProhibitMagicNumbers ) ##
$table{'c?'} = chr(0x7f);                                                   ## no critic ( ProhibitMagicNumbers ) ##

sub _decode {
    # _decode( <null>|$|@ ): returns <null>|$|@ ['shortcut' function]
    # decode ANSI C string
    @_ = @_ ? @_ : $_ if defined wantarray;     ## no critic (ProhibitPostfixControls)  ## break aliasing if non-void return context

#   my $c = quotemeta('0abefnrtv'.$_G{escape_char}.$_G{single_q}.$_G{double_q});
    my $c = quotemeta('abefnrtv'.$_G{escape_char}.$_G{single_q}.$_G{double_q});     # \0 is covered by octal matches
    #for my $k (sort keys %table) { #print "table{:$k:} = $table{$k}\n";}
#   for (@_ ? @_ : $_) { s/\\([$c]|[0-7]{1,3}|x[0-9a-fA-F]{2}|X[0-9a-fA-F]{2}|c.)/:$1:/g }
#   for (@_ ? @_ : $_) { s/\\([0-7]{1,3}|[$c]|x[0-9a-fA-F]{2}|X[0-9a-fA-F]{2}|c.)/$table{$1}/g } ## no critic ( ProhibitEnumeratedClasses ) ##
    for (@_ ? @_ : $_) { s/\\([0-7]{1,3}|[$c]|x[0-9a-fA-F]{2}|c.)/$table{$1}/g } ## no critic ( ProhibitEnumeratedClasses ) ## ToDO: \XHH no longer matches (TEST and remove this comment)

    return wantarray ? @_ : "@_";
    }
}


sub _decode_qq {
    # _decode_qq( <null>|$|@ ): returns <null>|$|@ ['shortcut' function]
    # decode double quoted string (replace internal \" with ")
    @_ = @_ ? @_ : $_ if defined wantarray;     ## no critic (ProhibitPostfixControls)  ## break aliasing if non-void return context

    my $c = quotemeta(q{"}.$_G{escape_char});
    for (@_ ? @_ : $_) { s/\\([$c])/$1/g }; # replace \<x>'s with <x>'s

    return wantarray ? @_ : "@_";
}

sub _decode_dosqq {
    # _decode_dosqq( <null>|$|@ ): returns <null>|$|@ ['shortcut' function]
    # decode double quoted string (replace internal \" with ")
    # CMD/DOS quirk NOTES:
    #   {\\} => {\\} UNLESS followed by a double-quote mark, then {\\"} => {\"} and {\"} => {"} (acting just as a character and not an enclosing quotation mark)
    #   EOL acts as a closing quotation mark
    # EXAMPLES: {"\" a} => {\" a}, {"\"" a} => {" \"}
    # ODDNESS: {"a ""} => {a "}, {"a """} => {a "}
    #   ## it seems double double-quotes leave a double-quote character AND close the QUOTATION (this is NOT implemented right now as the parsing regular expressions see it as an end quote, then another starting quote)
    # TODO: Make it work for the most part now THEN TEST, adding PATHOLOGIC cases as necessary (or leaving it 'more logical' and documenting the issues)
    @_ = @_ ? @_ : $_ if defined wantarray;     ## no critic (ProhibitPostfixControls)  ## break aliasing if non-void return context

    ## no critic ( ProhibitUnusualDelimiters ) # ToDO: remove/revisit

    my $e = quotemeta q{\\};    # escape character
    my $q = quotemeta q{"};     # double-quote (")
    for (@_ ? @_ : $_)
        {
        #Carp::Assert::assert( not /(?<!$e)$q$q/, '_decode_dosqq: sequential double-quotes without preceeding escape character not allowed' );      # ASSERT: no internal "" unless preceeded by \  (current parsing should not allow this to happen)
        s:([$e]+)([$q]):((substr $1, 0, 1) x (length($1)/2)).$2:eg;
        }

    return wantarray ? @_ : "@_";
}

sub _decode_dollarqq {
    # _decode_qq( <null>|$|@ ): returns <null>|$|@ ['shortcut' function]
    # decode double quoted string (replace internal \" with ")
    @_ = @_ ? @_ : $_ if defined wantarray;     ## no critic (ProhibitPostfixControls)  ## break aliasing if non-void return context

    my $c = quotemeta(q{$"}.$_G{escape_char});      ## no critic ( RequireInterpolationOfMetachars )
    for (@_ ? @_ : $_) { s/\\([$c])/$1/g }; # replace \<x>'s with <x>'s

    return wantarray ? @_ : "@_";
}

sub _is_const { my $is_const = !eval { ($_[0]) = $_[0]; 1; }; return $is_const; }

sub _ltrim {
    # _ltrim( $|@:STRING(s) [,\%:OPTIONAL_ARGS] ): returns $|@ ['shortcut' function] (with optional hash_ref containing function options)
    # trim leading characters (defaults to whitespace)
    # NOTE: not able to currently determine the difference between a function call with a zero arg list {"f(());"} and a function call with no arguments {"f();"}
    #       so, by the Principle of Least Surprise, f() in void context is disallowed instead of being an alias of "f($_)" so that f(@array) doesn't silently perform f($_) when @array has zero elements
    #       carp on f(<empty>) in void context
    #       use "f($_)" instead of "f()" when needed
    # NOTE: alternatively, could use _ltrim( <null>|$|\@[,\%] ), carping on more than one argument
    # NOTE: alternatively, could use _ltrim( <null>|$|@|\@[,\%] ), carping on more than one argument
    # NOTE: Perl6 (if it ever arrives) CAN see a difference between "f()" and "f(())", so we may re-enable the ability to use f() as an alias for f($_)
    # NOTE: after thinking and reading PBP (specifically Dollar-Underscore (p85) and Interator Variables (p105)), I think disallowing zero arguments is for the best.
    #       making operation on $_ require explicit coding breeds more maintainable code with little extra effort
    # so:
    #   $foo = _ltrim($bar);
    #   @foo = _ltrim(@bar) if @bar;
    #   $foo = _ltrim(@bar) if @bar;
    #   _ltrim($bar);
    #   _ltrim(@bar) if @bar;
    #   $foo = _ltrim($_);
    #   _ltrim($_);
    #   @bar = (); $xxx = ltrim(@bar);  ## ERROR
    #   $xxx = ltrim();                 ## ERROR
    #   ltrim();                        ## ERROR
    my %opt = (
        trim_re => '\s+',
        );

    my $me = (caller(0))[3];    ## no critic ( ProhibitMagicNumbers )   ## caller(EXPR) => ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller($i);
    my $opt_ref;
    $opt_ref = pop @_ if ( @_ && (ref($_[-1]) eq 'HASH'));  ## no critic (ProhibitPostfixControls)  ## pop last argument only if it's a HASH reference (assumed to be options for our function)
    if ($opt_ref) { for (keys %{$opt_ref}) { if (exists $opt{$_}) { $opt{$_} = $opt_ref->{$_}; } else { Carp::carp "Unknown option '$_' for function ".$me; return; } } }
    if ( !@_ && !defined(wantarray) ) { Carp::carp 'Useless use of '.$me.' with no arguments in void return context (did you want '.$me.'($_) instead?)'; return; } ## no critic ( RequireInterpolationOfMetachars ) #
    if ( !@_ ) { Carp::carp 'Useless use of '.$me.' with no arguments'; return; }

    my $t = $opt{trim_re};

    my $arg_ref;
    $arg_ref = \@_;
    $arg_ref = [ @_ ] if defined wantarray;     ## no critic (ProhibitPostfixControls)  ## break aliasing if non-void return context

    for my $arg ( @{$arg_ref} ) {
        if (_is_const($arg)) { Carp::carp 'Attempt to modify readonly scalar'; return; }
        $arg =~ s/\A$t//;
        }

    return wantarray ? @{$arg_ref} : "@{$arg_ref}";
    }

sub _gen_delimeted_regexp {
    # _gen_delimeted_regexp ( $delimiters, $escapes ): returns $
    # from "Mastering Regular Expressions, 2e; p. 281" and modified from Text::Balanced::gen_delimited_pat($;$) [v1.95]
    # $DOUBLE = qr{"[^"\\]+(?:\\.[^"\\]+)+"};
    # $SINGLE = qr{'[^'\\]+(?:\\.[^'\\]+)+'};
    ## no critic (ControlStructures::ProhibitCStyleForLoops)
    my ($dels, $escs) = @_;
    return q{} unless $dels =~ /^\S+$/;     ## no critic (ProhibitPostfixControls)
    $escs = q{} unless $escs;               ## no critic (ProhibitPostfixControls)

    #print "dels = $dels\n";
    #print "escs = $escs\n";

    my @pat = ();
    for (my $i=0; $i<length $dels; $i++)
        {
            my $d = quotemeta substr($dels,$i,1);
            if ($escs)
                {
                for (my $j=0; $j < length $escs; $j++)
                    {
                    my $e = quotemeta substr($escs,$j,1);
                    if ($d eq $e)
                        {
                        push @pat, "$d(?:[^$d]*(?:(?:$d$d)[^$d]*)*)$d";
                        }
                    else
                        {
                        push @pat, "$d(?:[^$e$d]*(?:$e.[^$e$d]*)*)$d";
                        }
                    }
                }
            else { push @pat, "$d(?:[^$d]*)$d"; }
        }
    my $pat = join q{|}, @pat;

    return "(?:$pat)";
    }

sub _dequote{
    # _dequote( <null>|$|@ [,\%] ): returns <null>|$|@ ['shortcut' function] (with optional hash_ref containing function options)
    # trim balanced outer quotes
    # $opt{'surround_re'} = 'whitespace' surround which is removed  [default = '\s*']
    # $opt{'allowed_quotes_re'} = balanced 'quote' delimeters which are removed [default = q{['"]} ]

    my %opt = (
        surround_re         => '\s*',
        allowed_quotes_re   => '['.$_G{quote_meta}.']',
        _return_quote       =>  0,                          # true/false [ default = false ], if true, return quote as first character in returned array
        );

    my $me = (caller(0))[3];    ## no critic ( ProhibitMagicNumbers )   ## caller(EXPR) => ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller($i);
    my $opt_ref;
    $opt_ref = pop @_ if ( @_ && (ref($_[-1]) eq 'HASH'));  ## no critic (ProhibitPostfixControls)  ## pop last argument only if it's a HASH reference (assumed to be options for our function)
    if ($opt_ref) { for (keys %{$opt_ref}) { if (exists $opt{$_}) { $opt{$_} = $opt_ref->{$_}; } else { Carp::carp "Unknown option '$_' to for function ".$me; } } }

    my $w = $opt{surround_re};
    my $q = $opt{allowed_quotes_re};
    my $quoter = q{};

    @_ = @_ ? @_ : $_ if defined wantarray;     ## no critic (ProhibitPostfixControls)  ## break aliasing if non-void return context

    for (@_ ? @_ : $_)
        {
        s/^$w($q)(.*)\1$w$/$2/;
        if (defined($1)) { $quoter = $1; }
        #print "_ = $_\n";
        }

    if ( $opt{_return_quote} )
        {
        unshift @_, $quoter;
        #print "quoter = $quoter\n";
        #print "_ = @_\n";
        }

    return wantarray ? @_ : "@_";
    }

sub _zero_position_v1 {
    # _zero_position( $q_re, @args ): returns $
    # find and return the position of the current executable within the given argument array
    # $q_re = allowable quotation marks (possibly surrounding the executable name)
    # @args = the parsed argument array
    use English qw( -no_match_vars ) ;  # '-no_match_vars' avoids regex performance penalty

    my $q_re = shift @_;
    my @args = @_;

    my $pos;
    # find $0 in the ARGV array
    #print "0 = $0\n";
    #win32 - filenames are case-preserving but case-insensitive [so, solely case difference compares equal => convert to lowercase]
    my $zero = $PROGRAM_NAME;      ## no critic (Variables::ProhibitPunctuationVars)
    my $zero_lc = lc($zero);
    my $zero_dq = _dequote($zero_lc, { allowed_quotes_re => $q_re } );  # dequoted $0

    #print "zero = $zero\n";
    #print "zero_lc = $zero_lc\n";
    #print "zero_dq = $zero_dq\n";

#   while (my $arg = shift @a) {
    for ($pos=0; $pos<$#args; $pos++) {     ## no critic (ProhibitCStyleForLoops)
        my $arg = $args[$pos];
#    for my $arg (@a) {
        #print "arg = $arg\n";
        if ($zero_lc eq lc($arg))
            { # direct match
            #print "\tMATCH (direct)\n";
            last;
            }
        $arg =~ s/($q_re)(.*)\1/$2/;
        #print "arg = $arg\n";
        if ($zero_lc eq lc($arg))
            { # dequoted match
            #print "\tMATCH (dequoted)\n";
            last;
            }
        #print 'rel2abs(arg) = '.File::Spec->rel2abs($arg)."\n";
        # TODO: rethink file testing (-e is not sufficient as directories of same prefix may block resolution; but is -f or (-f & !-d) sufficient/correct? what about symbolic links/junctions, pipes, etc?
        # TODO: add tests to specify appropriate behaviour for colliding names
        if (-f $arg && (lc(File::Spec->rel2abs( $zero_dq )) eq lc(File::Spec->rel2abs( $arg ))))
            { # rel2abs match
            #print "\tMATCH (rel2abs)\n";
            last;
            }
        if (!-f $arg)
            { # find file on PATH with File::Which (needed for compiled perl executables)
            my ($fn, $r);
            my ($split_1, $split_2);
            ($split_1, $split_2, $fn) = File::Spec->splitpath( $arg );
            #print "split_1 = $split_1\n";
            #print "split_2 = $split_2\n";
            #print "fn = $fn\n";
            $r = File::Which::which($fn);
            if (defined $r) { $r = File::Spec->rel2abs( $r ); }
            #print $arg."\t\t=(find with which)> ".((defined $r) ? $r : "undef");
            if (lc($r) eq lc(File::Spec->rel2abs($zero)))
                {# which found
                #print "\tMATCH (via which)\n";
                last;
                }
            #else { print "\NO match (via which)\n"; }
            }
        #print "\n";
        }

    return $pos;
}

sub _argv_parse{
    # _argv( $ [,\%] ): returns @
    # parse scalar using bash-like rules for quotes and command/subshell block replacements (no globbing or environment variable substitutions are performed)
    # [\%]: an optional hash_ref containing function options as named parameters
    ## NOTE: once $(<...>) is implemented => need to parse "\n" as whitespace (use the /s argument for regexp) because there may be embedded newlines as whitespace
    ## TODO: formalize the grammar in documentation (very similar to bash shell grammer, except no $VAR interpretation, $(...) not interpreted within simple "..." (however, it is within $"..." => no further interpretation of $(...) output), quote removal within $(...) [to protect pipes]

    ## no critic ( ProhibitPunctuationVars ) # ToDO: remove/revisit

    my %opt = (
        _glob_within_qq => 0,       # = true/false [default = false]    # <private> if true, globbing within double quotes is performed, rather than only for "bare"/unquoted glob characters
        _carp_unbalanced => 1,      # = 0/true/'quotes'/'subshells' [default = true] # <private> if true, carp for unbalanced command line quotes or subshell blocks
        _die_subshell_error => 1,   # = true/false [default = true]     # <private> if true, die on any subshell call returning an error
        );

    # read/expand optional named parameters
    my $me = (caller(0))[3];    ## no critic ( ProhibitMagicNumbers )   ## caller(EXPR) => ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller($i);

    my $opt_ref;
    $opt_ref = pop @_ if ( @_ && (ref($_[-1]) eq 'HASH'));  # pop trailing argument only if it's a HASH reference (assumed to be options for our function)
    if ($opt_ref) { for (keys %{$opt_ref}) { if (defined $opt{$_}) { $opt{$_} = $opt_ref->{$_}; } else { Carp::carp "Unknown option '$_' supplied for function ".$me;   } } }

    my $command_line = shift @_;

    my @args; #@args = []ofhref{token=>'', chunks=>chunk_aref[]ofhref{chunk=>'',glob=>0,id=>''}, globs=>glob_aref[]}

    my $s = _ltrim($command_line, {trim_re => '(?s)[\s\n]+'});  # initial string to parse; prefix is whitespace trimmed     #???: need to change trim characters to include NL?
    my $glob_this_token = 1;

    # $s == string being parsed
    while ($s ne q{})
        {# $s is non-empty and starts with non-whitespace character
        Carp::Assert::assert( $s =~ /^\S/ );
        my $start_s1 = $s;
        my $t = q{};    # token (may be a partial/in-progess or full/finished token)
        my @argY;

        ##$s = _ltrim($s, {trim_re => '(?s)[\s\n]+'});      # ?needed
        $s = _ltrim($s);
        # get and concatenate chunks
        #print "1.s = `$s`\n";
        while ($s =~ /^\S/)
            {# $s has initial non-whitespace character
            # process and concat chunks until non-quoted whitespace is encountered
            # chunk types:
            #   NULL == 'null' (nothing but whitespace found)
            #   $( .* ) <subshell command, ends with 1st non-quoted )> == ['subshell_start', <any (balanced)>, 'subshell_end']
            #   ".*" <escapes ok> == 'double-quoted' [DOS escapes for \ and "]
            #   $".*" <escapes ok, with possible internal subshell commands> == '$double-quoted'
            #   $'.*' <ANSI C string, escapes ok> == '$single-quoted'
            #   '.*' <literal, no escapes> == 'single-quoted'
            #   \S+ == 'simple'
            my $start_s2 = $s;
            my $chunk;
            my $type;
            ($chunk, $s, $type) = _get_next_chunk( $s );

            #print "2.s = `$s`\n";
            #print "2.chunk = `$chunk`\n";
            #print "2.type = `$type`\n";

            if ($type eq 'subshell_start')
                {
                #print ":in subshell_start\n";
                # NOTE: UN-like BASH, the internal subshell command block may be quoted and will be interpreted with any external, balanced quotes (' or ") removed. This allows pipe and redirection characters within the subshell command block (eg, $("dir | sort")).
                my $in_subshell_n = 1;
                my $block = q{};
                my $block_chunk;
                ($block_chunk, $s, $type) = _get_next_chunk( $s );
                while ($in_subshell_n > 0)
                    {
                    #print "ss:block_chunk = `$block_chunk`\n";
                    #print "ss:type = `$type`\n";
                    #print "ss:s = `$s`\n";
                    if ($block_chunk eq q{}) { Carp::croak 'unbalanced subshell block [#1]'; }
                    elsif ($type eq 'subshell_start') { $in_subshell_n++; }
                    elsif ($type eq 'subshell_end') { $in_subshell_n--; }
                    else {
                        $block .= $block_chunk;
                        ($block_chunk, $s, $type) = _get_next_chunk( $s );
                        }
                    }
                $block = _dequote($block);
                #print "block = `$block`\n";
                my $output = `$block`;
                #print "output = `$output`\n";
                if ($opt{_die_subshell_error} and $?) { Carp::croak 'error '.q{'}.(($? > 0) ? $? >> 8 : $?).q{'}.' while executing subshell block `'.$block.q{`}; }     ## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
                $output =~ s/\n$//s; # remove any final NL (internal NLs and ending NLs > 1 are preserved, if present)
                $s = $output . $s; # graft to the front of $s for further interpretation
                _ltrim($s);
                #print "s = `$s`\n";
                }
            elsif ($type eq '$double-quoted')
                {
                #print ":in \$double-quoted\n";
                my $ss = _dequote(_ltrim($chunk, { trim_re => '\s+|\$' })); # trim whitespace and initial $ and then remove outer quotes
                #print "\$dq.1.ss = `$ss`\n";
                while ($ss ne q{})
                    {
                    # remove and concat any initial non-escaped/non-subshell portion of the string
                    # peel individual characters out...
                    my $sss = quotemeta q{$(};
                    while ($ss =~ /^($sss|\\[\\\"\$]|.)(.*)$/)      #"
                        {
                        my $o = $1;
                        $ss = $2;
                        if (length($o) > 1)
                            {
                            if (substr($o, 0, 1) eq q{\\}) { $o = substr($o, 1, 1); }
                            else
                                {# subshell_start
                                #print "\$double-quote: in subshell consumer\n";
                                #print "\$dq.sss.ss = `$ss`\n";
                                # NOTE: UNlike BASH, the internal subshell command block may be quoted and will be interpreted with any external, balanced quotes (' or ") removed. This allows pipe and redirection characters within the subshell command block (eg, $("dir | sort")).
                                my $in_subshell_n = 1;
                                my $block = q{};
                                my $block_chunk;
                                ($block_chunk, $ss, $type) = _get_next_chunk( $ss );
                                while ($in_subshell_n > 0)
                                    {
                                    #print "ssc:block_chunk = `$block_chunk`\n";
                                    #print "ssc:type = `$type`\n";
                                    #print "ssc:ss = `$ss`\n";
                                    if ($block_chunk eq q{}) { Carp::croak 'unbalanced subshell block [#2]'; }
                                    elsif ($type eq 'subshell_start') { $in_subshell_n++; }
                                    elsif ($type eq 'subshell_end') { $in_subshell_n--; }
                                    else {
                                        $block .= $block_chunk;
                                        ($block_chunk, $ss, $type) = _get_next_chunk( $ss );
                                        }
                                    }
                                $block = _dequote($block);
                                #print "dq.block = `$block`\n";
                                my $output = `$block`;
                                #print "dq.output = `$output`\n";
                                if ($opt{_die_subshell_error} and $?) { Carp::croak 'error '.q{'}.(($? > 0) ? $? >> 8 : $?).q{'}.' while executing subshell block `'.$block.q{`}; }     ## no critic ( ProhibitMagicNumbers ) # ToDO: revisit/remove
                                $output =~ s/\n$//s; # remove any final NL (internal NLs and ending NLs > 1 are preserved, if present)
                                $o = $output;   # output as single token ## do this within $"..."
                                }
                            }
                        #$t .= $o;
                        push @argY, { token => $o, glob => 0, id => "[$type]" };
                        $t .= $argY[-1]->{token};
                        #push @{ $argX[ $i ] }, { token => _dequote($o), glob => $opt{_glob_within_qq}, id => 'complex:re_qq_escok_dollar' };
                        #print "\$dq.dq.0.t = `$t`\n";
                        #print "\$dq.dq.0.ss = `$ss`\n";
                        }
                    }
                }
            elsif ($type eq 'double-quoted')
                {
                #print ":in double-quoted\n";
                #$t .= _dequote(_decode_dosqq(_ltrim($chunk)));
                push @argY, { token => _dequote(_decode_dosqq(_ltrim($chunk))), glob => $opt{_glob_within_qq}, id => "[$type]" };
                $t .= $argY[-1]->{token};
                #print "token = `$argY[-1]->{token}`\n";
                }
            elsif ($type eq '$single-quoted')
                {
                #print ":in \$single-quoted\n";
                # trim whitespace and initial $, decode, and then remove outer quotes
                push @argY, { token => _dequote(_decode(_ltrim($chunk, { trim_re => '\s+|\$' }))), glob => 0, id => "[$type]" };
                $t .= $argY[-1]->{token};
                }
            elsif ($type eq 'single-quoted')
                {
                #print ":in single-quoted\n";
                #$t .= _dequote(_ltrim($chunk));
                push @argY, { token => _dequote(_ltrim($chunk)), glob => 0, id => "[$type]" };
                $t .= $argY[-1]->{token};
                }
            else ## default to ($type eq 'simple') [also assumes the 'null' case which should be impossible]
                {
                #print ":in default[$type]\n";
                push @argY, { token => _ltrim($chunk), glob => 1, id => '[default]:'.$type };
                my $token = $argY[-1]->{token};
                #print "token = $token\n";
                $t .= $token;
#               if (($token =~ /^[\'\"]/) and $opt{_carp_unbalanced}) { Carp::croak 'Unbalanced command line quotes [#1] (at token`'.$token.'` from command line `'.$command_line.'`)'; }   #"
                if ($token =~ /^[\'\"]/) { Carp::croak 'Unbalanced command line quotes [#1] (at token`'.$token.'` from command line `'.$command_line.'`)'; }    #"
                Carp::Assert::assert( $type ne 'null', 'Found a null chunk in $s (should be impossible with $s =~ /^\S/)' );
                }
            Carp::Assert::assert( $start_s2 ne $s, 'Parsing is proceeding ($s is being consumed)' );
            }
        #print "t = `$t`\n";
        push @args, { token => $t, chunks => \@argY };
        _ltrim($s);
        ##_ltrim($s, {trim_re => '(?s)[\s]+'});     ## ?needed for multi-NL command lines?
        #print "[end (\$s ne '')] s = `$s`\n";
        Carp::Assert::assert( $start_s1 ne $s, 'Parsing is not proceeding ($s is unchanged)' );
        }
    #print "-- _argv_parse [RETURNING]\n";
    #print "args[".scalar(@args)."] => `@args`\n";
    #print "args[".scalar(@args)."]\n";
    #push @{    $argX[ $i ] }, { token => _dequote($o), glob => $opt{_glob_within_qq}, id => 'complex:re_qq_escok_dollar' };
    #print "argX[".scalar(@argX)."]\n";
#   for (@argX) { #print "token = ".$_->{token}."; glob = ".$_->{glob}."; id = ".$_->{id}."\n"; }
#   foreach (@argX) { #print "token = ".$_->{token}."; glob = ".$_->{glob}."; id = ".$_->{id}."\n"; }
#   for my $a (@argX) { for my $aa (@{$a}) {print "token = $a->[0]->{token}; glob = $a->[0]->{glob}; id = $a->[0]->{id}; \n"; } }
    #for my $arg (@args) { #print "token = $arg->{token};\n"; for my $chunk (@{$arg->{chunks}}) { #print "::chunk = $chunk->{token}; glob = $chunk->{glob}; id = $chunk->{id}; \n"; } }

    #print "$me:exiting\n"; for (my $pos=0; $pos<=$#args; $pos++) { #print "args[$pos]->{token} = `$args[$pos]->{token}`\n"; }

    return @args;
}

sub _get_next_chunk{
    # _get_next_chunk( $ ): returns ( $chunk, $suffix, $type )
    # parse next chunk of text returning the $chunk removed, the $suffix remaining, and the $type of chunk returned
    # chunks are raw (unprocessed) with whatever leading whitespace might be present in $
    my $s = shift @_;

    my ($ret_chunk, $ret_type) = (q{}, 'null');

    my $sq = $_G{single_q};         # single quote (')
    my $dq = $_G{double_q};         # double quote (")
    my $quotes = $sq.$dq;           # quote chars ('")
    my $q_qm = quotemeta $quotes;
    my $q_re = '['.quotemeta $quotes.']';

    my $g_re = '['.quotemeta $_G{glob_char}.']';    # glob signal characters

    my $escape = $_G{escape_char};

    my $_unbalanced_command_line = 0;

    my $re_q_escok = _gen_delimeted_regexp( $sq, $escape );     # regexp for single quoted string with internal escaped characters allowed
    my $re_qq_escok = _gen_delimeted_regexp( $dq, $escape );    # regexp for double quoted string with internal escaped characters allowed
    my $re_q    = _gen_delimeted_regexp( $sq );                 # regexp for single quoted string (no internal escaped characters)
    my $re_qq   = _gen_delimeted_regexp( $dq );                 # regexp for double quoted string (no internal escaped characters)
    my $re_qqq  = _gen_delimeted_regexp( $quotes );             # regexp for any-quoted string (no internal escaped characters)


    # chunk types:
    #   NULL == 'null' (nothing but whitespace found)
    #   $( .* ) <subshell command, ends with non-quoted )> == ['subshell_start', <any (balanced)>, 'subshell_end']
    #   ".*" <escapes ok> == 'double-quoted', $".*" <escapes ok> == '$double-quoted'
    #   $'.*' <ANSI C string, escapes ok> == '$single-quoted'
    #   '.*' <literal, no escapes> == 'single-quoted'
    #   \S+ == 'simple'

    $ret_type = 'null';     # default == 'null' type
    $ret_chunk = q{};

    #print "gc.1.s = `$s`\n";
    if ($s =~ /^(\s+)(.*)/s)
        {# remove leading whitespace
        #print "ws.1    = `$1`\n" if $1;
        #print "ws.2    = `$2`\n" if $2;
        $ret_type = 'null';     # 'null' type so far
        $ret_chunk = $1;
        $s = defined($2) ? $2 : q{};
        }
    #print "gc.2.s = `$s`\n";
    if ($s ne q{})
        {
        if ($s =~ /^(\$[(])(.*)$/s)
            {# subshell_start == unquoted '$(' characters
            # $1 = subshell block starting token
            # $2 = rest of string [if exists]
            #print "sss.1   = `$1`\n" if $1;
            #print "sss.2   = `$2`\n" if $2;
            $ret_type = 'subshell_start';
            $ret_chunk .= $1;
            $s = defined($2) ? $2 : q{};
            }
        elsif ($s =~ /^([)])(.*)$/s)
            {# subshell_end == unquoted ')' character
            # $1 = subshell block ending token
            # $2 = rest of string [if exists]
            #print "sse.1   = `$1`\n" if $1;
            #print "sse.2   = `$2`\n" if $2;
            $ret_type = 'subshell_end';
            $ret_chunk .= $1;
            $s = defined($2) ? $2 : q{};
            }
        elsif ($s =~ /^((\$)?$re_qq_escok)(.*)$/s)
            {# double-quoted or $double-quoted chunk (possible internal escapes)
            # $1 = leading $ (if present)
            # $2 = double-quoted chunk
            # $3 = rest of string [if exists]
            $ret_type = 'double-quoted';
            if (defined($2)) { $ret_type = $2.$ret_type; };
            $ret_chunk .= $1;
            $s = defined($3) ? $3 : q{};
            #print "dq.1    = `$1`\n" if $1;
            #print "dq.2    = `$2`\n" if $2;
            #print "dq.3    = `$3`\n" if $3;
            #print "dq.s    = `$s`\n";
            }
        elsif ($s =~ /^(\$$re_q_escok)(.*)$/s)
            {# $single-quoted chunk (possible internal escapes)
            # $1 = $single-quoted chunk
            # $2 = rest of string [if exists]
            #print "\$sq.1  = `$1`\n" if $1;
            #print "\$sq.2  = `$2`\n" if $2;
            $ret_type = '$single-quoted';
            $ret_chunk .= $1;
            $s = defined($2) ? $2 : q{};
            }
        elsif ($s =~ /^($re_q)(.*)$/s)
            {# single-quoted chunk (no internal escapes)
            # $1 = single-quoted token
            # $2 = rest of string [if exists]
            #print "sq.1    = `$1`\n" if $1;
            #print "sq.2    = `$2`\n" if $2;
            $ret_type = 'single-quoted';
            $ret_chunk .= $1;
            $s = defined($2) ? $2 : q{};
            }
        elsif ($s =~ /^([$q_qm].*)$/s)
            {# quoted chunk unmatched above (unbalanced)
            # $1 = quoted token
            #print "ub.1    = `$1`\n" if $1;
            $ret_type = 'unbalanced-quoted';
            $ret_chunk .= $1;
            $s = q{};
            }
        else
            {# simple non-whitespace character chunk  ##default
            ## n#o critic ( ProhibitDeepNests )
            Carp::Assert::assert( $s =~ /^\S/ );
            #print "s = $s\n";
            $ret_type = 'simple';
            if ($s =~ /^([^\s$q_qm\$()]+)(.*)$/s)
                {
                # $1 = non-whitespace/non-quoted/non-subshell_start/non-subshell_end token
                # $2 = rest of string [if exists]
                #print "simple.1    = `$1`\n" if defined($1);
                #print "simple.2    = `$2`\n" if defined($2);
                $ret_chunk .= defined($1) ? $1 : q{};
                $s = defined($2) ? $2 : q{};
                }
            else
                {# cover the case for isolated $
                ## no critic ( ProhibitCaptureWithoutTest )     ## ToDO: revisit / reanalyze & remove
                $s =~ /^(\S)(.*)$/s;
                # $1 = non-whitespace character
                # $2 = rest of string [if exists]
                #Carp::Assert::assert( defined $1 );
                $ret_chunk .= defined($1) ? $1 : q{};
                $s = defined($2) ? $2 : q{};
                }
            }
        }

    return ( $ret_chunk, $s, $ret_type );
}

sub _argv_do_glob{
    # _argv_do_glob( @args ): returns @
    ## @args = []of{token=>'', chunks=>chunk_aref[]of{chunk=>'',glob=>0,id=>''}, globs=>glob_aref[]}

    ## no critic ( ProhibitUnusualDelimiters ) # ToDO: remove/revisit

    my %opt = (
        dosquote => 0,              # = 0/<true>/'all' [default = 0]    # if true, convert all non-globbed ARGS to DOS/Win32 CLI compatible tokens (escaping internal quotes and quoting whitespace and special characters)
        dosify => 0,                # = 0/<true>/'all' [default = 0]    # if true, convert all globbed ARGS to DOS/Win32 CLI compatible tokens (escaping internal quotes and quoting whitespace and special characters); 'all' => do so for for all ARGS which are determined to be files
        unixify => 0,               # = 0/<true>/'all' [default = 0]    # if true, convert all globbed ARGS to UNIX path style; 'all' => do so for for all ARGS which are determined to be files
        glob => 1,      ## REMOVE this??
        nullglob => defined($ENV{nullglob}) ? $ENV{nullglob} : 0,       # = 0/<true> [default = 0]  # if true, patterns which match no files are expanded to a null string (no token), rather than the pattern itself  ## $ENV{nullglob} (if it exists) overrides the default
        );

    # read/expand optional named parameters
    my $me = (caller(0))[3];    ## no critic ( ProhibitMagicNumbers )   ## caller(EXPR) => ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller($i);

    my $opt_ref;
    $opt_ref = pop @_ if ( @_ && (ref($_[-1]) eq 'HASH'));  # pop trailing argument only if it's a HASH reference (assumed to be options for our function)
    if ($opt_ref) { for (keys %{$opt_ref}) { if (defined $opt{$_}) { $opt{$_} = $opt_ref->{$_}; } else { Carp::carp "Unknown option '$_' supplied for function ".$me;   } } }

    my @args = @_;
    my $glob_this;

    my %home_paths = _home_paths();
    # if <username> is duplicated in environment vars, it overrides any previous path found in the registry
    for my $k (keys %ENV)
        {
        if ( $k =~ /^~(\w+)$/ )
            {
            my $username = $1;
            $ENV{$k} =~ /\s*"?\s*(.*)\s*"?\s*/;
            if (defined $1) { $home_paths{lc($username)} = $1; }
                else { $home_paths{lc($username)} = $ENV{$k}; }
            }
        }
    for my $k (keys %home_paths) { $home_paths{$k} =~ s/\\/\//g; }; # unixify path seperators
    my $home_path_re =  q{(?i)}.q{^~(}.join(q{|}, keys %home_paths ).q{)?(/|$)}; ## no critic (RequireInterpolationOfMetachars)

    use File::Glob qw( :glob );
    my $s = q{};
    for (my $i=0; $i<=$#args; $i++)     ## no critic (ProhibitCStyleForLoops)
        {
        my @g = ();
        #print "args[$i] = $args[$i]->{token}\n";
        my $pat;

        $pat = q{};
        $s = q{};
        $glob_this = 0;
        # must meta-quote to allow glob metacharacters to correctly match within quotes
        foreach my $chunk ( @{ $args[$i]->{chunks} } )
            {
            my $t = $chunk->{token};
            $s .= $t;
            if ($chunk->{glob})
                {
                $glob_this = 1;
                $t =~ s/\\/\//g;
                #print "s = $s\n";
                #print "t = $t\n";
                }
            else
                { $t = _quote_gc_meta($t); }
            $pat .= $t;
            }
        # NOT!: bash-like globbing EXCEPT no backslash quoting within the glob; this makes "\\" => "\\" instead of "\" so that "\\machine\dir" works
        # DONE/instead: backslashes have already been replaced with forward slashes (by _quote_gc_meta())
        # must do the slash changes for user expectations ( "\\machine\dir\"* should work as expected on Win32 machines )
        # TODO: note differences this causes between bash and Win32::CommandLine::argv() globbing
        # TODO: note in LIMITATIONS section

        # DONE=>TODO: add 'dosify' option => backslashes for path dividers and quoted special characters (with escaped [\"] quotes) and whitespace within the ARGs
        # TODO: TEST 'dosify' and 'unixify'

        my $glob_flags = GLOB_NOCASE | GLOB_ALPHASORT | GLOB_BRACE | GLOB_QUOTE;

        if ( $opt{nullglob} )
            {
            $glob_flags |= GLOB_NOMAGIC;
            }
        else
            {
            $glob_flags |= GLOB_NOCHECK;
            }

        if ( $opt{glob} && $glob_this )
            {
            $pat =~ s:\\\\:\/:g;        ## no critic ( ProhibitUnusualDelimiters )  ## replace all backslashes (assumed to be backslash quoted already) with forward slashes

            if ($pat =~ m/$home_path_re/)
                {# deal with possible prefixes
                # TODO: NOTE: this allows quoted <usernames> which is different from bash, but needed because Win32 <username>'s can have internal whitespace
                # TODO: CHECK: are there any cases where the $s wouldn't match but $pat would causing incorrect fallback string?
                #print "pat(pre-prefix)  = `$pat`\n";
                #print "s(pre-prefix)    = `$s`\n";
                $pat =~ s/$home_path_re/$home_paths{lc($1)}$2/;
                $s =~ s:\\:\/:g;                                # unixify $s for processing
                $s =~ s/$home_path_re/$home_paths{lc($1)}$2/;   # need to change fallback string $s as well in case the final pattern doesn't expand with bsd_glob()
                }

            if ( $pat =~ /\\[?*]/ )
                { ## '?' and '*' are not allowed in filenames in Win32, and Win32 DosISH globbing doesn't correctly escape them when backslash quoted, so skip globbing for any tokens containing these characters
                #print "pat contains escaped wildcard characters ($pat)\n";
                @g = ( $s );
                }
            else
                {
                #print "bsd_glob of `$pat`\n";
                @g = bsd_glob( $pat, $glob_flags );
                #print "s = $s\n";
                if ((scalar(@g) == 1) && ($g[0] eq $pat)) { @g = ( $s ); }
                if ($opt{dosify}) { foreach (@g) { _dosify($_); }}
                elsif ($opt{unixify}) { foreach (@g) { $_ =~ s:\\:\/:g; }}
                }
            }
        else
            {
            @g = ( $s );
            # TODO: CHECK this and think about correct function names... (both here and in successful glob function above)
            # TODO: CHECK unixify ... does it need the  "if (-e $_)" gate similar to dosify?
            if ($opt{dosify} eq 'all') { foreach (@g) { if (-e $_) { _dosify($_); }}}
            elsif ($opt{dosquote}) { foreach (@g) { _dos_quote($_); }}
            elsif ($opt{unixify} eq 'all') { foreach (@g) { $_ =~ s:\\:\/:g; }}
            }
        #print "glob_this = $glob_this\n";
        #print "s   = `$s`\n";
        #print "pat = `$pat`\n";
        #print "\@g = { @g }\n";

        #BUGFIX: do this only for successful globs... MOVED into glob loop above [FIXES: xx -e perl -e "$x = split( /n/, q{Win32::CommandLine}); print $x;" => perl -e "$x = split( \n\, q{Win32::CommandLine}); print $x;" ]
        ## if whitespace or special characters, surround with double-quotes ((::whole token:: or just individual problem characters??))
        #if ($opt{dosify})
        #   {
        #   foreach (@g) { _dosify($_); }
        #   };

        $args[$i]->{globs} = \@g;
        }

    #print "$me:exiting\n"; for (my $pos=0; $pos<=$#args; $pos++) { #print "args[$pos]->{token} = `$args[$pos]->{token}`\n"; }

    return @args;
}

sub _zero_position{
    # _zero_position( @args, \% ): returns $
    # find and return the position of the current executable within the given argument array
    # @args = the parsed argument array     ## @args = []of{token=>'', chunks=>chunk_aref[]of{chunk=>'',glob=>0,id=>''}, globs=>glob_aref[]}
    ## no critic ( ProhibitEscapedCharacters ) # ToDO: remove/revisit
    my %opt = (
        q{}=>q{},                       # placeholder to allow {''=><x>} as a named optional parameter group because the function takes complex parameters which will be seen as a HASHREF
        quote_re => qq{[\x22\x27]},     # = <regexp> [default = single/double quotes]   ## allowable quotation marks (possibly surrounding the executable name)
        );

    # read/expand optional named parameters
    my $me = (caller(0))[3];    ## no critic ( ProhibitMagicNumbers )   ## caller(EXPR) => ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller($i);

    my $opt_ref;
    $opt_ref = pop @_ if ( @_ && (ref($_[-1]) eq 'HASH'));  # pop trailing argument only if it's a HASH reference (assumed to be options for our function)
    if ($opt_ref) { for (keys %{$opt_ref}) { if (defined $opt{$_}) { $opt{$_} = $opt_ref->{$_}; } else { Carp::carp "Unknown option '$_' supplied for function ".$me;   } } }

    use English qw( -no_match_vars ) ;  # '-no_match_vars' avoids regex performance penalty

    my $q_re = $opt{quote_re};
    my @args = @_;

    my $pos;
    # find $0 in the ARGV array
    #print "0 = $0\n";
    #win32 - filenames are case-preserving but case-insensitive [so, solely case difference compares equal => convert to lowercase]
    # TODO: for use in C# programs under PerlScript => if $PROGRAM_NAME eq q{}, assume 0 position is correct (any other ramifications?)
    my $zero = $PROGRAM_NAME;      ## no critic (Variables::ProhibitPunctuationVars)
    my $zero_lc = lc($zero);
    my $zero_dq = _dequote($zero_lc, { allowed_quotes_re => $opt{quote_re} } );  # dequoted $0

    #print "zero = $zero\n";
    #print "zero_lc = $zero_lc\n";
    #print "zero_dq = $zero_dq\n";

    if ($zero eq q{}) { return 0 }; # if $0/$zero eq q{} then the script may be running under some scripting harness, assume the 1st arg is the command name and return (allows use in C# under MSScriptControl.ScriptControlClass harness)

    #print '#args = '.@args."\n";
    #print "$me:starting search\n"; for (my $pos=0; $pos<=$#args; $pos++) { print "args[$pos]->{token} = `$args[$pos]->{token}`\n"; }
#   while (my $arg = shift @a) {
    for ($pos=0; $pos<=$#args; $pos++) {        ## no critic (ProhibitCStyleForLoops)
        my $arg = $args[$pos]->{token};
#    for my $arg (@a) {
        #print "pos = $pos\n";
        #print "arg = $arg\n";
        if ($zero_lc eq lc($arg))
            { # direct match
            #print "\tMATCH (direct)\n";
            last;
            }
        $arg =~ s/($q_re)(.*)\1/$2/;
        #print "arg = $arg\n";
        if ($zero_lc eq lc($arg))
            { # dequoted match
            #print "\tMATCH (dequoted)\n";
            last;
            }
        #print 'rel2abs(arg) = '.File::Spec->rel2abs($arg)."\n";
        # TODO: rethink file testing (-e is not sufficient as directories of same prefix may block resolution; but is -f or (-f & !-d) sufficient/correct? what about symbolic links/junctions, pipes, etc?
        # TODO: add tests to specify appropriate behaviour for colliding names
        if (-f $arg && (lc(File::Spec->rel2abs( $zero_dq )) eq lc(File::Spec->rel2abs( $arg ))))
            { # rel2abs match
            #print "\tMATCH (rel2abs)";
            last;
            }
        if (!-f $arg)
            { # find file on PATH with File::Which (needed for compiled perl executables)
            my ($fn, $r);
            my ($split_1, $split_2);
            ($split_1, $split_2, $fn) = File::Spec->splitpath( $arg );
            #print "split_1 = $split_1\n";
            #print "split_2 = $split_2\n";
            #print "fn = $fn\n";
            $r = File::Which::which($fn);
            if (defined $r) { $r = File::Spec->rel2abs( $r ); }
            #print $arg."\t\t=(find with which)> ".((defined $r) ? $r : "undef");
            if ($r && (lc($r) eq lc(File::Spec->rel2abs($zero))) )
                {# which found
                #print "\tMATCH (using which)";
                last;
                }
            #else { print "\tNO match (using which())"; }
            }
        #print "\n";
        }

    return $pos;
}

sub _argv{
    # _argv( $ [,\%] ): returns @
    # parse scalar as a command line string (bash-like parsing of quoted strings with globbing of resultant tokens, but no other expansions or substitutions are performed)
    # [\%]: an optional hash_ref containing function options as named parameters
    my %opt = (
        remove_exe_prefix => 1,     # = 0/<true> [default = true]       # if true, remove all initial args up to and including the exe name from the @args array
        dosquote => 0,              # = 0/<true>/'all' [default = 0]    # if true, convert all non-globbed ARGS to DOS/Win32 CLI compatible tokens (escaping internal quotes and quoting whitespace and special characters)
        dosify => 0,                # = 0/<true>/'all' [default = 0]    # if true, convert all _globbed_ ARGS to DOS/Win32 CLI compatible tokens (escaping internal quotes and quoting whitespace and special characters); 'all' => do so for for _all_ ARGS which are determined to be files
        unixify => 0,               # = 0/<true>/'all' [default = 0]    # if true, convert all _globbed_ ARGS to UNIX path style; 'all' => do so for for _all_ ARGS which are determined to be files
        nullglob => defined($ENV{nullglob}) ? $ENV{nullglob} : 0,       # = 0/<true> [default = 0]  # if true, patterns which match no files are expanded to a null string (no token), rather than the pattern itself  ## $ENV{nullglob} (if it exists) overrides the default
        glob => 1,                  # = 0/<true> [default = true]       # when true, globbing is performed
        ## TODO: rework this ... need carp/croak on unbalanced quotes/subshells (? carp_ub_quotes, carp_ub_shells, carp = 0/1/warn/carp/die/croak)
        croak_unbalanced => 1,      # = 0/true/'quotes'/'subshells' [default = true] # if true, croak for unbalanced command line quotes or subshell blocks (takes precedence over carp_unbalanced)
        carp_unbalanced => 1,       # = 0/true/'quotes'/'subshells' [default = true] # if true, carp for unbalanced command line quotes or subshell blocks
        _glob_within_qq => 0,       # = true/false [default = false]    # <private> if true, globbing within double quotes is performed, rather than only for "bare"/unquoted glob characters
        _die_subshell_error => 1,   # = true/false [default = true]     # <private> if true, die on any subshell call returning an error
        );

    # read/expand optional named parameters
    my $me = (caller(0))[3];    ## no critic ( ProhibitMagicNumbers )   ## caller(EXPR) => ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller($i);

    my $opt_ref;
    $opt_ref = pop @_ if ( @_ && (ref($_[-1]) eq 'HASH'));  # pop trailing argument only if it's a HASH reference (assumed to be options for our function)
    if ($opt_ref) { for (keys %{$opt_ref}) { if (defined $opt{$_}) { $opt{$_} = $opt_ref->{$_}; } else { Carp::carp "Unknown option '$_' supplied for function ".$me;   } } }

    my $command_line = shift @_;

    #print "$me: command_line = $command_line\n";

    # parse tokens from the $command_line string
    my @args = _argv_parse( $command_line, { _glob_within_qq => $opt{_glob_within_qq}, _carp_unbalanced => $opt{_carp_unbalanced}, _die_subshell_error => $opt{_die_subshell_error} } );
    #@args = []of{token=>'', chunks=>chunk_aref[]of{chunk=>'',glob=>0,id=>''}, globs=>glob_aref[]}

    #print "$me:pre-remove_exe_prefix\n"; for (my $pos=0; $pos<=$#args; $pos++) { print "args[$pos]->{token} = `$args[$pos]->{token}`\n"; }

    if ($opt{remove_exe_prefix})
        {# remove $0    (and any prior entries) from ARGV array (and the matching glob_ok signal array)
        #my $p = _zero_position( @args, {} );
        my $p = _zero_position( @args, {q{}=>q{}} );
        #print "p = $p\n";
        #print "$me:pre-removing\n"; for (my $pos=0; $pos<=$#args; $pos++) { #print "args[$pos]->{token} = `$args[$pos]->{token}`\n"; }
        @args = @args[$p+1..$#args];
        #print "$me:pre-removing\n"; for (my $pos=0; $pos<=$#args; $pos++) { #print "args[$pos]->{token} = `$args[$pos]->{token}`\n"; }
        }

    #print "$me:post-remove_exe_prefix\n"; for (my $pos=0; $pos<=$#args; $pos++) { print "args[$pos]->{token} = `$args[$pos]->{token}`\n"; }

    if ($opt{glob})
        {# do globbing
        #print 'globbing'.qq{\n};
        @args = _argv_do_glob( @args, { dosify => $opt{dosify}, dosquote => $opt{dosquote}, nullglob => $opt{nullglob} } );
        }
    else
        {# copy tokens to 'glob' position (for output later)
        #TODO: testing
        #print 'NO globbing'.qq{\n};
        for my $arg (@args) { $arg->{globs} = [ $arg->{token} ]; }
        }

    ## TODO: TEST -- NOW DONE in _argv_do_glob()
    #if ($opt{dosify} eq 'all')
    #   {
    #   foreach my $arg (@args) { for my $glob (@{$arg->{globs}}) { if (-e $glob) { _dosify($glob); }}}
    #   }
    #if ($opt{unixify} eq 'all')
    #   {
    #   foreach my $arg (@args) { for my $glob (@{$arg->{globs}}) { if (-e $glob) { $glob =~ s:\\:\/:g; }}}
    #   }

    ## TODO: CHECK this and think about correct function names... -- NOW DONE in _argv_do_glob()
    #if ($opt{dosquote})
    #   {
    #   foreach (@g) { _dos_quote($_); }
    #   };


    my @g;
    #print "$me:gather globs\n"; for (my $pos=0; $pos<=$#args; $pos++) { print "args[$pos]->{token} = `$args[$pos]->{token}`\n"; print "args[$pos]->{globs} = `$args[$pos]->{globs}`\n"; my @globs = $args[$pos]->{globs}; for (my $xpos=0; $xpos<$#globs; $xpos++) { print "globs[$pos] = `$globs[$pos]`\n"; } }
    for my $arg (@args)
        {
        my @globs = @{$arg->{globs}};
        for (@globs) { push @g, $_; }
        }

    #@g = ('this', 'that', 'the other');
    #print "$me:exiting\n"; for (my $pos=0; $pos<=$#args; $pos++) { print "g[$pos] = `$g[$pos]`\n"; }

    return @g;
}

sub _quote_gc_meta{
    my $s = shift @_;
#   my $gc = $_G{glob_char};

    my $gc = quotemeta( q{?*[]{}~}.q{\\} );
#   my $dgc = quotemeta ( '?*' );

#   $s =~ s/\\/\//g;                        # replace all backslashes with forward slashes
#   $s =~ s/([$gc])/\\$1/g;                 # backslash quote all metacharacters (note: there should be no backslashes to quote)

#   $s =~ s/([$gc])/\\$1/g;                 # backslash quote all metacharacters (backslashes are ignored)
    $s =~ s/([$gc])/\\$1/g;                 # backslash quote all glob metacharacters (backslashes as well)

#   $s =~ s/([$dgc])/\\\\\\\\\\$1/g;        # see Dos::Glob notes for literally quoting '*' or '?'  ## doesn't work for Win32 (? only MacOS)

    return $s;
}

sub _argv_v1{   ## no critic ( Subroutines::ProhibitExcessComplexity )
    # _argv( $command_line )

    # [separated from argv() for testing]
    # '...'     => literal (no escapes and no globbing within quotes)
    # $'...'    => ANSI C string escapes (\a, \b, \e, \f, \n, \r, \t, \v, \\, \', \n{1,3}, \xh{1,2}, \cx; all other \<x> =>\<x>), no globbing within quotes
    ##NOT# "..." => literal (no escapes but allows internal globbing) [differs from bash]
    # "..."   => literal (no escapes and no globbing within quotes)
    # DONE[2009-02-18]:TODO: "..."    => literal (no escapes [EXCEPT \" and \\] and no globbing within quotes) [works the same in bash and needed for cmd.exe compatibility]
    # $"..."  => same as "..."
    # globbing is only done for non-quoted glob characters

    # TODO: add $(<COMMAND>) intepretation, inserting the resultant STDOUT output into the command line in place of the $(<COMMAND>) with trailing NEWLINE removed (internal NEWLINEs are preserved)
    #   $(<COMMAND>) => defined as opening '$(' (no whitespace) followed by <COMMAND> = everything up to the next unquoted ')' character
    #   NOTE: at this point [2009-02-17], no redirection is allowed as the shell grabs the line and redirects before allowing interpretation which would break the command line internal to the $()
    #           ?? can we somehow meta-quote the string to protect and then allow redirection??
    #   ?? what about errors? how to propogate?

    # DONE[]:TODO:  Change semantics so that "..." has no internal globbing (? unless has at least one non-quoted glob character, vs what to do with combination quoted and non-quoted glob characters)
    #       only glob bare (non-quoted) characters

    # _argv( $ [,\%] ): returns @
    # parse scalar as a command line string (bash-like parsing of quoted strings with globbing of resultant tokens, but no other expansions or substitutions are performed)
    # [%]: an optional hash_ref containing function options as named parameters

    # ???: distinction between cmd.exe argument quoting and 'dosify' == change to forward slash path dividers; 'unixify' == just backslash dividers or quote as well?
    # ???: cmdify, bashify, or quote => 0/cmd/bash to use as separate from path divider changes
    my %opt = (
        dosify => 0,                # = 0/<true>/'all' [default = 0]    # if true, convert all globbed ARGS to DOS/Win32 CLI compatible tokens (escaping internal quotes and quoting whitespace and special characters); 'all' => do so for for all ARGS which are determined to be files
        unixify => 0,               # = 0/<true>/'all' [default = 0]    # if true, convert all globbed ARGS to UNIX path style; 'all' => do so for for all ARGS which are determined to be files
        nullglob => defined($ENV{nullglob}) ? $ENV{nullglob} : 0,       # = 0/<true> [default = 0]  # if true, patterns which match no files are expanded to a null string (no token), rather than  the pattern itself  ## $ENV{nullglob} (if it exists) overrides the default
        glob => 1,                  # = 0/<true> [default = true]       # when true, globbing is performed
        _glob_within_qq => 0,       # = true/false [default = false]    # <private> if true, globbing within double quotes is performed, rather than only for "bare"/unquoted glob characters
        _carp_unbalanced => 1,      # = true/false [default = true]     # <private> if true, carp for unbalanced command line quotes
        );

    # read/expand optional named parameters
    my $me = (caller(0))[3];    ## no critic ( ProhibitMagicNumbers )   ## caller(EXPR) => ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller($i);

    my $opt_ref;
    $opt_ref = pop @_ if ( @_ && (ref($_[-1]) eq 'HASH'));  # pop trailing argument only if it's a HASH reference (assumed to be options for our function)
    if ($opt_ref) { for (keys %{$opt_ref}) { if (defined $opt{$_}) { $opt{$_} = $opt_ref->{$_}; } else { Carp::carp "Unknown option '$_' supplied for function ".$me; } } }

    my @argv2;                  # [] of tokens
    my @argv2_globok;           # glob signal per argv2 entry

    my @argv_3;                 # [] of [](token => <token_portion>, glob => glob_this)

    my $sq = $_G{single_q};         # single quote (')
    my $dq = $_G{double_q};         # double quote (")
    my $quotes = $sq.$dq;           # quote chars ('")
    my $q_qm = quotemeta $quotes;

    my $gc = quotemeta ( $_G{glob_char} );  #   glob signal characters

    my $escape = $_G{escape_char};

    my $_unbalanced_command_line = 0;

    my $re_q_escok = _gen_delimeted_regexp( $sq, $escape );     # regexp for single quoted string with internal escaped characters allowed
    my $re_qq_escok = _gen_delimeted_regexp( $dq, $escape );    # regexp for double quoted string with internal escaped characters allowed
    my $re_q    = _gen_delimeted_regexp( $sq );                 # regexp for single quoted string (no internal escaped characters)
    my $re_qq   = _gen_delimeted_regexp( $dq );                 # regexp for double quoted string (no internal escaped characters)
    my $re_qqq  = _gen_delimeted_regexp($quotes);               # regexp for any-quoted string (no internal escaped characters)

    #print "re_esc = $re_q_escok\n";
    #print "re_qq = $re_qq\n";
    #print "re_q = $re_q\n";
    #print "re_qqq = $re_qqq\n";

    #my $re_superescape = _gen_delimeted_regexp($quotes, "\\#");
    #print "re_superescape = $re_superescape\n";

    my $command_line = shift @_;    # copy command line [if used, "extract_..." functions are destructive of the original string]
    my $s = _ltrim($command_line);  # initial string to parse; prefix is whitespace trimmed
    my $glob_this_token = 1;

    # $s == string being parsed
    while ($s ne q{})
        {# $s is non-empty
        my $t = q{};    # in-progress token (may be partial)

        #print "s = `$s`\n";

        _ltrim($s); # remove leading whitespace
        $glob_this_token = 1;
        my $i = scalar(@argv_3);

        if ($s =~ /^([^\s$q_qm]+)(\s.*$|$)/)
            {# simple leading full token with no quote delimeter characters
            # $1 = non-whitespace/non-quote token
            # $2 = rest of string (with leading whitespace) [if exists]
            #print "1-push `$1` (g_ok = $glob_this_token)\n";
            $t = $1;
            #push @argv2, $1;
            #push @argv2_globok, $glob_this_token;
            #print "1-push (simple:token): token => $1, glob => 1\n";
            push @{ $argv_3[ scalar(@argv_3) ] }, { token => $1, glob => 1, id => 'simple:token' };
            $s = defined($2) ? $2 : q{};
            #_ltrim($s);
            #next;
            }
        else
            {
            # complex token containing quote delimeters
            Carp::Assert::assert( $s =~ /[$q_qm]/ );
            #my $t = q{};
            while ($s =~ /^\S/)
                {# parse full token containing quote delimeters
                # $s contains non-whitespace characters and starts with non-whitespace
                if ($s =~ /^((?:[^\s$q_qm\$]|\$[^$q_qm])*)((?:(\$([$q_qm]))|[$q_qm])?(.*))$/)
                    {# complex token with internal quotes and leading non-quote/non-whitespace characters
                    # initial non-quotes now separated
                    # $1 = initial non-quote/non-whitespace characters (except any $<quote-char>)
                    # $2 = rest of string after non-quote characters (including possible $<quote-char><...>)
                    # $3 = $<quote-char> [if exists]
                    # $4 = <quote-char> (of '$<quote-char>') [if exists]
                    # $5 = rest of quoted string (and any extra following characters)
                    #print "1.1 = `$1`\n" if defined($1);
                    #print "1.2 = `$2`\n" if defined($2);
                    #print "1.3 = `$3`\n" if defined($3);
                    #print "1.4 = `$4`\n" if defined($4);
                    #print "1.5 = `$5`\n" if defined($5);
                    if ( defined($1) && length($1) > 0 )    {
                        $t .= $1;
                        #print "1-push (complex:leading non-quoted+whitespace): token => $1, glob => 1\n";
                        push @{ $argv_3[ $i ] }, { token => $1, glob => 1, id => 'complex:leading non-quoted+whitespace' };
                        }
                    $s = defined($2) ? $2 : q{};
                    #_ltrim($s);
                    if ( $s =~ /^[\s]/ || _ltrim($s) eq q{} ) { last; }
                    #if ($2) { $s = $2; } else {$s = q{}; last; }
                    if ( defined($3) )
                        {# $'<...> or $"<...>
                        ## no critic ( ProhibitDeepNests )
                        $s = $4.$5;
                        if ($s =~ /^($re_q_escok)(.*)$/)
                            {# $'...'
                            my $d_one = _decode($1);
                            my $two = $2;
                            #print "d_one = $d_one\n";
                            #if ($d_one =~ /[$gc]/) { $glob_this_token = 0; }
                            $glob_this_token = 0 if ($d_one =~ /[$gc]/);        ## no critic (ProhibitPostfixControls)
                            $t .= _dequote($d_one);
                            $s = $two;
                            #print "1-push (complex:re_q_escok): token => $1, glob => 1\n";
                            push @{ $argv_3[ $i ] }, { token => _dequote($d_one), glob => 0, id => 'complex:re_q_escok' };
                            next;
                            }
                        ##if ($s =~ /^($re_qq)(.*)$/)
                        if ($s =~ /^($re_qq_escok)(.*)$/)
                            {# $"..."
                            #my $one = $1;
                            #my $two = $2;
                            #if ($one =~ /[$gc]/) { $glob_this_token = 0; } # globbing within ""'s is ok
                            #$t .= $one;
                            #$s = $two;
                            ##$t .= _dequote($1);
                            ##$s = $2;
                            my $d_one = _decode_dosqq($1);
                            $t .= _dequote($d_one);
                            $s = $2;
                            ###print "1-push (complex:re_qq): token => $1, glob => $opt{_glob_within_qq}\n";
                            #print "1-push (complex:re_qq_escok [within \$]): token => $1, glob => $opt{_glob_within_qq}\n";
                            ##push @{   $argv_3[ $i ] }, { token => _dequote($1), glob => $opt{_glob_within_qq}, id => 'complex:re_qq' };
                            push @{ $argv_3[ $i ] }, { token => _dequote($d_one), glob => $opt{_glob_within_qq}, id => 'complex:re_qq_escok_dollar' };
                            next;
                            }
                        $t .= q{$}.$s;
                        $_unbalanced_command_line = 1;
                        $s = q{};
                        last;
                        }
                    if ($s =~ /^($re_qq_escok)(.*)$/)
                        {# double-quoted token (possible internal escapes)
                        ## no critic ( ProhibitDeepNests )
                        #print "2.1 = `$1`\n" if $1;
                        #print "2.2 = `$2`\n" if $2;
                        my $d_one = _decode_dosqq($1);
                        $t .= _dequote($d_one);
                        $s = $2;
                        ###print "1-push (complex:re_qq): token => $1, glob => $opt{_glob_within_qq}\n";
                        #print "1-push (complex:re_qq_escok [bare]): token => $1, glob => $opt{_glob_within_qq}\n";
                        ##push @{   $argv_3[ $i ] }, { token => _dequote($1), glob => $opt{_glob_within_qq}, id => 'complex:re_qq' };
                        push @{ $argv_3[ $i ] }, { token => _dequote($d_one), glob => $opt{_glob_within_qq}, id => 'complex:re_qq_escok_bare' };
                        next;
                        }
                    if ($s =~ /^(?:($re_qqq)(.*))|(.*)$/)
                        {# quoted token (no escapes) == NOW only single quoted token after 're_qq_escok' change above
                        ## no critic ( ProhibitDeepNests )
                        #print "3.1 = `$1`\n" if $1;
                        #print "3.2 = `$2`\n" if $2;
                        #print "3.3 = `$3`\n" if $3;
                        #print "3.4 = `$4`\n" if $4;
                        #$t .= $1;
                        my $one = defined($1) ? $1 : q{};
                        my $two = defined($2) ? $2 : q{};
                        my $three = defined($3) ? $3 : q{};
                        if ($one)
                            {
                            my $quote;
                            my $dequoted_token;
                            $glob_this_token = 0;
                            #print "one = $one\n";
                            #if ($one =~ /^\'.*[$gc]+.*/) { $glob_this_token = 0; }
                            #$glob_this_token = 0 if    ($one =~ /^\'.*[$gc]+.*/);      ## no critic (ProhibitPostfixControls)
                            ( $quote, $dequoted_token ) = _dequote($one, {_return_quote => 1});
                            #$dequoted_token = _dequote($one);
                            $glob_this_token = $opt{_glob_within_qq} && ($quote eq $_G{qq});
                            $t .= $dequoted_token;
                            $s = $two;
                            #print "1-push (complex:noescapes): token => _dequote($one), glob => $glob_this_token\n";
                            push @{ $argv_3[ $i ] }, { token => _dequote($one), glob => $glob_this_token, id => 'complex:noescapes' };
                            }
                        else {
                            $t .= $three; $_unbalanced_command_line = 1; $s = q{};
                            #print "1-push (complex:NON-quoted/unbalanced): token => $three, glob => 1\n";
                            push @{ $argv_3[ $i ] }, { token => $three, glob => 1, id => 'complex:NON-quoted/unbalanced' };
                            last;
                            }
                        #else { $t .= $4; $s = q{}; $_unbalanced_command_line = 1; last; }
                        }
                    }
                else { Carp::croak q{no match: shouldn't get here...}; };
                }
            }

        _ltrim($s);
        if ( defined($t) )
            {
            #print "2-push `$t` (g_ok = $glob_this_token)\n";
            push @argv2, $t;
            push @argv2_globok, $glob_this_token;
            #push @{ $argv_3[ $i ] }, { token => $t, glob => 1, id => '$t' };
            next;
            }

        # no prior token match
        Carp::croak q{shouldn't get here...};
        #print "*-push `$s` (g_ok = $glob_this_token)\n";
        push @argv2, $s;
        push @argv2_globok, $glob_this_token;
        push @{ $argv_3[ scalar(@argv_3) ] }, { token => $s, glob => 1, id => 'WRONG:$s (shouldn\'t get here)' };       ## no critic (RequireInterpolationOfMetachars)
        $s = q{};
        }

    #@argv2 = Text::Balanced::extract_multiple($command_line, [ qr/\s*([^\s'"]+)\s/, sub { _mytokens($_[0]) }, qr/\S+/ ], undef, 1);

    #print "" . Dumper( @argv_3 )."\n";

    # remove $0 (and any prior entries) from ARGV array (and the matching glob signal array)
    my $n = _zero_position_v1( '['.$q_qm.']',   @argv2 );
    #print "n = $n\n";
    @argv2 = @argv2[$n+1..$#argv2];
    @argv2_globok = @argv2_globok[$n+1..$#argv2_globok];

    # check for unbalanced quotes and croak if so...
    if ($opt{_carp_unbalanced} && $_unbalanced_command_line) { Carp::croak 'Unbalanced command line quotes [#1] (at token `'.$argv2[-1].'` from command line `'.$command_line.'`)'; }

    # do globbing
#META CHARACTERS
#
#  \       Quote the next metacharacter
#  []      Character class
#  {}      Multiple pattern
#  *       Match any string of characters
#  ?       Match any single character
#  ~       User name home directory
#
#The metanotation a{b,c,d}e is a shorthand for abe ace ade. Left to right order is preserved, with results of matches being sorted separately at a low level to preserve this order. As a special case {, }, and {} are passed undisturbed.
#
#POSIX FLAGS
#
#The POSIX defined flags for bsd_glob() are:
#
#GLOB_ERR
#
#    Force bsd_glob() to return an error when it encounters a directory it cannot open or read. Ordinarily bsd_glob() continues to find matches.
#GLOB_LIMIT
#
#    Make bsd_glob() return an error (GLOB_NOSPACE) when the pattern expands to a size bigger than the system constant ARG_MAX (usually found in limits.h). If your system does not define this constant, bsd_glob() uses sysconf(_SC_ARG_MAX) or _POSIX_ARG_MAX where available (in that order). You can inspect these values using the standard POSIX extension.
#GLOB_MARK
#
#    Each pathname that is a directory that matches the pattern has a slash appended.
#GLOB_NOCASE
#
#    By default, file names are assumed to be case sensitive; this flag makes bsd_glob() treat case differences as not significant.
#GLOB_NOCHECK
#
#    If the pattern does not match any pathname, then bsd_glob() returns a list consisting of only the pattern. If GLOB_QUOTE is set, its effect is present in the pattern returned.
#GLOB_NOSORT
#
#    By default, the pathnames are sorted in ascending ASCII order; this flag prevents that sorting (speeding up bsd_glob()).
#
#The FreeBSD extensions to the POSIX standard are the following flags:
#
#GLOB_BRACE
#
#    Pre-process the string to expand {pat,pat,...} strings like csh(1). The pattern '{}' is left unexpanded for historical reasons (and csh(1) does the same thing to ease typing of find(1) patterns).
#GLOB_NOMAGIC
#
#    Same as GLOB_NOCHECK but it only returns the pattern if it does not contain any of the special characters "*", "?" or "[". NOMAGIC is provided to simplify implementing the historic csh(1) globbing behaviour and should probably not be used anywhere else.
#GLOB_QUOTE
#
#    Use the backslash ('\') character for quoting: every occurrence of a backslash followed by a character in the pattern is replaced by that character, avoiding any special interpretation of the character. (But see below for exceptions on DOSISH systems).
#GLOB_TILDE
#
#    Expand patterns that start with '~' to user name home directories.
#GLOB_CSH
#
#    For convenience, GLOB_CSH is a synonym for GLOB_BRACE | GLOB_NOMAGIC | GLOB_QUOTE | GLOB_TILDE | GLOB_ALPHASORT.
#
#The POSIX provided GLOB_APPEND, GLOB_DOOFFS, and the FreeBSD extensions GLOB_ALTDIRFUNC, and GLOB_MAGCHAR flags have not been implemented in the Perl version because they involve more complex interaction with the underlying C structures.
#
#The following flag has been added in the Perl implementation for csh compatibility:
#
#GLOB_ALPHASORT
#
#    If GLOB_NOSORT is not in effect, sort filenames is alphabetical order (case does not matter) rather than in ASCII order.
#
#DIAGNOSTICS
#
#bsd_glob() returns a list of matching paths, possibly zero length. If an error occurred, &File::Glob::GLOB_ERROR will be non-zero and $! will be set. &File::Glob::GLOB_ERROR is guaranteed to be zero if no error occurred, or one of the following values otherwise:
#
#GLOB_NOSPACE
#
#    An attempt to allocate memory failed.
#GLOB_ABEND
#
#    The glob was stopped because an error was encountered.
#
#In the case where bsd_glob() has found some matching paths, but is interrupted by an error, it will return a list of filenames and set &File::Glob::ERROR.
#
#Note that bsd_glob() deviates from POSIX and FreeBSD glob(3) behaviour by not considering ENOENT and ENOTDIR as errors - bsd_glob() will continue processing despite those errors, unless the GLOB_ERR flag is set.
#
#Be aware that all filenames returned from File::Glob are tainted.
#
#
#NOTES
#
#    *
#
#      If you want to use multiple patterns, e.g. bsd_glob("a* b*"), you should probably throw them in a set as in bsd_glob("{a*,b*}"). This is because the argument to bsd_glob() isn't subjected to parsing by the C shell. Remember that you can use a backslash to escape things.
#    *
#
#      On DOSISH systems, backslash is a valid directory separator character. In this case, use of backslash as a quoting character (via GLOB_QUOTE) interferes with the use of backslash as a directory separator. The best (simplest, most portable) solution is to use forward slashes for directory separators, and backslashes for quoting. However, this does not match "normal practice" on these systems. As a concession to user expectation, therefore, backslashes (under GLOB_QUOTE) only quote the glob metacharacters '[', ']', '{', '}', '-', '~', and backslash itself. All other backslashes are passed through unchanged.
#    *
#
#      Win32 users should use the real slash. If you really want to use backslashes, consider using Sarathy's File::DosGlob, which comes with the standard Perl distribution.
#    *
#
#      Mac OS (Classic) users should note a few differences. Since Mac OS is not Unix, when the glob code encounters a tilde glob (e.g. ~user) and the GLOB_TILDE flag is used, it simply returns that pattern without doing any expansion.
#
#      Glob on Mac OS is case-insensitive by default (if you don't use any flags). If you specify any flags at all and still want glob to be case-insensitive, you must include GLOB_NOCASE in the flags.
#
#      The path separator is ':' (aka colon), not '/' (aka slash). Mac OS users should be careful about specifying relative pathnames. While a full path always begins with a volume name, a relative pathname should always begin with a ':'. If specifying a volume name only, a trailing ':' is required.
#
#      The specification of pathnames in glob patterns adheres to the usual Mac OS conventions: The path separator is a colon ':', not a slash '/'. A full path always begins with a volume name. A relative pathname on Mac OS must always begin with a ':', except when specifying a file or directory name in the current working directory, where the leading colon is optional. If specifying a volume name only, a trailing ':' is required. Due to these rules, a glob like <*:> will find all mounted volumes, while a glob like <*> or <:*> will find all files and directories in the current directory.
#
#      Note that updirs in the glob pattern are resolved before the matching begins, i.e. a pattern like "*HD:t?p::a*" will be matched as "*HD:a*". Note also, that a single trailing ':' in the pattern is ignored (unless it's a volume name pattern like "*HD:"), i.e. a glob like <:*:> will find both directories and files (and not, as one might expect, only directories). You can, however, use the GLOB_MARK flag to distinguish (without a file test) directory names from file names.
#
#      If the GLOB_MARK flag is set, all directory paths will have a ':' appended. Since a directory like 'lib:' is not a valid relative path on Mac OS, both a leading and a trailing colon will be added, when the directory name in question doesn't contain any colons (e.g. 'lib' becomes ':lib:').
#
#
    my @argv2_g;
    my $glob_this;

    my %home_paths = _home_paths();
    # [DONE] add ability to specify "home_paths" from environment vars => use the general set ~<x>=<FOOPATH> technique
    # if <username> is duplicated in environment vars, it overrides any previous path found in the registry
    for my $k (keys %ENV)
        {
        if ( $k =~ /^~(\w+)$/ )
            {
            my $username = $1;
            $ENV{$k} =~ /\s*"?\s*(.*)\s*"?\s*/;
            if (defined $1) { $home_paths{lc($username)} = $1; }
                else { $home_paths{lc($username)} = $ENV{$k}; }
            }
        }
    for my $k (keys %home_paths) { $home_paths{$k} =~ s/\\/\//g; }; # unixify path seperators
    my $home_path_re =  q{(?i)}.q{^~(}.join(q{|}, keys %home_paths ).q{)?(/|$)}; ## no critic (RequireInterpolationOfMetachars)
    ##my $home_path_re = q{(?i)}.q{^~(?:[$q_qm])?(}.join(q{|}, keys %home_paths ).q{)(?:[$q_qm])?(/|$)}; ## no critic (RequireInterpolationOfMetachars)

    # TODO: figure out a method to allow '~"<username>"' to be globbed correctly since <username>'s can have internal whitespace
    #       currently, this is handled by adding the <username> with nulled internal whitespace into the home_path hash (but this process can result in collisions)
    #       * it may be difficult since globbing is done based on the "chunk" of the token and non-quoted and quoted portions are "chunked" into separate pieces (and what about ~"administrator"TEST == how far should the concatenation go for a possible match?)

    #for my $k (keys %home_paths) { #print "$k => $home_paths{$k}\n"; }
    #print "home_path_re = $home_path_re\n";

    use File::Glob qw( :glob );
    for (my $i=0; $i<=$#argv2; $i++)        ## no critic (ProhibitCStyleForLoops)
        {
        my @g = ();
        #print "argv2[$i] = $argv2[$i] (globok = $argv2_globok[$i])\n";
        my $pat;
        #$pat = $argv2[$i];
        #$pat =~ s/\\/\//g;     # change '\' to '/' within  path for correct globbing [Win32 only (? assert Win32)]

        $pat = q{};
        $s = q{};
        $glob_this = 0;
        # must meta-quote to allow glob metacharacters to correctly match within quotes
        foreach my $r_h ( @{ $argv_3[$n+$i+1] } )
            {
            my $t = $r_h->{token};
            $s .= $t;
            if ($r_h->{glob})
                {
                $glob_this = 1;
                $t =~ s/\\/\//g;
                #print "s = $s\n";
                #print "t = $t\n";
                }
            else
                { $t = _quote_gc_meta($t); }
            $pat .= $t;
            #print "r_h(token) = `$r_h->{token}`\n";
            #print "r_h(glob) = $r_h->{glob}\n";
            #print "r_h(id) = `$r_h->{id}`\n";
            #print "t = `$t`\n";
            #print "s = `$s`\n";
            #print "glob_this = $glob_this\n";
            #print "pat = `$pat`\n";
            }
        #print "s = '$s'\n";
        #$pat = $s;

        #if ($pat =~ /\s/) { $pat = $_G{'single_q'}.$pat.$_G{q}; }      # quote if contains white space to avoid splitting pattern  (NOT needed for bsd_glob())

        #print "pat = '$pat'\n";
        #if ($argv2_globok[$i]) { @g = File::DosGlob::glob( $pat ) if $pat =~ /[$gc]/; }
        # TODO: Figure out how to quote glob meta characters in the string corresponding _only_ to quoted sections of the token (? and glob all tokens)
##        if ($argv2_globok[$i]) { @g = glob( $pat ) if $pat =~ /[$gc]/; }      ## no critic (ProhibitPostfixControls)
##        @g = File::Glob::glob( $pat ) if ( $pat =~ /[$gc]/ );     ## no critic (ProhibitPostfixControls)      ## only glob if glob characters are in string


        # NOT!: bash-like globbing EXCEPT no backslash quoting within the glob; this makes "\\" => "\\" instead of "\" so that "\\machine\dir" works
        # DONE/instead: backslashes have already been replaced with forward slashes (by _quote_gc_meta())
        # must do the slash changes for user expectations ( "\\machine\dir\"* should work as expected on Win32 machines )
        # TODO: note differences this causes between bash and Win32::CommandLine::argv() globbing
        # TODO: note in LIMITATIONS section

        # DONE=>TODO: add 'dosify' option => backslashes for path dividers and quoted special characters (with escaped [\"] quotes) and whitespace within the ARGs
        # DONE=>TODO: find a better name for 'dospath' => 'dosify'
        # TODO: TEST 'dosify' and 'unixify'

        my $glob_flags = GLOB_NOCASE | GLOB_ALPHASORT | GLOB_BRACE | GLOB_QUOTE;
#       my $glob_flags = GLOB_NOCASE | GLOB_ALPHASORT | GLOB_BRACE;

        if ( $opt{nullglob} )
            {
            #$glob_flags |= GLOB_NOMAGIC;   # TEST: returns pattern ONLY if doesn't contain "*", "?" or "["? ## should this be something else instead?
            #$glob_flags &= ~GLOB_NOCHECK;
            }
        else
            {
            $glob_flags |= GLOB_NOCHECK;
            }

        if ( $opt{glob} && $glob_this )
            {
            $pat =~ s:\\\\:\/:g;        ## no critic ( ProhibitUnusualDelimiters )  ## replace all backslashes (assumed to be backslash quoted already) with forward slashes

            if ($pat =~ m/$home_path_re/)
                {# deal with possible prefixes
                ## no critic ( ProhibitUnusualDelimiters ) # ToDO: remove/revisit
                # TODO: NOTE: this allows quoted <usernames> which is different from bash, but needed because Win32 <username>'s can have internal whitespace
                # TODO: CHECK: are there any cases where the $s wouldn't match but $pat would causing incorrect fallback string?
                #print "pat(pre-prefix)  = `$pat`\n";
                #print "s(pre-prefix)    = `$s`\n";
                $pat =~ s/$home_path_re/$home_paths{lc($1)}$2/;
                $s =~ s:\\:\/:g;                                # unixify $s for processing
                $s =~ s/$home_path_re/$home_paths{lc($1)}$2/;   # need to change fallback string $s as well in case the final pattern doesn't expand with bsd_glob()
#               if ($opt{dosify}) { $s =~ s:\/:\\:g; };
                #if ($opt{dosify}) { _dosify($s); };
                #print "pat(post-prefix) = `$pat`\n";
                #print "s(post-prefix)   = `$s`\n";
                }

            if ( $pat =~ /\\[?*]/ )
                { ## '?' and '*' are not allowed in filenames in Win32, and Win32 DosISH globbing doesn't correctly escape them when backslash quoted, so skip globbing for any tokens containing these characters
                @g = ( $s );
                }
            else
                {
                @g = bsd_glob( $pat, $glob_flags );
                #print "s = $s\n";
                if ((scalar(@g) == 1) && ($g[0] eq $pat)) { @g = ( $s ); }
##              elsif ($opt{dosify}) { foreach my $glob (@g) { $glob =~ s:\/:\\:g; } };     ## no critic (ProhibitUnusualDelimiters)    ## replace / with \ for all globbed tokens if $opt{dosify}
##              elsif ($opt{dosify}) { foreach my $glob (@g) { _dosify($glob); } };     ## no critic (ProhibitUnusualDelimiters)    ## replace / with \ for all globbed tokens if $opt{dosify}
                }
            }
        else
            {
            @g = ( $s );
            }
        #print "glob_this = $glob_this\n";
        #print "s   = `$s`\n";
        #print "pat = `$pat`\n";
        #print "#g = @g\n";

        # if whitespace or special characters, surround with double-quotes ((::whole token:: or just individual problem characters??))
        if ($opt{dosify})
            {
###         my $dos_special_chars = ':*?"<>|';
##          # TODO: check these characters for necessity => PIPE characters [<>|] and internal double quotes for sure, [:]?, [*?] glob chars needed?, what about glob character set chars [{}]?
##          my $dos_special_chars = '"<>|';
##          my $dc = quotemeta( $dos_special_chars );
##          foreach my $tok (@g) {
##              if ($tok =~ qr{(\s|[$dc])})
##                  {
##                  $tok =~ s:":\\":g;  # CMD: preserve double-quotes within double-quotes with backslash escape    # TODO: change to $dos_escape   ## no critic (ProhibitUnusualDelimiters)
##                  $tok = q{"}.$tok.q{"};
##                  #$tok =~ s/^(\/\w+(?:[=:])?)?(.*)$/$1\"$2\"/;
##                  ##$tok = _dosify($tok);
##                  };
###             if ($tok =~ qr{(\s|[$dc])}) { $tok = q{"}.$tok.q{"}; };
##              };
            foreach (@g) { _dosify($_); }
            };

        push @argv2_g, @g;
        }

    ## TODO: TEST and EXPAND these...
##  if ($opt{dosify} eq 'all') { foreach my $a (@argv2_g) { if (-e $a) {$a =~ s:\/:\\:g; } } }  ## no critic (ProhibitUnusualDelimiters)
    if ($opt{dosify} eq 'all') { foreach my $a (@argv2_g) { if (-e $a) { _dosify($a); } } } ## no critic (ProhibitUnusualDelimiters)
    if ($opt{unixify} eq 'all') { foreach my $a (@argv2_g) { if (-e $a) {$a =~ s:\\:\/:g; } } } ## no critic (ProhibitUnusualDelimiters)

    return @argv2_g;
}

sub _home_paths
{
# TODO:? memoize the home paths array

## no critic (ProhibitUnlessBlocks)
# _home_paths(): returns %
# pull user home paths from registry

# modified from File::HomeDir::Win32 (v0.04)

# CHANGED: eval optional modules as strings to avoid Kwalitee 'prereq_matches_use' ding for 'Win32::Security::SID' missing as a requirement in META.yml
##my $have_all_needed_modules = eval { require Win32; require Win32::Security::SID; require Win32::TieRegistry; 1; };
my @modules = ( 'Win32', 'Win32::Security::SID', 'Win32::TieRegistry' );
my $have_all_needed_modules = 1;
foreach (@modules) { if (!eval "require $_; 1;") { $have_all_needed_modules = 0; last; } }  ## no critic (ProhibitStringyEval)

my %home_paths = ();

# initial paths for user from environment vars
if ($ENV{USERNAME} && $ENV{USERPROFILE}) { $home_paths{q{}} = $home_paths{lc($ENV{USERNAME})} = $ENV{USERPROFILE}; };

# add All Users / Public
$home_paths{'all users'} = $ENV{ALLUSERSPROFILE};                   #?? should this be $ENV{PUBLIC} on Vista/Win7+?
if ($ENV{PUBLIC}) { $home_paths{public} = $ENV{PUBLIC}; }
else { $home_paths{public} = $ENV{ALLUSERSPROFILE}; }

my $profiles_href;

if ($have_all_needed_modules) {
    my $node_name   = Win32::NodeName;
    my $domain_name = Win32::DomainName;

    $profiles_href = $Win32::TieRegistry::Registry->{'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\ProfileList\\'}; ## no critic (ProhibitPackageVars)
    unless ($profiles_href) {
        # Windows 98
        $profiles_href = $Win32::TieRegistry::Registry->{'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ProfileList\\'};    ## no critic (ProhibitPackageVars)
        }

    #foreach my $p (keys %{$profiles}) { #print "profiles{$p} = $profiles->{$p}\n"; }

    foreach my $p (keys %{$profiles_href})
        {
        #print "p = $p\n";
        if ($p =~ /^(S(?:-\d+)+)\\$/) {
            my $sid_str = $1;
            my $sid = Win32::Security::SID::ConvertStringSidToSid($1);
            my $uid = Win32::Security::SID::ConvertSidToName($sid);
            my $domain = q{};
            if ($uid =~ /^(.+)\\(.+)$/) {
                $domain = $1;
                $uid    = $2;
                }
            if ($domain eq $node_name || $domain eq $domain_name) {
                my $path = $profiles_href->{$p}->{ProfileImagePath};
                $path =~ s/\%(.+)\%/$ENV{$1}/eg;
                #print $uid."\n";
                $uid = lc($uid);                # remove/ignore user case
                $home_paths{$uid} = $path;      # save uid => path
                }
            }
        }
    foreach my $uid (sort keys %home_paths)
        {# add paths for UIDs with internal whitespace removed (for convenience)
        if ($uid =~ /\s/) {
            # $uid contains whitespace
            my $path = $home_paths{$uid};
            $uid =~ s/\s+//g; # remove any internal whitespace (Win32 usernames may have internal whitespace)
            if (!$home_paths{$uid}) { $home_paths{$uid} = $path; } # save uid(no-whitespace) => path (NOTE: no overwrites if previously defined, to avoid possible collisions with other UIDs)
            }
        }
    }

#for my $k (keys %home_paths) { #print "$k => $home_paths{$k}\n"; }
return %home_paths;
}

#print '#registry entries = '.scalar( keys %{$Win32::TieRegistry::Registry} )."\n";

1; # Magic true value required at end of module (for require)

####

#sub _mytokens
#{# parse tokens with one or more quotes (balanced or not)
## bash-like tokens ($'...' and $"...")
## ToDO: Rename => extract_quotedToken? remove_semiquoted? ...
## ToDO?: make more general specifying quote character set#my $textref = defined $_[0] ? \$_[0] : \$_;
#my $wantarray = wantarray;
#my $position = pos $$textref || 0;
#
##--- config
#my $unbalanced_as_separate_last_arg = 0;       # if unbalanced quote exists, make it a last separate argument (even if not separated from last argument by whitespace)
##---
#
#my $r = q{};
#my $s = q{};
#my $p = q{};
#
#my $q = qq{\'\"};      # quote characters
#my $e = q$_G{'escape_char'};        # quoted string escape character
#
#print "[in@($position)] = :$$textref: => :".substr($$textref, $position).":\n";
#if ($$textref =~ /\G(\s*)([\S]*['"]+.*)/g)
#   {# at least one quote character exists in the next token of the string; $1 = leading whitespace, $2 = string
#   $p = defined $1 ? $1 : q{};
#   $s = $2;
#   #print "prefix = '$p'\n";
#   #print "start = '$s'\n";
#   while ($s =~ m/^([^\s'"]*)(.*)$/)
#       {# $1 = non-whitespace prefix, $2 = quote + following characters
#       #print "1 = '$1'\n";
#       #print "2 = '$2'\n";
#       my $one = $1;
#       my $two = $2;
#       $r .= $one;
#       $s = $two;
#       if ($two =~ /^[^'"]/) {
#           #print "last (no starting quote)\n";
#           # shouldn't happen
#           last;
#           }
#       my ($tok, $suffix, $prefix) = Text::Balanced::extract_delimited($two);
#       #my ($tok, $suffix, $prefix) = _extract_delimited($two, undef, undef, '+');
#       #print "tok = '$tok'\n";
#       #print "suffix = '$suffix'\n";
#       #print "prefix = '$prefix'\n";
#       $r .= $tok;
#       $s = $suffix;
#       if ($tok eq q{}) {
#           #$Win32::CommandLine::_unbalanced_command_line =    1;
#           if (($r ne q{} && !$unbalanced_as_separate_last_arg) || ($r eq q{})) {
#               $r .= $suffix; $s = q{};
#               }
#           #print "r = '$r'\n";
#           #print "s = '$s'\n";
#           #print "last (no tok)\n";
#           last;
#           }
#       #print "r = '$r'\n";
#       #print "s = '$s'\n";
#       if ($s =~ /^\s/) {
#           #print "last (s leading whitespace)\n";
#           last;
#           }
#       }
#   }
#
#my $posadvance = length($p) + length($r);
##print "posadvance = $posadvance\n";
##print "[out] = ('$r', '$s', '$p')\n";
#pos($$textref) = $position + $posadvance;
#return ($r, $s, $p);
#}

=for readme continue

=head1 SYNOPSIS

=for author_to_fill_in
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exemplary as possible.

=over

 @ARGV = Win32::CommandLine::argv() if eval { require Win32::CommandLine; };

B<E<nbsp>E<nbsp>E<nbsp>E<nbsp>_or_>

 use Win32::CommandLine qw( command_line );
 my $commandline = command_line();
 ...

=back

=head1 DESCRIPTION

=for author_to_fill_in
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.

This module is used to reparse the Win32 command line, automating better quoting, command substitution, and globbing of the command line.
Globbing is full bash POSIX compatible globbing. With the use of the companion script (B<C<xx.bat>>), and B<C<doskey>> for macro aliasing,
you can add fully implemented, bash compatible, string quoting/expansion and file globbing to I<any> Win32 executable.

This module is compatible with both B<C<cmd.exe>> and C<4nt/tcc/tcmd> shells, and can be used to add better parsing and bash glob
expansion to I<any> external command (by using the included B<C<xx.bat>> batch script).

=head2 B<C<CMD.EXE>>

=over

 doskey type=call xx type $*
 type [a-c]*.pl
 doskey perl=call xx perl $*
 perl -e 'print "test"'      [would otherwise FAIL]

=back

=head2 C<4NT/TCC/TCMD>

=over

 alias type=call xx type
 type [a-c]*.pl
 alias perl=call xx perl
 perl -e 'print "test"'      [would otherwise FAIL]

=back

Note that bash-compatible globbing and argument expansion are supplied, including command substitution. Glob patterns may also
contain meta-notations, such as 'C<a[bc]*>' or 'C<foo.{bat,pl,exe,o}>'.

=for another_example
    cpan $(dzil listdeps)   :: with a CPAN wrapper program

=head2 Command line string/character expansion

=over

 '...'    literal (no escapes and no globbing within quotes)
 "..."    literal (no escapes and no globbing within quotes) (see *NOTE-1)
 $'...'   string including all ANSI C string escapes (see *NOTE-2); no globbing within quotes
 $"..."   literal (no escapes and no globbing within quotes) [same as "..."]
 $( ... ) command substitution (see *NOTE-3)
 $("...") command substitution (quotes removed; see *NOTE-4)

=back

NOTE-1: DOS character escape sequences (such as C<"\"">) are parsed prior to being put into the command
line and, so, are valid and still (unavoidably) interpreted within double-quotes.

NOTE-2: ANSI C string escapes are C<\a, \b, \e, \f, \n, \r, \t, \v, \\, \', \[0-9]{1,3}, \x[0-9a-fA-f]{1,2}, \c[@A-Z[\\\]\^_`]>;
all other escaped characters are left in place without transformation (C<< \<x> => \<x> >>).

NOTE-3: Command substitution replaces the C<$(...)> argument with the standard output of that
argument's execution. Command substitution strings are not, themselves, automatically expanded;
use C<$(xx.bat >C<I<COMMAND>)>) to trigger expansion of the subshell command line.

NOTE-4: C<$("...")> is present to enable delayed DOS/Windows interpretation of redirection & continuation characters. This
allows redirection & continuation characters to be used within the subshell command string.

URLref: [bash ANSI-C Quoting] L<http://www.gnu.org/software/bash/manual/html_node/ANSI_002dC-Quoting.html> @@ L<http://www.webcitation.org/66M8skmP8>

=for ToDO
    NOTE: \XHH also currently works (although capitalized versions of the other escape sequences DO NOT cause a transformation)... ? remove \XHH ## needs research

=head2 GLOB META CHARACTERS

=over

 \           Quote the next metacharacter
 []          Character class
 {}          Multiple pattern
 *           Match any string of characters
 ?           Match any single character
 ~           Current user home directory
 ~USERNAME   Home directory of USERNAME
 ~TEXT       Environment variable named ~TEXT (aka $ENV{~TEXT}) [overrides ~USERNAME expansion]

=back

The multiple pattern metanotation 'C<a{b,c,d}e>' is a shorthand for 'C<abe ace ade>'.  Left to
right order is preserved, with results of matches being sorted separately at a low level to preserve this order.

=for CHECK-THIS
    As special cases C<{}> and umatched C<}> are passed through undisturbed to the final command line. [TRUE]
    Unmatched C<{> is consumed. [TRUE, may change?]

=for CHECK-THIS
     verify and document ~<text> overrides ~<name> ## TRUE, except $ENV{~} which has no effect ## verify and document which has priority

=head1 INSTALLATION

To install this module, run the following commands:

=over

 perl Build.PL
 ./Build
 ./Build test
 ./Build install

=back

Or, if you're on a platform (like DOS or Windows) that doesn't require the leading 'C<./>' notation, you can
replace 'C<./Build>' with just 'C<Build>'.

Alternatively, the standard make idiom is also available (although it is deprecated):

=over

 perl Makefile.PL
 make
 make test
 make install

=back

(On Windows platforms, you should use B<C<nmake>>or B<C<dmake>>, instead of B<C<make>>.)

Note that the Makefile.PL script is just a pass-through, and Module::Build is still ultimately required for installation.
Makefile.PL will throw an exception if Module::Build is missing from your current installation. C<cpan> will
notify the user of the build prerequisites (and install them for the build, if it is setup to do so [see the cpan
configuration option C<build_requires_install_policy>]).

PPM installation bundles should also be available in the standard PPM repositories (i.e. ActiveState, trouchelle.com [L<http://trouchelle.com/ppm/package.xml>]).

Note: On ActivePerl installations, 'C<./Build install>' will do a full installation using B<C<ppm>> (see ppm).
During the installation, a PPM package is constructed locally and then subsequently used for the final module install.
This allows for uninstalls (using 'C<ppm uninstall >C<I<MODULE>>' and also keeps local HTML documentation current.

=for future_possibles
    Check into using the PPM perl module, if installed, for installation of this module (removes the ActiveState requirement).

=for readme stop

=head1 INTERFACE

=for author_to_fill_in
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.

=head2 C<command_line( ): $>

=over

=item * [out] : the original command line for the process, as a string

=back

 my $commandline = command_line();

Use the Win32 API to recapture the original command line for the current process.

=head2 C<argv( [\%options] ): @>

=over

=item * [in] : (optional) reference to hash containing function options

=item * [out] : returns a new argument array (which can replace @ARGV)

=back

 @ARGV = argv();

Reparse & glob-expand the original command line, returning a new argument array (which is a drop-in replacement for @ARGV).

=head2 C<parse( $ [,\%options ] ): @>

=over

=item * [in] : string argument to parse/glob-expand

=item * [in] : (optional) reference to hash containing function options

=item * [out] : returns an argument array

=back

 my @argv_new = parse( command_line() );

Parse & glob-expand a string argument; returns the results of parsed/expanded argument as an array.

=head2 Function Options ( C<\%options> )

    my %options = (
        remove_exe_prefix => 1,     # = 0/<true> [default = true]       # if true, remove all initial args up to and including the exe name from the @args array
        dosquote => 0,              # = 0/<true>/'all' [default = 0]    # if true, convert all non-globbed ARGS to DOS/Win32 CLI compatible tokens (escaping internal quotes and quoting whitespace and special characters)
        dosify => 0,                # = 0/<true>/'all' [default = 0]    # if true, convert all _globbed_ ARGS to DOS/Win32 CLI compatible tokens (escaping internal quotes and quoting whitespace and special characters); 'all' => do so for for _all_ ARGS which are determined to be files
        unixify => 0,               # = 0/<true>/'all' [default = 0]    # if true, convert all _globbed_ ARGS to UNIX path style; 'all' => do so for for _all_ ARGS which are determined to be files
        nullglob => defined($ENV{nullglob}) ? $ENV{nullglob} : 0,       # = 0/<true> [default = 0]  # if true, patterns which match no files are expanded to a null string (no token), rather than the pattern itself  ## $ENV{nullglob} (if it exists) overrides the default
        glob => 1,                  # = 0/<true> [default = true]       # when true, globbing is performed
        ## TODO: rework this ... need carp/croak on unbalanced quotes/subshells (? carp_ub_quotes, carp_ub_shells, carp = 0/1/warn/carp/die/croak)
        croak_unbalanced => 1,      # = 0/true/'quotes'/'subshells' [default = true] # if true, croak for unbalanced command line quotes or subshell blocks (takes precedence over carp_unbalanced)
        carp_unbalanced => 1,       # = 0/true/'quotes'/'subshells' [default = true] # if true, carp for unbalanced command line quotes or subshell blocks
        ## ToDO: add globstar option
        );

=head1 SUBROUTINES/METHODS

=for author_to_fill_in
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.

=for readme continue

=head1 RATIONALE

This began as a simple need to work-around the less-than-stellar C<COMMAND.COM>/C<CMD.EXE> command line parser, just to accomplish more `correct` quotation interpretation.
It then grew into a small odyssey: learning XS and how to create a perl module, learning the perl build process and creating a customized build script/environment,
researching tools and developing methods for revision control and versioning, learning and creating perl testing processes, and finally learning about PAUSE
and perl publishing practices. And, somewhere in the middle, adding some of the C<bash> shell magic to the CMD shell (and, additionally, making it
compatible with the excellent [and free] TCC-LE shell from JPSoft [find that at L<http://jpsoft.com>]).

Some initial attempts were made using C<Win32::API> and C<Inline::C>. For example, a C<Win32::API> attempt [which caused GPFs]:

  @rem = '--*-Perl-*--
  @echo off
  if "%OS%" == "Windows_NT" goto WinNT
  perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
  goto endofperl
  :WinNT
  perl -x -S %0 %*
  if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
  if %errorlevel% == 9009 echo You do not have Perl in your PATH.
  if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
  goto endofperl
  @rem ';
  #!/usr/bin/perl -w
  #line 15
  #
  use Win32::API;
  #
  Win32::API->Import("kernel32", "LPTSTR GetCommandLine()");
  my $string = pack("Z*", GetCommandLine());
  #
  print "string[".length($string)."] = '$string'\n";
  # ------ padding --------------------------------------------------------------------------------------
  __END__
  :endofperl

Unfortunately, C<Win32::API> and C<Inline::C> were shown to be too fragile at the time (in 2007).
C<Win32::API> caused occasional (but reproducible) GPFs, and C<Inline::C> was shwon to be very brittle on Win32 systems (i.e, not compensating for paths with embedded strings).
[ See L<http://www.perlmonks.org/?node_id=625182> for a more full explanation of the problem and initial attempts at a solution. ]

So, an initial XS solution was implemented. And from that point, the lure of C<bash>-like command line parsing led inexorably to the full implementation. The parsing logic is unfortunately still complex, but seems to be holding up well under testing.

=for readme stop

=head1 IMPLEMENTATION and INTERNALS

This is a list of internal XS functions (brief descriptions will be added at a later date):

  SV * _wrap_GetCommandLine() // [XS] Use C and Win32 API to get the command line
  HANDLE _wrap_CreateToolhelp32Snapshot ( dwFlags, th32ProcessID )
  bool _wrap_Process32First ( hSnapshot, lppe )
  bool _wrap_Process32Next ( hSnapshot, lppe )
  bool _wrap_CloseHandle ( hObject )
  // Pass useful CONSTANTS back to perl
  int _const_MAX_PATH ()
  HANDLE _const_INVALID_HANDLE_VALUE ()
  DWORD _const_TH32CS_SNAPPROCESS ()
  // Pass useful sizes back to Perl (for testing) */
  unsigned int _info_SIZEOF_HANDLE ()
  unsigned int _info_SIZEOF_DWORD ()
  // Pass PROCESSENTRY32 structure info back to Perl
  SV * _info_PROCESSENTRY32 ()

=for further_expansion
    other internal function notes

=head1 DIAGNOSTICS

=for author_to_fill_in
    List every single error and warning message that the module can
    generate (even the ones that will ''never happen''), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

Pending documentation...

=begin FUTURE-DOCUMENATION

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back

=end FUTURE-DOCUMENATION

=head1 CONFIGURATION AND ENVIRONMENT

=for author_to_fill_in
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.

C<Win32::CommandLine> requires no configuration files or environment variables.

=head2 OPTIONAL Environment Variables

=over

=item C<NULLGLOB> - override the default glob expansion behavior for empty matches

 $ENV{NULLGLOB} = 1; # undef/0 | <true>

Default glob expansion, as in bash, expands glob patterns which match nothing into the glob pattern itself.
Use C<$ENV{NULLGLOB}> to override this default behavior.

Analogous to the bash command 'C<shopt -s nullglob>', when C<$ENV{NULLGLOB}> is set to a true (non-NULL, non-zero)
value, a glob expansion which matches nothing will expand to the null string (aka, C<q{}>).

Note: the default glob expansion behavior can also be modified programmatically
via the function option, C<nullglob>, when passed to the argv() and parse() functions.
This option, when passed to C<argv()> or C<parse()>, will override both the default behavior
I<and> the C<$ENV{NULLGLOB}> setting.

=for possible_future
    $ENV{GLOBSTAR} = 0 | TRUE ... URLref:https://www.gnu.org/software/bash/manual/html_node/The-Shopt-Builtin.html#The-Shopt-Builtin
        If set, the pattern '**' used in a filename expansion context will match all files and zero or more directories and subdirectories. If the pattern is followed by a '/', only directories and subdirectories match.
    $ENV{WIN32_COMMANDLINE_RULE} = "sh" | "bash" (case doesn't matter) => argv will parse in "sh/bash" manner if set to "default"|"undef"
    - will warn (not carp) if value unrecognized

=back

=for readme continue

=head1 DEPENDENCIES

=for author_to_fill_in
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

C<Win32::CommandLine> requires C<Carp::Assert> for internal error checking and warnings.

The optional modules C<Win32>, C<Win32::Security::SID>, and C<Win32::TieRegistry> are recommended to allow full glob tilde expansions
for user home directories (eg, C<~administrator> expands to C<C:\Users\Administrator>). Expansion of the single tilde (C<~>) has a backup
implementation based on %ENV variables, and therefore will still work even without the optional modules.

=for readme stop

=head1 INCOMPATIBILITIES

=for author_to_fill_in
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.

=head1 BUGS AND LIMITATIONS

=for author_to_fill_in
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

Please report any bugs or feature requests to C<bug-Win32-CommandLine@rt.cpan.org>, or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Win32-CommandLine>. The developers will be notified, and you'll automatically be notified of progress on your bug as any changes are made.

=head2 Operational Notes

IMPORTANT NOTE: Special shell characters (shell redirection [ C<'|'>, C<'<'>, C<'>'> ] and continuation C<'&'>) must be B<DOUBLE-quoted> to escape shell interpretation (eg, C<< "foo | bar" >>). The shell does initial parsing and redirection/continuation (stripping away everything after I/O redirection and continuation characters) before B<any> process can get a look at the command line. So, the special shell characters can only be hidden from shell interpretation by quoting them with double-quote characters.

=for CORRECTION
    special characters need to be DOUBLE-QUOTED or escaped (usually the escape character is ^)...

C<< %<X> >> is also replaced by the corresponding %ENV variable by the shell before handing the command line off to the OS. So, C<%%> must be used to place single %'s in the command line (eg, C<< perl -e "use Win32::CommandLine; %%x = Win32::CommandLine::_home_paths(); for (sort keys %%x) { print qq{$_ => $x{$_}\n}; }" >>).

=for CORRECTION
    for TCC: %X and %X% are replaced prior to expansion
    for CMD: %X% is replaced but %X is left alone ( and lack of whitespace is not a barrier to interpretation ... '%o = (t=>1); @k = keys %o;' => 'o;'
    for TCC: %NOT_AN_ENV_VAR% => <null>
    for CMD: %NOT_AN_ENV_VAR% => %NOT_AN_ENV_VAR%

Brackets ('{' and '}') and braces ('[' and ']') must be quoted (single or double quotes) to be matched literally. This may be a gotcha for some users, although if the filename has internal spaces, tab expansion of filenames for the standard Win32 shell (cmd.exe) or 4NT/TCC/TCMD will automatically surround the entire path with spaces (which corrects the issue).

Some programs may expect their arguments to maintain their surrounding quotes, but argv() parsing only quotes arguments which require it to maintain equivalence for shell parsing (i.e., those containing spaces, special characters, etc). And, since single quotes have no special meaning to the shell, all arguments which require quoting for correct shell interpretation will be quoted with double-quote characters, even if they were originally quoted with single-quotes. Neither of these issues should be a problem for programs using Win32::CommandLine, but may be an issue for 'legacy' applications which have their command line expanded with B<C<xx.bat>>.

Be careful with backslashed quotes within quoted strings. Note that "foo\" is an B<unbalanced> string containing a double quote. Place the backslash outside of the quotation ("foo"\) or use a double backslash within ("foo\\") to include the backslash it in the parsed token. However, backslashes ONLY need to be doubled when placed prior to a quotation mark ("foo\bar" will work as expected).

=for further_expansion
    GOTCHA: Note this behavior (ending \" => ", which is probably not what is desired or expected in this case (? what about other cases, should this be "fixed" or would it break something else?)
    C:\...\perl\Win32-CommandLine
    >t\prelim\echo.exe "\\sethra\C$\"win*
    [0]\\sethra\C$"win*

=for FIXED
    4NT/TCC/TCMD NOTE: The shell interprets and B<removes> backquote characters before executing the command. You must quote backquote characters with B<**double-quotes**> to pass them into the command line (eg, {perl -e "print `dir`"} NOT {perl -e 'print `dir`'} ... the single quotes do not protect the backquotes which are removed leaving just {dir}).
        ??? fix this by using $ENV{CMDLINE} which is set by TCC? => attempts to workaround this using $ENV{CMDLINE} fail because TCC doesn't have control between processes and can't set the new CMDLINE value if one process directly creates another (and I'm not sure how to detect that TCC started the process)
        -- can try PPIDs if Win32::API is present...
            => DONE [2009-02-18] [seems to be working now... if Win32::API is available, parentEXE is checked and $ENV{CMDLINE} is used if the parent process matches 4nt/tcc/tcmd]

=head2 Bugs

No bugs have been reported.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

=over

 perldoc Win32::CommandLine

=back

You can also look for further information at:

=over

=item * CPAN

=over

L<https://metacpan.org/search?q=Win32-CommandLine>

L<http://search.cpan.org/dist/Win32-CommandLine>

L<http://kobesearch.cpan.org/dist/Win32-CommandLine>

=back

=item * CPAN Ratings

=over

L<http://cpanratings.perl.org/dist/Win32-CommandLine>

=back

=item * RT: CPAN's request tracker (aka buglist)

=over

L<http://rt.cpan.org/Public/Dist/Display.html?Name=Win32-CommandLine>

=back

=item * CPANTESTERS: Test results

=over

L<http://www.cpantesters.org/show/Win32-CommandLine.html>

=back

=item * CPANTS: CPAN Testing Service

=over

C<[kwalitee]> L<http://cpants.perl.org/dist/kwalitee/Win32-CommandLine>

C<[ used by]> L<http://cpants.perl.org/dist/used_by/Win32-CommandLine>

=back

=back

=for possible_future
    * AnnoCPAN: Annotated CPAN documentation
      http://annocpan.org/dist/Win32-CommandLine
    * CPANFORUM: Forum discussing Win32::CommandLine
      http://www.cpanforum.com/dist/Win32-CommandLine

=head1 TODO

Expand and polish the documentation. Add argument/option explanations and examples for interface functions.

=head1 TESTING

=for REFERENCE [good documentation/TESTING heading :: URLref: http://search.cpan.org/dist/Net-Amazon-S3/lib/Net/Amazon/S3.pm ]

=for REFERENCE [info re end-user/install vs automated vs release/author testing :: URLref: http://search.cpan.org/~adamk/Test-XT-0.02/lib/Test/XT.pm ]

For additional testing, set the following environment variables to a true value ("true" in the perl sense, meaning non-NULL, non-ZERO value):

=over

=item TEST_AUTHOR

Perform distribution correctness and quality tests, which are essential prior to a public release.

=item TEST_FRAGILE

Perform tests which have a specific (i.e., fragile) execution context (eg, network tests to named hosts).
These are tests that must be coddled with specific execution contexts or set up on specific machines to
complete correctly.

=item TEST_SIGNATURE

Verify signature is present and correct for the distribution.

=item TEST_ALL

Perform ALL (non-FRAGILE) additional/optional tests. Given the likelyhood of test failures without special handling,
tests marked as 'FRAGILE' are still NOT performed unless TEST_FRAGILE is also true. Additionally, note that
the 'build testall' command can be used as an equivalent to setting TEST_ALL to true temporarily, for the duration
of the build, followed by a 'build test'.

=back

=for TODO
    =head1 SEE ALSO

=for readme continue

=head1 LICENSE AND COPYRIGHT

 Copyright (c) 2007-2013, Roy Ivy III <rivy[at]cpan[dot]org>. All rights reserved.

This module is free software; you can redistribute it and/or modify it under the
Perl Artistic License v2.0 (see L<http://opensource.org/licenses/artistic-license-2.0.php>).

=head1 DISCLAIMER OF WARRANTY

 THIS PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER AND CONTRIBUTORS "AS IS"
 AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES. THE IMPLIED WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT
 ARE DISCLAIMED TO THE EXTENT PERMITTED BY YOUR LOCAL LAW. UNLESS REQUIRED
 BY LAW, NO COPYRIGHT HOLDER OR CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF
 THE USE OF THE PACKAGE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

 [REFER TO THE FULL LICENSE FOR EXPLICIT DEFINITIONS OF ALL TERMS.]

=head1 ACKNOWLEDGEMENTS

Thanks to BrowserUK and syphilis (aka SISYPHUS on CPAN) for some helpful ideas (including an initial XS starting
point for the module) during a discussion on PerlMonks (see L<http://www.perlmonks.org/?node_id=625182>).

=for TODO
    POST in REPLY to http://www.perlmonks.org/?parent=625182;node_id=3333
    I just wanted to drop you a note to let you know that I used your post here as a starting point and ultimately went in for the full monty. After a lot of research, investigation, and coding, I've just released Win32::CommandLine [1] on CPAN last week.
    It does a little more than just grab the command line now. :)
    Thanks for the help and encouragement.
    - Roy
    [1] http://search.cpan.org/~rivy/Win32-CommandLine
    POST in reply to http://www.perlmonks.org/?parent=625151;node_id=3333
    I wanted to thank both BrowserUK and syphilis

=head1 AUTHOR

Roy Ivy III <rivy[at]cpan[dot]org>

=for readme stop

=begin IMPLEMENTATION-NOTES

BASH QUOTING
    Quoting is used to remove the special meaning of certain characters or words to the
    shell.  Quoting can be used to disable special treatment for special characters, to
    prevent reserved  words  from  being  recognized as such, and to prevent parameter
    expansion.

    Each of the metacharacters listed above under DEFINITIONS has  special  meaning to
    the shell and must be quoted if it is to represent itself.

    When the command history expansion facilities are being used (see HISTORY EXPANSION
    below), the history expansion character, usually !, must be quoted to prevent  his-
    tory expansion.

    There are three quoting mechanisms: the escape character, single quotes, and double
    quotes.

    A non-quoted backslash (\) is the escape character. It preserves the literal value
    of  the next character that follows, with the exception of <newline>.  If a \<new-
    line> pair appears, and the backslash is  not  itself  quoted,  the \<newline> is
    treated as a  line continuation (that is, it is removed from the input stream and
    effectively ignored).

    Enclosing characters in single quotes preserves the literal value of each character
    within  the quotes.  A single quote may not occur between single quotes, even when
    preceded by a backslash.

    Enclosing characters in double quotes preserves the literal value of all characters
    within  the quotes,  with the exception of $, `, \, and, when history expansion is
    enabled, !. The characters $ and ` retain  their  special  meaning within double
    quotes. The backslash retains its special meaning only when followed by one of the
    following characters: $, `, ", \, or <newline>.  A double quote  may be quoted
    within  double quotes by preceding it with a backslash. If enabled, history expan-
    sion will be performed unless an !  appearing in double quotes is escaped  using  a
    backslash.  The backslash preceding the !  is not removed.

    The special  parameters  * and  @ have special meaning when in double quotes (see
    PARAMETERS below).

    Words of the form $'string' are treated specially.  The word  expands  to  string,
    with  backslash-escaped characters replaced  as specified by the ANSI C standard.
    Backslash escape sequences, if present, are decoded as follows:
     \a  alert (bell)
     \b  backspace
     \e  an escape character
     \f  form feed
     \n  new line
     \r  carriage return
     \t  horizontal tab
     \v  vertical tab
     \\  backslash
     \'  single quote
     \nnn  the eight-bit character whose value is the octal value  nnn  (one to
      three digits)
     \xHH  the  eight-bit character whose value is the hexadecimal value HH (one
      or two hex digits)
     \cx  a control-x character

    The expanded result is single-quoted, as if the dollar sign had not been present.

    A double-quoted string preceded by a dollar sign ($) will cause the string to be
    translated  according  to the current locale.  If the current locale is C or POSIX,
    the dollar sign is ignored. If the string is translated and replaced, the replace-
    ment is double-quoted.

EXPANSION
    Use "glob" to expand filenames.

BASH COMMAND SUBSTITUTION
   Command Substitution
       Command substitution allows the output of a command to replace  the  command  name.
       There are two forms:


              $(command)
       or
              `command`

       Bash  performs the expansion by executing command and replacing the command substi-
       tution with the standard output of the command, with any trailing newlines deleted.
       Embedded  newlines  are not deleted, but they may be removed during word splitting.
       The command substitution $(cat file) can be replaced by the equivalent  but  faster
       $(< file).

       When  the  old-style  backquote form of substitution is used, backslash retains its
       literal meaning except when followed by $, `, or \.  The first backquote  not  pre-
       ceded  by  a  backslash terminates the command substitution.  When using the $(com-
       mand) form, all characters between the parentheses make up the  command;  none  are
       treated specially.

       Command  substitutions  may  be  nested.   To  nest when using the backquoted form,
       escape the inner backquotes with backslashes.

       If the substitution appears within  double  quotes,  word  splitting  and  pathname
       expansion are not performed on the results.

BASH COMMAND SUBSTITUTION EXAMPLES

Administrator@loish ~
$ echo "$(which -a echo)"
/usr/bin/echo
/bin/echo
/usr/bin/echo

Administrator@loish ~
$ echo $(which -a echo)
/usr/bin/echo /bin/echo /usr/bin/echo

SUMMARY
TODO: UPDATE THIS $"..." and "..." not exactly accurate now [2009-02-23]
 '...' => literal (no escapes and no globbing within quotes)
 $'...' => ANSI C string escapes (\a, \b, \e, \f, \n, \r, \t, \v, \\, \', \n[0-9]{1,3}, \xh[0-9a-fA-F]{1,2}, \cx; all other \<x> =>\<x>)
 "..." => literal (no escapes but allows internal globbing) [differs from bash]
 $"..." => same as "..."
??? $"..." => modified bash escapes (for $, ", \ only) and $ expansion (?$() shell escapes), no `` shell escapes, note: \<x> => \<x> unless <x> = {$, ", or <NL>}


=end IMPLEMENTATION-NOTES

=begin FUTURE-DOCUMENTATION

TODO

Check VCC compilation. Currently, after vcvars.bat setup: 1) compilation proceeds to completion without error, 2) loading the .dll causes a GPF[ perl.exe - Unable to Locate Component == This application has failed to start because MSVCR90.dll was not found. Re-installing the application may fix this problem. ]

Note that a similar GPF occurs for 'test.exe' when test.exe.manifest is removed => [ perl.exe - Unable to Locate Component == This application has failed to start because MSVCR90.dll was not found. Re-installing the application may fix this problem. ]

[test.c]
int main(int argc, char **argv, char **env)
{
}
[test.exe.manifest]
<?xml version='1.0' encoding='UTF-8' standalone='yes'?>
<assembly xmlns='urn:schemas-microsoft-com:asm.v1' manifestVersion='1.0'>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level='asInvoker' uiAccess='false' />
      </requestedPrivileges>
    </security>
  </trustInfo>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity type='win32' name='Microsoft.VC90.CRT' version='9.0.21022.8' processorArchitecture='x86' publicKeyToken='1fc8b3b9a1e18e3b' />
    </dependentAssembly>
  </dependency>
</assembly>

SOLUTION (why needed? and is it fixed with later v of ActivePerl?)

** create perl.exe.manifest in same directory as perl.exe executable [c:\perl\bin]

[perl.exe.manifest]
<?xml version='1.0' encoding='UTF-8' standalone='yes'?>
<assembly xmlns='urn:schemas-microsoft-com:asm.v1' manifestVersion='1.0'>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level='asInvoker' uiAccess='false' />
      </requestedPrivileges>
    </security>
  </trustInfo>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity type='win32' name='Microsoft.VC90.CRT' version='9.0.21022.8' processorArchitecture='x86' publicKeyToken='1fc8b3b9a1e18e3b' />
    </dependentAssembly>
  </dependency>
</assembly>

=end FUTURE-DOCUMENTATION

=cut
