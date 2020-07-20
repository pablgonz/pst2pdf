#!/usr/bin/env perl
use v5.26;

# $Id: pst2pdf.pl 119 2014-09-24 12:04:09Z herbert $
# v. 0.19    2020-07-10 simplify the use of PSTricks with pdf
# (c) Herbert Voss <hvoss@tug.org>
#     Pablo González Luengo <pablgonz@yahoo.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the
# Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA  02111-1307  USA
#

use Getopt::Long qw(:config bundling_override); # read parameter and activate "bundling"
use File::Spec::Functions qw(catfile devnull);
use File::Basename;
use Archive::Tar;
use Data::Dumper;
use FileHandle;
use IO::Compress::Zip qw(:all);
use File::Path qw(remove_tree);
use File::Temp qw(tempdir);
use POSIX qw(strftime);
use File::Copy;
use File::Find;
use Env qw(PATH);
use autodie;
use Config;
use Cwd;
use if $^O eq 'MSWin32', 'Win32';
use if $^O eq 'MSWin32', 'Win32::Console::ANSI'; # need for color :)
use Term::ANSIColor;

### Internal vars
my $tempDir = tempdir( CLEANUP => 1); # temporary directory
my $workdir = cwd;      # current working dir
my $imgdir  = 'images'; # where to save the images
my $margins = '1';      # margins in pdfcrop
my $clear   = 0;        # 0 or 1, clears all temporary files
my $dpi     = '300';    # very low value for the png's
my $runs    = '1';      # set runs for compliler
my $nocorp  = 0;        # 1->no crop pdf files created
my $norun   = 0;        # 1->no create images
my $noprew  = 0;        # 1->create images in nopreview mode
my $runbibtex = 0;      # 1->runs bibtex
my $runbiber  = 0;      # 1->runs biber and sets $runbibtex=0
my $all = 0;            # 1->create all images and files for type
my $xetex  = 0;         # 1->Using (Xe)LaTeX for compilation.
my $luatex = 0;         # 1->Using dvilualatex for compilation.
my $latexmk = 0;        # 1->Using latexmk for compiler output file.
my $arara;              # 1->Using arara for compiler output file.
my $nosource = 0;       # Delete TeX source for images
my $srcenv;             # write only source code of environments
my $nopdf;              # Don't create a pdf image files
my $force;              # try to capture \psset
my $zip;                # compress files generated in .zip
my $tar;                # compress files generated in .tar.gz
my $help;               # help info
my $version;            # version info
my $license;            # license info
my $verbose = 0;        # verbose info
my @verb_env_tmp;       # save verbatim environments
my $myverb = 'myverb' ; # internal \myverb macro
my $gscmd;              # ghostscript executable name
my $gray;               # gray scale ghostscript
my $log      = 0;       # log file
my $outfile  = 0;       # write output file
my $PSTexa   = 0;       # run extract PSTexample environments
my $STDenv   = 0;       # run extract pspicture/psfrag environments
my %opts_cmd;           # hash to store Getopt::Long options

### Script identification
my $scriptname = 'pst2pdf';
my $nv         = 'v0.19';
my $ident      = '$Id: pst2pdf.pl 119 2020-07-15 12:04:09Z herbert $';

### Log vars
my $LogFile = "$scriptname.log";
my $LogWrite;
my $LogTime = strftime("%y/%m/%d %H:%M:%S", localtime);

### Error in command line
sub errorUsage {
    my $msg = shift;
    die color('red').'* Error!!: '.color('reset').$msg.
    " (run $scriptname --help for more information)\n";
    return;
}

### Extended error messages
sub exterr {
    chomp(my $msg_errno = $!);
    chomp(my $msg_extended_os_error = $^E);
    if ($msg_errno eq $msg_extended_os_error) {
        $msg_errno;
    }
    else {
        "$msg_errno/$msg_extended_os_error";
    }
}

### Funtion uniq
sub uniq {
    my %seen;
    return grep !$seen{$_}++, @_;
}

### Funtion array_minus
sub array_minus(\@\@) {
    my %e = map{ $_ => undef } @{$_[1]};
    return grep !exists $e{$_}, @{$_[0]};
}

### Funtion to create hash begin -> BEGIN, end -> END
sub crearhash {
    my %cambios;
    for my $aentra(@_){
        for my $initend (qw(begin end)) {
            $cambios{"\\$initend\{$aentra"} = "\\\U$initend\E\{$aentra";
        }
    }
    return %cambios;
}

### Print colored info in screen
sub Infocolor {
    my $type = shift;
    my $info = shift;
    if ($type eq 'Running') {
        print color('cyan'), '* ', color('reset'), color('green'),
        "$type: ", color('reset'), color('cyan'), "$info\r\n", color('reset');
    }
    if ($type eq 'Warning') {
        print color('bold red'), "* $type: ", color('reset'),
        color('yellow'), "$info\r\n", color('reset');
    }
    if ($type eq 'Finish') {
        print color('yellow'), '* ', color('reset'), color('bold red'),
        "$type!: ", color('reset'),  color('yellow'), "$info\r\n",color('reset');
    }
    return;
}

### Write Log line and print msg (common)
sub Infoline {
    my $msg = shift;
    my $now = strftime("%y/%m/%d %H:%M:%S", localtime);
    if ($log) { $LogWrite->print(sprintf "[%s] * %s\n", $now, $msg); }
    say $msg;
    return;
}

### Write Log line (no print msg and time stamp)
sub Logline {
    my $msg = shift;
    if ($log) { $LogWrite->print("$msg\n"); }
    return;
}

### Write Log line (time stamp)
sub Log {
    my $msg = shift;
    my $now = strftime("%y/%m/%d %H:%M:%S", localtime);
    if ($log) { $LogWrite->print(sprintf "[%s] * %s\n", $now, $msg); }
    return;
}

### Write array env in Log
sub Logarray {
    my ($env_ref) = @_;
    my @env_tmp = @{ $env_ref }; # dereferencing and copying each array
    if ($log) {
        if (@env_tmp) {
            my $tmp  = join "\n", map { qq/* $_/ } @env_tmp;
            print {$LogWrite} "$tmp\n";
        }
        else {
            print {$LogWrite} "Not found\n";
        }
    }
    return;
}

### Extended print info for execute system commands using $ command
sub Logrun {
    my $msg = shift;
    my $now = strftime("%y/%m/%d %H:%M:%S", localtime);
    if ($log) { $LogWrite->print(sprintf "[%s] \$ %s\n", $now, $msg); }
    return;
}

### Capture and execute system commands
sub RUNOSCMD {
    my $cmdname  = shift;
    my $argcmd   = shift;
    my $showmsg  = shift;
    my $captured = "$cmdname $argcmd";
    Logrun($captured);
    if ($showmsg eq 'show') {
        if ($verbose) {
            Infocolor('Running', $captured);
        }
        else{ Infocolor('Running', $cmdname); }
    }
    if ($showmsg eq 'only' and $verbose) {
        Infocolor('Running', $captured);
    }
    # Run system system command
    $captured = qx{$captured};
    if ($log) { $LogWrite->print($captured); }
    if ($? == -1) {
        my $errorlog    = "* Error!!: ".$cmdname." failed to execute (%s)!\n";
        my $errorprint  = "* Error!!: ".color('reset').$cmdname." failed to execute (%s)!\n";
        if ($log) { $LogWrite->print(sprintf $errorlog, exterr); }
        print STDERR color('red');
        die sprintf $errorprint, exterr;
    } elsif ($? & 127) {
        my $errorlog   = "* Error!!: ".$cmdname." died with signal %d!\n";
        my $errorprint = "* Error!!: ".color('reset').$cmdname." died with signal %d!\n";
        if ($log) { $LogWrite->print(sprintf $errorlog, ($? & 127)); }
        print STDERR color('red');
        die sprintf $errorprint, ($? & 127);
    } elsif ($? != 0 ) {
        my $errorlog = "* Error!!: ".$cmdname." exited with error code %d!\n";
        my $errorprint  = "* Error!!: ".color('reset').$cmdname." exited with error code %d!\n";
        if ($log) { $LogWrite->print(sprintf $errorlog, $? >> 8); }
        print STDERR color('red');
        die sprintf $errorprint, $? >> 8;
    }
    if ($verbose) { print $captured; }
    return;
}

### General information
my $copyright = <<'END_COPYRIGHT' ;
Copyright 2011-2020 (c) Herbert Voss <hvoss@tug.org> and Pablo González.
END_COPYRIGHT

my $licensetxt = <<'END_LICENSE';
  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.
END_LICENSE

my $versiontxt= <<"END_VERSION" ;
${scriptname} ${nv} ${ident}
${copyright}
END_VERSION

### Standart info in terminal
my $title = "$scriptname $nv $ident\n";

### Usage of script
sub usage ($) {
my $usage = <<"END_OF_USAGE";
${title}Usage: $scriptname <texfile.tex>  [Options]
pst2pdf run a TeX source, read all PS-related part and convert in images
    in pdf,eps,jpg,svg or png format (default pdf) and create new file
    whitout pst-environments and runs (pdf/Xe/lua)latex.
    See texdoc pst2pdf documentation for more info.
Options:
  -h,--help          - display this help and exit
  -l,--log           - creates a .log file
  -v,--version       - display version (current $nv) and exit
  -d,--dpi=<int>     - the dots per inch for images (default 300)
  -j,--jpg           - create .jpg files (need Ghostscript)
  -p,--png           - create .png files (need Ghostscript)
  -e,--eps           - create .eps files (need pdftops)
  -s,--svg           - create .svg files (need pdftocairo)
  -P,--ppm           - create .ppm files (need pdftoppm)
  -a,--all           - create .(pdf,eps,jpg,png,ppm,svg) images
  -c,--clear         - delete all temp and aux files
  -x,--xetex         - using (Xe)LaTeX for create images
  -m,--margins=<int> - margins for pdfcrop (in bp) (default 1)
  -ni,--noimages     - generate file-pdf.tex, but not images
  -np,--single       - create images files whitout preview pkg
  -ns,--nosource     - delete all source(.tex) for images files
  --imgdir=<string>  - the folder for the created images (default images)
  --ignore=<string>  - add other's verbatim environments (default other)
  --bibtex           - run bibtex on the aux file, if exists
  --biber            - run biber on the bcf file, if exists
  -V,--Verbose          - show extended information of process file

Examples:
* $scriptname test.tex -e -p -j -c --imgdir=pics
* produce test-pdf.tex whitout pstriks related parts and create image
* dir whit all images (pdf,eps,png,jpg) and source (.tex) for all pst
* environment in "./pics" dir using Ghostscript and cleaning all tmp files.
* Suport bundling for short options $scriptname test.tex -epjc --imgdir=pics
END_OF_USAGE
print $usage;
exit 0;
}

### Options in terminal
my $result=GetOptions (
    'h|help'             => \$help,     # flag
    'v|version'          => \$version,  # flag
    'l|log'              => \$log,      # flag
    'f|force'            => \$force,    # flag
    'd|dpi=i'            => \$dpi,      # numeric
    'runs=i'             => \$runs,     # numeric
    'm|margins=i'        => \$margins,  # numeric
    'imgdir=s'           => \$imgdir,   # string
    'ignore=s'           => \@verb_env_tmp, # string
    'c|clear'            => \$clear,    # flag
    'ni|noimages|norun'  => \$norun,    # flag
    'np|single|noprew'   => \$noprew,   # flag
    'bibtex'             => \$runbibtex,# flag
    'biber'              => \$runbiber, # flag
    'arara'              => \$arara,    # flag
    'latexmk'            => \$latexmk,  # flag
    'srcenv'             => \$srcenv,   # flag
    'nopdf'              => \$nopdf,    # flag
    'zip'                => \$zip,      # flag
    'tar'                => \$tar,      # flag
    'g|gray'             => \$gray,     # flag
    'b|bmp'              => \$opts_cmd{image}{bmp}, # gs
    't|tif'              => \$opts_cmd{image}{tif}, # gs
    'j|jpg'              => \$opts_cmd{image}{jpg}, # gs
    'p|png'              => \$opts_cmd{image}{png}, # gs
    's|svg'              => \$opts_cmd{image}{svg}, # pdftocairo
    'e|eps'              => \$opts_cmd{image}{eps}, # pdftops
    'P|ppm'              => \$opts_cmd{image}{ppm}, # pdftoppm
    'a|all'              => \$all,      # flag
    'x|xetex'            => \$xetex,    # flag
    'luatex'             => \$luatex,   # flag
    'ns|nosource'        => \$nosource, # flag
    'V|Verbose'          => \$verbose,  # flag
) or do { $log = 0 ; die usage(0); };

### Open log file
if ($log) {
    if (!defined $ARGV[0]) { errorUsage('Input filename missing'); }
    my $tempname = $ARGV[0];
    $tempname =~ s/\.(tex|ltx)$//;
    if ($LogFile eq "$tempname.log") { $LogFile = "$scriptname-log.log"; }
    $LogWrite  = FileHandle->new("> $LogFile");
}

### Init log file
Log("The script $scriptname $nv was started in $workdir");
Log("Creating the temporary directory $tempDir");

### Validate verbatim environments options from comand line
s/^\s*(\=):?|\s*//mg foreach @verb_env_tmp;
@verb_env_tmp = split /,/,join q{},@verb_env_tmp;
if (grep /(^\-|^\.).*?/, @verb_env_tmp) {
    Log('Error!!: Invalid argument for --ignore, some argument from list begin with -');
    errorUsage('Invalid argument for --ignore option');
}

### Make ENV safer, see perldoc perlsec
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

### The next code it's part of pdfcrop (adapted from TexLive 2014)
# Windows detection
my $Win = 0;
if ($^O =~ /mswin32/i) { $Win = 1; }

my $archname = $Config{'archname'};
$archname = 'unknown' unless defined $Config{'archname'};

# Get ghostscript command name
sub find_ghostscript () {
    if ($log) {
        Log('General information about the Perl instalation and operating system');
        print {$LogWrite} "* Perl executable: $^X\n";
        if ($] < 5.006) {
            print {$LogWrite} "* Perl version: $]\n";
        }
        else {
            printf {$LogWrite} "* Perl version: v%vd\n", $^V;
        }
        if (defined &ActivePerl::BUILD) {
            printf {$LogWrite} "* Perl product: ActivePerl, build %s\n", ActivePerl::BUILD();
        }
        printf {$LogWrite} "* Pointer size: $Config{'ptrsize'}\n";
        printf {$LogWrite} "* Pipe support: %s\n",
                (defined $Config{'d_pipe'} ? 'yes' : 'no');
        printf {$LogWrite} "* Fork support: %s\n",
                (defined $Config{'d_fork'} ? 'yes' : 'no');
    }
    my $system = 'unix';
    $system = 'win' if $^O =~ /mswin32/i;
    $system = 'msys' if $^O =~ /msys/i;
    $system = 'cygwin' if $^O =~ /cygwin/i;
    $system = 'miktex' if defined $ENV{'TEXSYSTEM'} and
                          $ENV{'TEXSYSTEM'} =~ /miktex/i;
    if ($log) {
        print {$LogWrite} "* OS name: $^O\n";
        print {$LogWrite} "* Arch name: $archname\n";
        if ($^O eq 'MSWin32') {
            my $tmp = Win32::GetOSName();
            print {$LogWrite} "* System: $tmp\n";
        }
        else { print {$LogWrite} "* System: $system\n"; }
    }
    Log('Trying to locate the executable for Ghostscript');
    my %candidates = (
        'unix'   => [qw|gs|],
        'win'    => [qw|gswin32c|],
        'msys'   => [qw|gswin64c gswin32c|],
        'cygwin' => [qw|gs|],
        'miktex' => [qw|mgs gswin32c|],
    );
    if ($system eq 'win' or $system eq 'miktex') {
        if ($archname =~ /mswin32-x64/i) {
            my @a = ();
            foreach my $name (@{$candidates{$system}}) {
                push @a, 'gswin64c' if $name eq 'gswin32c';
                push @a, $name;
            }
            $candidates{$system} = \@a;
        }
    }
    my %exe = (
        'unix'   => q{},
        'win'    => '.exe',
        'msys'   => '.exe',
        'cygwin' => '.exe',
        'miktex' => '.exe',
    );
    my $candidates_ref = $candidates{$system};
    my $exe = $Config{'_exe'};
    $exe = $exe{$system} unless defined $exe;
    my @path = File::Spec->path();
    my $found = 0;
    foreach my $candidate (@$candidates_ref) {
        foreach my $dir (@path) {
            my $file = File::Spec->catfile($dir, "$candidate$exe");
            if (-x $file) {
                $gscmd = $candidate;
                $found = 1;
                if ($log) { print {$LogWrite} "* Found ($candidate): $file\n"; }
                last;
            }
            if ($log) { print {$LogWrite} "* Not found ($candidate): $file\n"; }
        }
        last if $found;
    }
    if (not $found and $Win and $system ne 'msys') {
        $found = SearchRegistry();
    }
    if (not $found and $system eq 'msys') {
        $found = Searchbyregquery();
    }
    if ($found) {
        if ($log) { print {$LogWrite} "* Autodetected ghostscript command: $gscmd\n"; }
    }
    else {
        $gscmd = $$candidates_ref[0];
        if ($log) { print {$LogWrite} "* Default ghostscript command: $gscmd\n"; }
    }
}

sub SearchRegistry {
    my $found = 0;
    # The module Win32::TieRegistry not aviable in cygwin/msys
    eval 'use Win32::TieRegistry qw|KEY_READ REG_SZ|';
    if ($@) {
        if ($log) {
            print {$LogWrite} "* Registry lookup for Ghostscript failed:\n";
            my $msg = $@;
            $msg =~ s/\s+$//;
            foreach (split /\r?\n/, $msg) {
                print {$LogWrite} " $_\n";
            }
        }
        return $found;
    }
    my $open_params = {Access => KEY_READ(), Delimiter => q{/}};
    my $key_name_software = 'HKEY_LOCAL_MACHINE/SOFTWARE/';
    my $current_key = $key_name_software;
    my $software = new Win32::TieRegistry $current_key, $open_params;
    if (not $software) {
        if ($log) {
            print {$LogWrite} "* Cannot find or access registry key `$current_key'!\n";
        }
        return $found;
    }
    if ($log) { print {$LogWrite} "* Search registry at `$current_key'.\n"; }
    my %list;
    foreach my $key_name_gs (grep /Ghostscript/i, $software->SubKeyNames()) {
        $current_key = "$key_name_software$key_name_gs/";
        if ($log) { print {$LogWrite} "* Registry entry found: $current_key\n"; }
        my $key_gs = $software->Open($key_name_gs, $open_params);
        if (not $key_gs) {
            if ($log) { print {$LogWrite} "* Cannot open registry key `$current_key'!\n"; }
            next;
        }
        foreach my $key_name_version ($key_gs->SubKeyNames()) {
            $current_key = "$key_name_software$key_name_gs/$key_name_version/";
            if ($log) { print {$LogWrite} "* Registry entry found: $current_key\n"; }
            if (not $key_name_version =~ /^(\d+)\.(\d+)$/) {
                if ($log) { print {$LogWrite} "  The sub key is not a version number!\n"; }
                next;
            }
            my $version_main = $1;
            my $version_sub = $2;
            $current_key = "$key_name_software$key_name_gs/$key_name_version/";
            my $key_version = $key_gs->Open($key_name_version, $open_params);
            if (not $key_version) {
                if ($log) { print {$LogWrite} "* Cannot open registry key `$current_key'!\n"; }
                next;
            }
            $key_version->FixSzNulls(1);
            my ($value, $type) = $key_version->GetValue('GS_DLL');
            if ($value and $type == REG_SZ()) {
                if ($log) { print {$LogWrite} "  GS_DLL = $value\n"; }
                $value =~ s|([\\/])([^\\/]+\.dll)$|$1gswin32c.exe|i;
                my $value64 = $value;
                $value64 =~ s/gswin32c\.exe$/gswin64c.exe/;
                if ($archname =~ /mswin32-x64/i and -f $value64) {
                    $value = $value64;
                }
                if (-f $value) {
                    if ($log) { print {$LogWrite} "EXE found: $value\n"; }
                }
                else {
                    if ($log) { print {$LogWrite} "EXE not found!\n"; }
                    next;
                }
                my $sortkey = sprintf '%02d.%03d %s',
                        $version_main, $version_sub, $key_name_gs;
                $list{$sortkey} = $value;
            }
            else {
                if ($log) { print {$LogWrite} "Missing key `GS_DLL' with type `REG_SZ'!\n"; }
            }
        }
    }
    foreach my $entry (reverse sort keys %list) {
        $gscmd = $list{$entry};
        if ($log) { print {$LogWrite} "* Found (via registry): $gscmd\n"; }
        $found = 1;
        last;
    }
    return $found;
} # end GS search registry

### This part is only necessary if you're using Git on windows and don't
### have gs configured in the PATH. Git for windows don't have a Win32::TieRegistry
### and this module is not supported in the current versions.
sub Searchbyregquery {
    my $found = 0;
    my $gs_regkey;
    my $opt_reg = '//s //v';
    if ($log) { print {$LogWrite} "* Search Ghostscript in Windows registry under mingw/msys:\n";}
    $gs_regkey = qx{reg query "HKLM\\Software\\GPL Ghostscript" $opt_reg GS_DLL};
    if ($? == 0) {
        if ($log) { print {$LogWrite} "* Registry entry found for GS_DLL (64 bits version)\n";}
    }
    else {
        $gs_regkey = qx{reg query "HKLM\\Software\\Wow6432Node\\GPL Ghostscript" $opt_reg GS_DLL};
        if ($? == 0) {
            if ($log) { print {$LogWrite} "* Registry entry found for GS_DLL (32 bits version)\n";}
        }
    }
    my ($gs_find) = $gs_regkey =~ m/(?:\s* GS_DLL \s* REG_SZ \s*) (.+?)(?:\.dll.+?\R)/s;
    if ($gs_find) {
        my ($gs_vol, $gs_path, $gs_ver) = $gs_find =~ m/
                                                        (\w{1})(?:\:)   # volumen
                                                        (.+?)           # path to executable
                                                        (?:\\gsdll)     # LIB
                                                        (\d{2})         # Version
                                                      /xs;
        # Adjust
        $gs_vol = lc($gs_vol);
        $gs_path = '/'.$gs_vol.$gs_path;
        $gs_path =~ s|\\|/|gmsxi;
        # Add to PATH
        if ($log) { print {$LogWrite} "* Add $gs_path to PATH for current session\n"; }
        $PATH .= ":$gs_path";
        # Set executable
        $gscmd = 'gswin'.$gs_ver.'c';
        if ($log) { print {$LogWrite} "* Found (via reg query): $gscmd\n"; }
        $found = 1;
    }
    if ($@) {
        if ($log) {
            print {$LogWrite} "* Registry lookup for Ghostscript by reg query failed:\n";
            my $msg = $@;
            $msg =~ s/\s+$//;
            foreach (split /\r?\n/, $msg) {
                print {$LogWrite} " $_\n";
            }
        }
        return $found;
    }
    return $found;
}

### Call GS
find_ghostscript();

### Windows need suport space in path
if ($Win and $gscmd =~ /\s/) { $gscmd = "\"$gscmd\"";}

### Help
if (defined $help) {
    usage(1);
    exit 0;
}

### Version
if (defined $version) {
    #print $title;
    print $versiontxt;
    exit 0;
}

### Define key = pdf for image format
if (!$nopdf) {
    $opts_cmd{image}{pdf} = 1;
}

### Sore image formats in hash
my %format = (%{$opts_cmd{image}});
my $format = join q{, },grep { defined $format{$_} } keys %format;

if (!$norun) {
    Log("Defined image formats for creating: $format");
}

### Check <input file> from command line
@ARGV > 0 or errorUsage('Input filename missing');
@ARGV < 2 or errorUsage('Unknown option or too many input files');

### Check <input file> extention
my @SuffixList = ('.tex', '.ltx'); # valid extention
my ($name, $path, $ext) = fileparse($ARGV[0], @SuffixList);
if ($ext eq '.tex' or $ext eq '.ltx') {
    $ext = $ext;
}
else {
    errorUsage('Invalid or empty extention for input file');
}

### Read <input file> in memory
Log("Read input file $name$ext in memory");
open my $INPUTfile, '<:crlf', "$name$ext";
    my $ltxfile;
        {
            local $/;
            $ltxfile = <$INPUTfile>;
        }
close $INPUTfile;

### Set tmp random number for <name-fig-tmp>
my $tmp = int(rand(10000));

### Set wraped environments for extraction $wrapping
my $wrapping = "$scriptname$tmp";

### Identification message in terminal
print $title;

### Default environment to extract
my @extr_env_tmp;
my @extr_tmp = qw (
    postscript pspicture psgraph PSTexample
    );
push @extr_env_tmp, @extr_tmp;

### Default verbatim environment
my @verb_tmp = qw (
    Example CenterExample SideBySideExample PCenterExample PSideBySideExample
    verbatim Verbatim BVerbatim LVerbatim SaveVerbatim PSTcode
    LTXexample tcblisting spverbatim minted listing lstlisting
    alltt comment chklisting verbatimtab listingcont boxedverbatim
    demo sourcecode xcomment pygmented pyglist program programl
    programL programs programf programsc programt
    );
push @verb_env_tmp, @verb_tmp;

### Default verbatim write environment
my @verw_env_tmp;
my @verbw_tmp = qw (
    scontents filecontents tcboutputlisting tcbexternal tcbwritetmp extcolorbox extikzpicture
    VerbatimOut verbatimwrite filecontentsdef filecontentshere filecontentsdefmacro
    filecontentsdefstarred filecontentsgdef filecontentsdefmacro filecontentsgdefmacro
    );
push @verw_env_tmp, @verbw_tmp;

########################################################################
# One problem that can arise is the filecontents environment, this can #
# contain a complete document and be anywhere, before dividing we will #
# make some replacements for this and comment lines                    #
########################################################################

### Create a Regex for verbatim write environment
@verw_env_tmp = uniq(@verw_env_tmp);
my $tmpverbw = join q{|}, map { quotemeta } sort { length $a <=> length $b } @verw_env_tmp;
$tmpverbw = qr/$tmpverbw/x;
my $tmp_verbw = qr {
                     (
                       (?:
                         \\begin\{$tmpverbw\*?\}
                           (?:
                             (?>[^\\]+)|
                             \\
                             (?!begin\{$tmpverbw\*?\})
                             (?!end\{$tmpverbw\*?\})|
                             (?-1)
                           )*
                         \\end\{$tmpverbw\*?\}
                       )
                     )
                   }x;

### A pre-regex for comment lines
my $tmpcomment = qr/^ \s* \%+ .+? $ /mx;

### Hash for replace in verbatim's and comment lines
my %document = (
    '\begin{document}' => '\BEGIN{document}',
    '\end{document}'   => '\END{document}',
    '\documentclass'   => '\DOCUMENTCLASS',
    '\pagestyle{'      => '\PAGESTYLE{',
    '\thispagestyle{'  => '\THISPAGESTYLE{',
    );

### Changes in input file for verbatim write and comment lines
while ($ltxfile =~ / $tmp_verbw | $tmpcomment /pgmx) {
    my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my  $encontrado = ${^MATCH};
        while (my($busco, $cambio) = each %document) {
            $encontrado =~ s/\Q$busco\E/$cambio/g;
        }
        substr $ltxfile, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
        pos ($ltxfile) = $pos_inicial + length $encontrado;
}

### Now, split input file
my ($atbegindoc, $document) = $ltxfile =~ m/\A (\s* .*? \s*) (\\documentclass.*)\z/msx;

### Rules to capture for regex my $CORCHETES = qr/\[ [^]]*? \]/x;
my $braces      = qr/ (?:\{)(.+?)(?:\}) /msx;
my $braquet     = qr/ (?:\[)(.+?)(?:\]) /msx;
my $no_corchete = qr/ (?:\[ .*? \])?    /msx;

### Array for capture new verbatim environments defined in input file
my @new_verb = qw (
    newtcblisting DeclareTCBListing ProvideTCBListing NewTCBListing
    lstnewenvironment NewListingEnvironment NewProgram specialcomment
    includecomment DefineVerbatimEnvironment newverbatim newtabverbatim
    );

### Regex to capture names for new verbatim environments from input file
my $newverbenv = join q{|}, map { quotemeta} sort { length $a <=> length $b } @new_verb;
$newverbenv = qr/\b(?:$newverbenv) $no_corchete $braces/msx;

### Array for capture new verbatim write environments defined in input file
my @new_verb_write = qw (
    renewtcbexternalizetcolorbox renewtcbexternalizeenvironment
    newtcbexternalizeenvironment newtcbexternalizetcolorbox newenvsc
    );

### Regex to capture names for new verbatim write environments from input file
my $newverbwrt = join q{|}, map { quotemeta} sort { length $a <=> length $b } @new_verb_write;
$newverbwrt = qr/\b(?:$newverbwrt) $no_corchete $braces/msx;

### Regex to capture MINTED related environments
my $mintdenv  = qr/\\ newminted $braces (?:\{.+?\})      /x;
my $mintcenv  = qr/\\ newminted $braquet (?:\{.+?\})     /x;
my $mintdshrt = qr/\\ newmint $braces (?:\{.+?\})        /x;
my $mintcshrt = qr/\\ newmint $braquet (?:\{.+?\})       /x;
my $mintdline = qr/\\ newmintinline $braces (?:\{.+?\})  /x;
my $mintcline = qr/\\ newmintinline $braquet (?:\{.+?\}) /x;

### Filter input file, now $ltxfile is pass to $filecheck
Log("Filter $name$ext \(remove % and comments\)");
my @filecheck = $ltxfile;
s/%.*\n//mg foreach @filecheck;    # del comments
s/^\s*|\s*//mg foreach @filecheck; # del white space
my $filecheck = join q{}, @filecheck;

### Search verbatim and verbatim write environments <input file>
Log("Search verbatim and verbatim write environments in $name$ext");

### Search new verbatim write names in <input file>
my @newv_write = $filecheck =~ m/$newverbwrt/xg;
if (@newv_write) {
    Log("Found new verbatim write environments in $name$ext");
    Logarray(\@newv_write);
    push @verw_env_tmp, @newv_write;
}

### Search new verbatim environments in <input file> (for)
my @verb_input = $filecheck =~ m/$newverbenv/xg;
if (@verb_input) {
    Log("Found new verbatim environments in $name$ext");
    Logarray(\@verb_input);
    push @verb_env_tmp, @verb_input;
}

### Search \newminted{$mintdenv}{options} in <input file>, need add "code" (for)
my @mint_denv = $filecheck =~ m/$mintdenv/xg;
if (@mint_denv) {
    Log("Found \\newminted\{envname\} in $name$ext");
    # Append "code"
    $mintdenv  = join "\n", map { qq/$_\Qcode\E/ } @mint_denv;
    @mint_denv = split /\n/, $mintdenv;
    Logarray(\@mint_denv);
    push @verb_env_tmp, @mint_denv;
}

### Search \newminted[$mintcenv]{lang} in <input file> (for)
my @mint_cenv = $filecheck =~ m/$mintcenv/xg;
if (@mint_cenv) {
    Log("Found \\newminted\[envname\] in $name$ext");
    Logarray(\@mint_cenv);
    push @verb_env_tmp, @mint_cenv;
}

### Remove repetead again :)
@verb_env_tmp = uniq(@verb_env_tmp);

### Capture verbatim inline macros in input file
Log("Search verbatim macros in $name$ext");

### Store all minted inline/short in @mintline
my @mintline;

### Search \newmint{$mintdshrt}{options} in <input file> (while)
my @mint_dshrt = $filecheck =~ m/$mintdshrt/xg;
if (@mint_dshrt) {
    Log("Found \\newmint\{macroname\} (short) in $name$ext");
    Logarray(\@mint_dshrt);
    push @mintline, @mint_dshrt;
}

### Search \newmint[$mintcshrt]{lang}{options} in <input file> (while)
my @mint_cshrt = $filecheck =~ m/$mintcshrt/xg;
if (@mint_cshrt) {
    Log("Found \\newmint\[macroname\] (short) in $name$ext");
    Logarray(\@mint_cshrt);
    push @mintline, @mint_cshrt;
}

### Search \newmintinline{$mintdline}{options} in <input file> (while)
my @mint_dline = $filecheck =~ m/$mintdline/xg;
if (@mint_dline) {
    Log("Found \\newmintinline\{macroname\} in $name$ext");
    # Append "inline"
    $mintdline  = join "\n", map { qq/$_\Qinline\E/ } @mint_dline;
    @mint_dline = split /\n/, $mintdline;
    Logarray(\@mint_dline);
    push @mintline, @mint_dline;
}

### Search \newmintinline[$mintcline]{lang}{options} in <input file> (while)
my @mint_cline = $filecheck =~ m/$mintcline/xg;
if (@mint_cline) {
    Log("Found \\newmintinline\[macroname\] in $name$ext");
    Logarray(\@mint_cline);
    push @mintline, @mint_cline;
}

### Add standart mint, mintinline and lstinline
my @mint_tmp = qw(mint  mintinline lstinline);

### Join all inline verbatim macros captured
push @mintline, @mint_tmp;
@mintline = uniq(@mintline);

### Create a regex using @mintline
my $mintline = join q{|}, map { quotemeta } sort { length $a <=> length $b } @mintline;
$mintline = qr/\b(?:$mintline)/x;

### Reserved words in verbatim inline (while)
my %changes_in = (
    '%CleanPST'       => '%PSTCLEAN',
    '\psset'          => '\PSSET',
    '\pspicture'      => '\TRICKS',
    '\endpspicture'   => '\ENDTRICKS',
    '\psgraph'        => '\PSGRAPHTRICKS',
    '\endpsgraph'     => '\ENDPSGRAPHTRICKS',
    '\usepackage'     => '\USEPACKAGE',
    '{graphicx}'      => '{GRAPHICX}',
    '\graphicspath{'  => '\GRAPHICSPATH{',
    );

### Hash to replace \begin and \end in verbatim inline
my %init_end = (
    '\begin{' => '\BEGIN{',
    '\end{'   => '\END{',
    );

### Join changes in new hash (while) for verbatim inline
my %cambios = (%changes_in,%init_end);

### Variables and constantes
my $no_del = "\0";
my $del    = $no_del;

### Rules
my $llaves      = qr/\{ .+? \}                                                          /x;
my $no_llaves   = qr/(?: $llaves )?                                                     /x;
my $corchetes   = qr/\[ .+? \]                                                          /x;
my $delimitador = qr/\{ (?<del>.+?) \}                                                  /x;
my $scontents   = qr/Scontents [*]? $no_corchete                                        /ix;
my $verb        = qr/(?:((spv|(?:q|f)?v|V)erb|$myverb)[*]?)           /ix;
my $lst         = qr/(?:(lst|pyg)inline)(?!\*) $no_corchete                             /ix;
my $mint        = qr/(?: $mintline |SaveVerb) (?!\*) $no_corchete $no_llaves $llaves    /ix;
my $no_mint     = qr/(?: $mintline) (?!\*) $no_corchete                                 /ix;
my $marca       = qr/\\ (?:$verb | $lst |$scontents | $mint |$no_mint) (?:\s*)? (\S) .+? \g{-1}     /sx;
my $comentario  = qr/^ \s* \%+ .+? $                                                    /mx;
my $definedel   = qr/\\ (?: DefineShortVerb | lstMakeShortInline| MakeSpecialShortVerb ) [*]? $no_corchete $delimitador /ix;
my $indefinedel = qr/\\ (?: (Undefine|Delete)ShortVerb | lstDeleteShortInline) $llaves  /ix;

Log('Making changes to inline/multiline verbatim macro before extraction');

### Changes in input file for verbatim inline/multiline
while ($document =~
        / $marca
        | $comentario
        | $definedel
        | $indefinedel
        | $del .+? $del
        /pgmx) {
    my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my  $encontrado = ${^MATCH};
    if ($encontrado =~ /$definedel/) {
        $del = $+{del};
        $del = "\Q$+{del}" if substr($del,0,1) ne '\\';
    }
    elsif ($encontrado =~ /$indefinedel/) {
        $del = $no_del;
    }
    else {
        while (my($busco, $cambio) = each %cambios) {
            $encontrado =~ s/\Q$busco\E/$cambio/g;
        }
        substr $document, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
        pos ($document) = $pos_inicial + length $encontrado;
    }
}

### Change "escaped braces" to <LTXSB.> (this label is not the one in the document)
$document =~ s/\\[{]/<LTXSBO>/g;
$document =~ s/\\[}]/<LTXSBC>/g;

### Regex for verbatim inline/multiline whit braces {...}
my $nestedbr   = qr /   ( [{] (?: [^{}]++ | (?-1) )*+ [}]  )                      /x;
my $fvextra    = qr /\\ (?: (Save|Esc)Verb [*]?) $no_corchete                     /x;
my $mintedbr   = qr /\\ (?:$mintline|pygment) (?!\*) $no_corchete $no_llaves      /x;
my $tcbxverb   = qr /\\ (?: tcboxverb [*]?| Scontents [*]? |$myverb [*]?|lstinline) $no_corchete /x;
my $verb_brace = qr /   (?:$tcbxverb|$mintedbr|$fvextra) (?:\s*)? $nestedbr       /x;

### Change \verb*{code} for verbatim inline/multiline
while ($document =~ /$verb_brace/pgmx) {
    my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my  $encontrado = ${^MATCH};
    while (my($busco, $cambio) = each %cambios) {
        $encontrado =~ s/\Q$busco\E/$cambio/g;
    }
    substr $document, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
    pos ($document) = $pos_inicial + length $encontrado;
}

### We recovered the escaped braces
$document =~ s/<LTXSBO>/\\{/g;
$document =~ s/<LTXSBC>/\\}/g;

### We recovered CleanPST in all file, but only at begin of line
$document =~ s/^%PSTCLEAN/%CleanPST/gmsx;

### First we do some security checks to ensure that they are verbatim and
### verbatim write environments are unique and disjointed
@verb_env_tmp = array_minus(@verb_env_tmp, @verw_env_tmp); #disjointed
my @verbatim = uniq(@verb_env_tmp);

Log('The environments that are considered verbatim:');
Logarray(\@verbatim);

### Create a Regex for verbatim standart environment
my $verbatim = join q{|}, map { quotemeta } sort { length $a <=> length $b } @verbatim;
$verbatim = qr/$verbatim/x;
my $verb_std = qr {
                    (
                      (?:
                        \\begin\{$verbatim\*?\}
                          (?:
                            (?>[^\\]+)|
                            \\
                            (?!begin\{$verbatim\*?\})
                            (?!end\{$verbatim\*?\})|
                            (?-1)
                          )*
                        \\end\{$verbatim\*?\}
                      )
                    )
                  }x;

### Verbatim write
@verw_env_tmp = array_minus(@verw_env_tmp, @verb_env_tmp); #disjointed
my @verbatim_w = uniq(@verw_env_tmp);

Log('The environments that are considered verbatim write:');
Logarray(\@verbatim_w);

### Create a Regex for verbatim write environment
my $verbatim_w = join q{|}, map { quotemeta } sort { length $a <=> length $b } @verbatim_w;
$verbatim_w = qr/$verbatim_w/x;
my $verb_wrt = qr {
                    (
                      (?:
                        \\begin\{$verbatim_w\*?\}
                          (?:
                            (?>[^\\]+)|
                            \\
                            (?!begin\{$verbatim_w\*?\})
                            (?!end\{$verbatim_w\*?\})|
                            (?-1)
                          )*
                        \\end\{$verbatim_w\*?\}
                      )
                    )
                  }x;

### An array with all environments to extract
my @extract_env = qw(preview nopreview);
push @extract_env,@extr_env_tmp;
my %extract_env = crearhash(@extract_env);

Log('The environments that will be searched for extraction:');
my @real_extract_env = grep !/nopreview/, @extract_env;
Logarray(\@real_extract_env);

### Create a regex to extract environments @extr_env_tmp; @extract_env;
my $environ = join q{|}, map { quotemeta } sort { length $a <=> length $b } @extr_env_tmp;
$environ = qr/$environ/x;
my $extr_tmp = qr {
                    (
                      (?:
                        \\begin\{$environ\*?\}
                          (?:
                            (?>[^\\]+)|
                            \\
                            (?!begin\{$environ\*?\})
                            (?!end\{$environ\*?\})|
                            (?-1)
                          )*
                        \\end\{$environ\*?\}
                      )
                    )
                  }x;

Log('Making changes to verbatim/verbatim write environments before extraction');

### Hash and Regex for changes, this "regex" is re-used in ALL script
my %replace = (%extract_env, %changes_in, %document);
my $find    = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %replace;

### We go line by line and make the changes (/p for ${^MATCH})
while ($document =~ /$verb_wrt | $verb_std /pgmx) {
    my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my $encontrado = ${^MATCH};
    $encontrado =~ s/($find)/$replace{$1}/g;
    substr $document, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
    pos ($document) = $pos_inicial + length $encontrado;
}

### Now match preview environment
my @env_preview = $document =~ m/\\begin\{PSTexample\}.+?\\end\{PSTexample\}(*SKIP)(*F)|
                                (\\begin\{preview\}.+?\\end\{preview\})/gmsx;

### Convert preview environment
if (@env_preview) {
    my $preNo = scalar @env_preview;
    Log("Found $preNo preview environments in $name$ext");
    Log("Pass all preview environments to \\begin{nopreview}\%TMP$tmp ... \\end{nopreview}\%TMP$tmp");
    $document =~ s/\\begin\{PSTexample\}.+?\\end\{PSTexample\}(*SKIP)(*F)|
                  (?:(\\begin\{|\\end\{))(preview\})/$1no$2\%TMP$tmp/gmsx;
}

### Internal dtxtag mark for verbatim environments
my $dtxverb = "verbatim$tmp";

Log("Pass verbatim write environments to %<*$dtxverb> ... %</$dtxverb>");
$document  =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
               \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
               ($verb_wrt)/\%<\*$dtxverb>$1\%<\/$dtxverb>/gmsx;

Log("Pass verbatim environments to %<*$dtxverb> ... %</$dtxverb>");
$document  =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
               \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
               ($verb_std)/\%<\*$dtxverb>$1\%<\/$dtxverb>/gmsx;

Log("Pass %CleanPST ... %CleanPST to %<*remove$tmp> ... %</remove$tmp>");
$document =~ s/\%<\*$dtxverb> .+?\%<\/$dtxverb>(*SKIP)(*F)|
              ^(?:%CleanPST) (.+?) (?:%CleanPST)/\%<\*remove$tmp>$1\%<\/remove$tmp>/gmsx;

### Check plain TeX syntax [skip PSTexample]
Log('Convert plain \pspicture to LaTeX syntax');
$document =~ s/\%<\*$dtxverb> .+?\%<\/$dtxverb>(*SKIP)(*F)|
              \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
              \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
              \\begin\{PSTexample\}.+?\\end\{PSTexample\}(*SKIP)(*F)|
              \\pspicture(\*)?(.+?)\\endpspicture/\\begin\{pspicture$1\}$2\\end\{pspicture$1\}/gmsx;
Log('Convert plain \psgraph to LaTeX syntax');
$document =~ s/\%<\*$dtxverb> .+?\%<\/$dtxverb>(*SKIP)(*F)|
              \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
              \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
              \\begin\{PSTexample\}.+?\\end\{PSTexample\}(*SKIP)(*F)|
              \\psgraph(\*)?(.+?)\\endpsgraph/\\begin\{psgraph$1\}$2\\end\{psgraph$1\}/gmsx;

### Force mode for pstricks/psgraph
if ($force) {
    Log('Capture \psset{...} for pstricks environments [force mode]');
    $document =~ s/\%<\*$dtxverb> .+?\%<\/$dtxverb>(*SKIP)(*F)|
                  \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
                  \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
                  \\begin\{PSTexample\}.+?\\end\{PSTexample\}(*SKIP)(*F)|
                  \\begin\{postscript\}.+?\\end\{postscript\}(*SKIP)(*F)|
                  (?<code>
                     (?:\\psset\{(?:\{.*?\}|[^\{])*\}.+?)?  # if exist ...save
                     \\begin\{(?<env> pspicture\*?| psgraph)\} .+? \\end\{\k<env>\}
                  )
                /\\begin\{$wrapping\}$+{code}\\end\{$wrapping\}/gmsx;
}

Log("Pass all postscript environments to \\begin{$wrapping} ... \\end{$wrapping}");
$document =~ s/\\begin\{PSTexample\}.+?\\end\{PSTexample\}(*SKIP)(*F)|
               \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
              (?:\\begin\{postscript\})(?:\s*\[ [^]]*? \])?
                 (?<code>.+?)
                 (?:\\end\{postscript\})
              /\\begin\{$wrapping\}$+{code}\\end\{$wrapping\}/gmsx;

Log("Pass all pstricks environments to \\begin{$wrapping} ... \\end{$wrapping}");
$document =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
              \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
              \\begin\{$wrapping\}.+?\\end\{$wrapping\}(*SKIP)(*F)|
              ($extr_tmp)/\\begin\{$wrapping\}$1\\end\{$wrapping\}/gmsx;

########################################################################
#  All environments are now classified:                                #
#  Extraction       ->    \begin{preview} ... \end{preview}            #
#  Verbatim's       ->    %<\*$dtxverb> ... <\/$dtxverb>               #
########################################################################

### Now split document
my ($preamble,$bodydoc,$enddoc) = $document =~ m/\A (.+?) (\\begin\{document\} .+?)(\\end\{document\}.*)\z/msx;

### Hash for reverse changes for extract and output file
my %changes_out = (
    '\PSSET'            => '\psset',
    '\TIKZSET'          => '\tikzset',
    '\TRICKS'           => '\pspicture',
    '\ENDTRICKS'        => '\endpspicture',
    '\PSGRAPHTRICKS'    => '\psgraph',
    '\ENDPSGRAPHTRICKS' => '\endpsgraph',
    '\USEPACKAGE'       => '\usepackage',
    '{GRAPHICX}'        => '{graphicx}',
    '\GRAPHICSPATH{'    => '\graphicspath{',
    '\BEGIN{'           => '\begin{',
    '\END{'             => '\end{',
    '\DOCUMENTCLASS'    => '\documentclass',
    '\PAGESTYLE{'       => '\pagestyle{',
    '\THISPAGESTYLE{'   => '\thispagestyle{',
    '%PSTCLEAN'         => '%CleanPST',
    );

### We restore the changes in body of environments and dtxverb
%replace = (%changes_out);
$find    = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %replace;
$bodydoc  =~ s/($find)/$replace{$1}/g;
$preamble =~ s/($find)/$replace{$1}/g;

### First search PSTexample environment for extract
my $BE = '\\\\begin\{PSTexample\}';
my $EE = '\\\\end\{PSTexample\}';

my @exa_extract = $bodydoc =~ m/(?:\\begin\{$wrapping\})(\\begin\{PSTexample\}.+?\\end\{PSTexample\})/gmsx;
my $exaNo = scalar @exa_extract;

my $envEXA;
my $fileEXA;
if ($exaNo > 1) {
    $envEXA   = 'PSTexample environments';
    $fileEXA  = 'files';
}
else {
    $envEXA   = 'PSTexample environment';
    $fileEXA  = 'file';
}

### Check if PSTexample environment found
if ($exaNo!=0) {
    $PSTexa = 1;
    Log("Found $exaNo $envEXA in $name$ext");
    my $fig = 1;
    for my $item (@exa_extract) {
        Logline("%##### PSTexample environment captured number $fig ######%");
        Logline($item);
        $fig++;
    }
    # Add [graphic={[...]...}] to \begin{PSTexample}[...]
    Log('Append [graphic={[...]...}] to \begin{PSTexample}[...]');
    $exaNo = 1;
    while ($bodydoc =~ /\\begin\{$wrapping\}(\s*)?\\begin\{PSTexample\}(\[.+?\])?/gsm) {
        my $swpl_grap = "graphic=\{\[scale=1\]$imgdir/$name-fig-exa";
        my $corchetes = $1;
        my ($pos_inicial, $pos_final) = ($-[1], $+[1]);
        if (not $corchetes) { $pos_inicial = $pos_final = $+[0]; }
        if (not $corchetes  or  $corchetes =~ /\[\s*\]/) {
            $corchetes = "[$swpl_grap-$exaNo}]";
        }
        else { $corchetes =~ s/\]/,$swpl_grap-$exaNo}]/; }
        substr($bodydoc, $pos_inicial, $pos_final - $pos_inicial) = $corchetes;
        pos($bodydoc) = $pos_inicial + length $corchetes;
    }
    continue { $exaNo++; }
    Log('Pass PSTexample environments to \begin{nopreview} ... \end{nopreview}');
    $bodydoc =~ s/\\begin\{$wrapping\}
                    (?<code>\\begin\{PSTexample\} .+? \\end\{PSTexample\})
                  \\end\{$wrapping\}
                 /\\begin\{nopreview\}%$tmp$+{code}\\end\{nopreview\}%$tmp/gmsx;
}

### Reset exaNo
$exaNo = scalar @exa_extract;

my $BP = "\\\\begin\{$wrapping\}";
my $EP = "\\\\end\{$wrapping\}";

my @env_extract = $bodydoc =~ m/(\\begin\{$wrapping\}.+?\\end\{$wrapping\})/gmsx;
my $envNo = scalar @env_extract;

my $envSTD;
my $fileSTD;
if ($envNo > 1) {
    $envSTD   = 'pstricks environments';
    $fileSTD  = 'files';
}
else {
    $envSTD   = 'pstricks environment';
    $fileSTD  = 'file';
}

### Check if pstricks environments found
if ($envNo!=0) {
    $STDenv = 1;
    Log("Found $envNo $envSTD in $name$ext");
    my $fig = 1;
    for my $item (@env_extract) {
        Logline("%##### Environment pstricks captured number $fig ######%");
        Logline($item);
        $fig++;
    }
}

### Check if enviroment(s) found in input file
if ($envNo == 0 and $exaNo == 0) {
    errorUsage("$scriptname can not find any environment to extract in $name$ext");
}

#### Check --srcenv and --subenv option from command line
#if ($srcenv && $subenv) {
    #errorUsage('Options --srcenv and --subenv  are mutually exclusive');
#}

#### If --srcenv or --subenv option are OK then execute script
#if ($srcenv) {
    #$outsrc = 1;
    #$subenv = 0;
#}
#if ($subenv) {
    #$outsrc = 1;
    #$srcenv = 0;
#}

### Set directory to save generated files, need full path for goog log :)
my $imgdirpath = File::Spec->rel2abs($imgdir);

if (-e $imgdir) {
    Infoline("The generated files will be saved in $imgdirpath");
}
else {
    Infoline("Creating the directory $imgdirpath to save the generated files");
    Infocolor('Running', "mkdir $imgdirpath");
    Logline("[perl] mkdir($imgdir,0744)");
    mkdir $imgdir,0744 or errorUsage("Can't create the directory $imgdir");
}

### Set compiler for process <input file>
my $compiler = $xetex  ? 'xelatex'
             : $luatex ? 'dvilualatex'
             :           'latex'
             ;

### Set options for pdfcrop
my $opt_crop = $xetex ? "--xetex  --margins $margins"
             :          "--margins $margins"
             ;

### Set options for preview package
my $opt_prew = $xetex ? 'xetex,'
             :          q{}
             ;

### Set message in terminal
my $msg_compiler = $xetex ?  'xelatex'
                 : $luatex ? 'dvilualatex>dvips>ps2pdf'
                 :           'latex>dvips>ps2pdf'
                 ;

### Set write18 for compiler in TeXLive and MikTeX
my $write18 = '-shell-escape'; # TeXLive
$write18 = '-enable-write18' if defined $ENV{'TEXSYSTEM'} and $ENV{'TEXSYSTEM'} =~ /miktex/i;

### Set options for compiler
my $opt_compiler = "$write18 -interaction=nonstopmode -recorder";

if (!$norun) {
    Log("The options '$opt_compiler' will be passed to $compiler");
}

### Set -q for system command line (gs, poppler-utils, dvips)
my $quiet = $verbose ? q{}
          :            '-q'
          ;

### Set options for ghostscript
my %opt_gs_dev = (
    pdf  => '-dNOSAFER -dBATCH -dNOPAUSE -sDEVICE=pdfwrite',
    gray => '-dNOSAFER -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -sColorConversionStrategy=Gray -sProcessColorModel=DeviceGray',
    png  => "-dNOSAFER -dBATCH -dNOPAUSE -sDEVICE=pngalpha -r $dpi",
    bmp  => "-dNOSAFER -dBATCH -dNOPAUSE -sDEVICE=bmp32b -r $dpi",
    jpg  => "-dNOSAFER -dBATCH -dNOPAUSE -sDEVICE=jpeg -r $dpi -dJPEGQ=100 -dGraphicsAlphaBits=4 -dTextAlphaBits=4",
    tif  => "-dNOSAFER -dBATCH -dNOPAUSE -sDEVICE=tiff32nc -r $dpi",
    );

### Set poppler-utils executables
my %cmd_poppler = (
    eps => "pdftops",
    ppm => "pdftoppm",
    svg => "pdftocairo",
    );

### Set options for poppler-utils
my %opt_poppler = (
    eps => "$quiet -eps",
    ppm => "$quiet -r $dpi",
    svg => "$quiet -svg",
    );

### Copy preamble and body for temp file with all environments
my $atbeginout = $atbegindoc;
my $preamout   = $preamble;
my $tmpbodydoc = $bodydoc;

### Match \pagestyle and \thispagestyle in preamble
my $style_page = qr /(?:\\)(?:this)?(?:pagestyle\{) (.+?) (?:\})/x;
my @style_page = $preamout =~ m/\%<\*$dtxverb> .+?\%<\/$dtxverb>(*SKIP)(*F)| $style_page/gmsx;
my %style_page = map { $_ => 1 } @style_page; # anon hash

### Set \pagestyle{empty} for standalone files and process
if (@style_page) {
    if (!exists $style_page{empty}) {
        Log("Replacing page style for generated files");
        $preamout =~ s/\%<\*$dtxverb> .+?\%<\/$dtxverb>(*SKIP)(*F)|
                      (\\(this)?pagestyle)(?:\{.+?\})/$1\{empty\}/gmsx;
    }
}
else {
    Log('Add \pagestyle{empty} for generated files');
    $preamout = $preamout."\\pagestyle\{empty\}\n";
}

##### Remove wraped postscript environments (pst-pdf, auto-pst-pdf, auto-pst-pdf-lua)
#Log('Convert postscript environments to \begin{preview} ... \end{preview} for standalone files');
#$tmpbodydoc =~ s/(?:$BP)(?:\n\\begin\{postscript\})(?:\s*\[ [^]]*? \])?
                 #(?<code>.+?)
                 #(?:\\end\{postscript\}\n)
                 #(?:$EP)
               #/\\begin\{preview\}%$tmp$+{code}\\end\{preview\}%$tmp/gmsx;

### We created a preamble for the individual files
my $sub_prea = "$atbeginout$preamout".'\begin{document}';

### Revert changes
$sub_prea =~ s/\%<\*$dtxverb>\s*(.+?)\s*\%<\/$dtxverb>/$1/gmsx;
%replace  = (%changes_out);
$find     = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %replace;
$sub_prea =~ s/($find)/$replace{$1}/g;
$sub_prea =~ s/^(?:\%<\*remove$tmp>)(.+?)(?:\%<\/remove$tmp>)/%CleanPST$1%CleanPST/gmsx;

### Write standalone files for environments
if (!$nosource) {
    my $src_name = "$name-fig-";
    my $srcNo    = 1;
    if ($srcenv) {
        Log('Extract source code of all captured environments without preamble');
        if ($STDenv) {
            Log("Creating $envNo $fileSTD [$ext] with source code for $envSTD in $imgdirpath");
            print "Creating $envNo $fileSTD ", color('magenta'), "[$ext]",
            color('reset'), " with source code for $envSTD\r\n";
            while ($tmpbodydoc =~ m/$BP(?:\s*)?(?<env_src>.+?)(?:\s*)?$EP/gms) {
                open my $outexasrc, '>', "$imgdir/$src_name$srcNo$ext";
                    print {$outexasrc} $+{'env_src'};
                close $outexasrc;
            }
            continue { $srcNo++; }
        }
        if ($PSTexa) {
            Log("Creating $exaNo $fileEXA [$ext] with source code for $envEXA in $imgdirpath");
            print "Creating $exaNo $fileEXA ", color('magenta'), "[$ext]",
            color('reset'), " with source code for $envEXA\r\n";
            while ($tmpbodydoc =~ m/$BE\[.+?(?<pst_exa_name>$imgdir\/.+?-\d+)\}\]\s*(?<exa_src>.+?)\s*$EE/gms) {
                open my $outstdsrc, '>', "$+{'pst_exa_name'}$ext";
                    print {$outstdsrc} $+{'exa_src'};
                close $outstdsrc;
            }
        }
    }
    else {
        Log('Extract source code of all captured environments with preamble');
        if ($STDenv) {
            Log("Creating a $envNo standalone $fileSTD [$ext] whit source code and preamble for $envSTD in $imgdirpath");
            print "Creating a $envNo standalone $fileSTD ", color('magenta'), "[$ext]",
            color('reset'), " whit source code and preamble for $envSTD\r\n";
            while ($tmpbodydoc =~ m/$BP(?:\s*)?(?<env_src>.+?)(?:\s*)?$EP/gms) {
                open my $outstdfile, '>', "$imgdir/$src_name$srcNo$ext";
                    print {$outstdfile} "$sub_prea\n$+{'env_src'}\n\\end\{document\}";
                close $outstdfile;
            }
            continue { $srcNo++; }
        }
        if ($PSTexa) {
            Log("Creating a $exaNo standalone $fileEXA [$ext] whit source code and preamble for $envEXA in $imgdirpath");
            print "Creating a $exaNo standalone $fileEXA ", color('magenta'), "[$ext]",
            color('reset'), " whit source code and preamble for $envEXA\r\n";
            while ($tmpbodydoc =~ m/$BE\[.+?(?<pst_exa_name>$imgdir\/.+?-\d+)\}\]\s*(?<exa_src>.+?)\s*$EE/gms) {
                open my $outexafile, '>', "$+{'pst_exa_name'}$ext";
                    print {$outexafile} "$sub_prea\n$+{'exa_src'}\n\\end\{document\}";
                close $outexafile;
            }
        }
    }
}

### Store options for preview and pst-pdf (add at begin document)
my $previewpkg = <<"EXTRA";
\\PassOptionsToPackage\{inactive\}\{pst-pdf\}%
\\AtBeginDocument\{%
\\RequirePackage\[inactive\]\{pst-pdf\}%
\\newenvironment\{$wrapping\}[1][]\{\\ignorespaces\}\{\}%
\\RequirePackage\[${opt_prew}active,tightpage\]\{preview\}%
\\PreviewEnvironment\{$wrapping\}
\\renewcommand\\PreviewBbAdjust\{-60pt -60pt 60pt 60pt\}\}%
EXTRA

### Store options for pst-pdf (add at begin document)
my $pstpdfpkg = <<'EXTRA';
\PassOptionsToPackage{inactive}{pst-pdf}
\AtBeginDocument{%
\RequirePackage[inactive]{pst-pdf}}%
EXTRA

### Remove %<*$dtxverb> ... %</$dtxverb> in bodyout and preamout
$tmpbodydoc =~ s/\%<\*$dtxverb>\s*(.+?)\s*\%<\/$dtxverb>/$1/gmsx;
$preamout   =~ s/\%<\*$dtxverb>\s*(.+?)\s*\%<\/$dtxverb>/$1/gmsx;
$tmpbodydoc =~ s/\\begin\{nopreview\}\%$tmp
                    (?<code> .+?)
                  \\end\{nopreview\}\%$tmp
                /\\begin\{nopreview\}\n$+{code}\n\\end\{nopreview\}/gmsx;
$tmpbodydoc =~ s/\\begin\{$wrapping\}
                    (?<code>.+?)
                  \\end\{$wrapping\}
                /\\begin\{$wrapping\}\n$+{code}\n\\end\{$wrapping\}/gmsx;

### Reverse changes for temporary file with all env (no in -exa file)
$tmpbodydoc =~ s/($find)/$replace{$1}/g;
$tmpbodydoc =~ s/(\%TMP$tmp)//g;
$preamout   =~ s/($find)/$replace{$1}/g;
$preamout   =~ s/^(?:\%<\*remove$tmp>)(.+?)(?:\%<\/remove$tmp>)/%CleanPST$1%CleanPST/gmsx;
$atbeginout =~ s/($find)/$replace{$1}/g;

### We created a preamble for individual files with all environments
$sub_prea = $noprew ? "$atbeginout$pstpdfpkg$preamout".'\begin{document}'
          :           "$atbeginout$previewpkg$preamout"
          ;

### Create a one file whit "all" PSTexample environments extracted
if ($PSTexa) {
    @exa_extract = undef;
    Infoline("Creating $name-fig-exa-$tmp$ext whit $exaNo $envEXA extracted");
    Log("Adding packages to $name-fig-exa-$tmp$ext");
    Logline($pstpdfpkg);
    while ($tmpbodydoc =~ m/$BE\[.+? $imgdir\/.+?-\d+\}\](?<exa_src>.+?)$EE/gmsx ) { # search
        push @exa_extract, $+{'exa_src'}."\\newpage\n";
        open my $allexaenv, '>', "$name-fig-exa-$tmp$ext";
            print {$allexaenv} "$atbeginout$pstpdfpkg$preamout".'\begin{document}'."@exa_extract"."\\end\{document\}";
        close $allexaenv;
    }
    if ($norun) {
        Infoline("Moving and renaming $name-fig-exa-$tmp$ext");
        if ($verbose) {
            Infocolor('Running', "mv $workdir/$name-fig-exa-$tmp$ext $imgdirpath/$name-fig-exa-all$ext");
        }
        else {
            Infocolor('Running', "mv $name-fig-exa-$tmp$ext $imgdir/$name-fig-exa-all$ext");
        }
        Logline("[perl] move($workdir/$name-fig-exa-$tmp$ext, $imgdirpath/$name-fig-exa-all$ext)");
        move("$workdir/$name-fig-exa-$tmp$ext", "$imgdir/$name-fig-exa-all$ext")
        or die "* Error!!: Couldn't be renamed $name-fig-exa-$tmp$ext to $imgdir/$name-fig-exa-all$ext";
    }
}

### Remove \begin{PSTexample}[graphic={...}]
$tmpbodydoc =~ s/($BE)(?:\[graphic=\{\[scale=1\]$imgdir\/.+?-\d+\}\])/$1/gmsx;
$tmpbodydoc =~ s/($BE\[.+?)(?:,graphic=\{\[scale=1\]$imgdir\/.+?-\d+\})(\])/$1$2/gmsx;

### Create a one file whit "all" standard environments extracted
if ($STDenv) {
    if ($noprew) {
        Log("Creating $name-fig-$tmp$ext whit $envNo $envSTD extracted [no preview]");
        print "Creating $name-fig-$tmp$ext whit $envNo $envSTD extracted",
        color('magenta'), " [no preview]\r\n",color('reset');
    }
    else {
        Log("Creating $name-fig-$tmp$ext whit $envNo $envSTD extracted [preview]");
        print "Creating $name-fig-$tmp$ext whit $envNo $envSTD extracted",
        color('magenta'), " [preview]\r\n",color('reset');
    }
    open my $allstdenv, '>', "$name-fig-$tmp$ext";
        if ($noprew) {
            my @env_extract;
            while ($tmpbodydoc =~ m/(?:\\begin\{$wrapping\})(?<env_src>.+?)(?:\\end\{$wrapping\})/gms) {
                push @env_extract,$+{'env_src'}."\\newpage\n";
            }
            Log("Adding packages to $name-fig-$tmp$ext");
            Logline($pstpdfpkg);
            print {$allstdenv} $sub_prea."@env_extract"."\\end{document}";
        }
        else {
            Log("Adding packages to $name-fig-$tmp$ext");
            Logline($previewpkg);
            print {$allstdenv} $sub_prea.$tmpbodydoc."\n\\end{document}";

        }
    close $allstdenv;
    if ($norun) {
        Infoline("Moving and renaming $name-fig-$tmp$ext");
        if ($verbose) {
            Infocolor('Running', "mv $workdir/$name-fig-$tmp$ext $imgdirpath/$name-fig-all$ext");
        }
        else {
            Infocolor('Running', "mv $name-fig-$tmp$ext $imgdir/$name-fig-all$ext");
        }
        Logline("[perl] move($workdir/$name-fig-$tmp$ext, $imgdirpath/$name-fig-all$ext)");
        move("$workdir/$name-fig-$tmp$ext", "$imgdir/$name-fig-all$ext")
        or die "* Error!!: Couldn't be renamed $name-fig-$tmp$ext to $imgdir/$name-fig-all$ext";
    }
}

### Compiler and generate PDF files
if (!$norun) {
Log('Generate a PDF file with all captured environments');
my @compiler = (1..$runs);
opendir (my $DIR, $workdir);
    while (readdir $DIR) {
        if (/(?<name>$name-fig(-exa)?)(?<type>-$tmp$ext)/) {
            Log("Compiling the file $+{name}$+{type} using [$msg_compiler]");
            print "Compiling the file $+{name}$+{type} using ", color('magenta'), "[$msg_compiler]\r\n",color('reset');
            #RUNOSCMD("$compiler $opt_compiler","$+{name}$+{type}",'show');
            for (@compiler){
                RUNOSCMD("$compiler $opt_compiler","$+{name}$+{type}",'show');
            }
            # Compiling file using latex>dvips>ps2pdf
            if ($compiler eq 'latex' or $compiler eq 'dvilualatex') {
                RUNOSCMD("dvips $quiet -Ppdf", "-o $+{name}-$tmp.ps $+{name}-$tmp.dvi",'show');
                RUNOSCMD("ps2pdf -sPDFSETTINGS=prepress -sAutoRotatePages=None", "$+{name}-$tmp.ps  $+{name}-$tmp.pdf",'show');
            }
            # Moving and renaming tmp file(s) with source code
            Log("Move $+{name}$+{type} file whit all source for environments to $imgdirpath");
            Infoline("Moving and renaming $+{name}$+{type}");
            if ($verbose){
                Infocolor('Running', "mv $workdir/$+{name}$+{type} $imgdirpath/$+{name}-all$ext");
            }
            else {
                Infocolor('Running', "mv $+{name}$+{type} $imgdir/$+{name}-all$ext");
            }
            Logline("[perl] move($workdir/$+{name}$+{type}, $imgdirpath/$+{name}-all$ext)");
            move("$workdir/$+{name}$+{type}", "$imgdir/$+{name}-all$ext")
            or die "* Error!!: Couldn't be renamed $+{name}$+{type} to $imgdir/$+{name}-all$ext";
            # pdfcrop
            Infoline("Cropping the file $+{name}-$tmp.pdf");
            RUNOSCMD("pdfcrop $opt_crop", "$+{name}-$tmp.pdf $+{name}-$tmp.pdf",'show');
            # gray
            if ($gray) {
                Infoline("Creating the file $+{name}-all.pdf [gray] in $tempDir");
                RUNOSCMD("$gscmd $quiet $opt_gs_dev{gray} ","-o $tempDir/$+{name}-all.pdf $workdir/$+{name}-$tmp.pdf",'show');
            }
            else {
                Infoline("Creating the file $+{name}-all.pdf in $tempDir");
                if ($verbose){
                    Infocolor('Running', "mv $workdir/$+{name}-$tmp.pdf $tempDir/$+{name}-all.pdf");
                }
                else { Infocolor('Running', "mv $+{name}-$tmp.pdf $tempDir/$+{name}-all.pdf"); }
                # Renaming pdf file
                Logline("[perl] move($workdir/$+{name}-$tmp.pdf, $tempDir/$+{name}-all.pdf)");
                move("$workdir/$+{name}-$tmp.pdf", "$tempDir/$+{name}-all.pdf")
                or die "* Error!!: Couldn't be renamed $+{name}-$tmp.pdf to $tempDir/$+{name}-all.pdf";
            }
        }
    }
closedir $DIR;
}

### Create image formats in separate files
if (!$norun) {
    Log("Creating the image formats: $format, working on $tempDir");
    opendir(my $DIR, $tempDir);
        while (readdir $DIR) {
            # PDF/PNG/JPG/BMP/TIFF format suported by ghostscript
            if (/(?<name>$name-fig(-exa)?)(?<type>-all\.pdf)/) {
                for my $var (qw(pdf png jpg bmp tif)) {
                    if (defined $opts_cmd{image}{$var}) {
                        Log("Generating format [$var] from file $+{name}$+{type} in $imgdirpath using $gscmd");
                        print 'Generating format', color('blue'), " [$var] ", color('reset'),"from file $+{name}$+{type}\r\n";
                        RUNOSCMD("$gscmd $quiet $opt_gs_dev{$var} ", "-o $workdir/$imgdir/$+{name}-%1d.$var $tempDir/$+{name}$+{type}",'show');
                    }
                }
            }
            # EPS/PPM/SVG format suported by poppler-utils
            if (/(?<name>$name-fig-exa)(?<type>-all\.pdf)/) { # pst-exa package
                for my $var (qw(eps ppm svg)) {
                    if (defined $opts_cmd{image}{$var}) {
                        Log("Generating format [$var] from file $+{name}$+{type} in $imgdirpath using $cmd_poppler{$var}");
                        print 'Generating format', color('blue'), " [$var] ", color('reset'),"from file $+{name}$+{type}\r\n";
                        if (!$verbose){
                            Infocolor('Running', "$cmd_poppler{$var} $opt_poppler{$var}");
                        }
                        for (my $epsNo = 1; $epsNo <= $exaNo; $epsNo++) {
                            RUNOSCMD("$cmd_poppler{$var} $opt_poppler{$var}", "-f $epsNo -l $epsNo $tempDir/$+{name}$+{type} $workdir/$imgdir/$+{name}-$epsNo.$var",'only');
                        }
                    }
                }
            }
            if (/(?<name>$name-fig)(?<type>-all\.pdf)/) {
                for my $var (qw(eps ppm svg)) {
                    if (defined $opts_cmd{image}{$var}) {
                        Log("Generating format [$var] from file $+{name}$+{type} in $imgdirpath using $cmd_poppler{$var}");
                        print 'Generating format', color('blue'), " [$var] ", color('reset'),"from file $+{name}$+{type}\r\n";
                        if (!$verbose){
                            Infocolor('Running', "$cmd_poppler{$var} $opt_poppler{$var}");
                        }
                        for (my $epsNo = 1; $epsNo <= $envNo; $epsNo++) {
                            RUNOSCMD("$cmd_poppler{$var} $opt_poppler{$var}", "-f $epsNo -l $epsNo $tempDir/$+{name}$+{type} $workdir/$imgdir/$+{name}-$epsNo.$var",'only');
                        }
                    }
                }
            }
        } # close while
    closedir $DIR;
    # Renaming PPM image files
    if (defined $opts_cmd{image}{ppm}) {
        Log("Renaming [ppm] images in $imgdirpath");
        if ($verbose){
            print 'Renaming', color('blue'), " [ppm] ", color('reset'),"images in $imgdirpath\r\n";
        }
        opendir(my $DIR, $imgdir);
            while (readdir $DIR) {
                if (/(?<name>$name-fig(-exa)?-\d+\.ppm)(?<sep>-\d+)(?<ppm>\.ppm)/) {
                    if ($verbose){
                        Infocolor('Running', "mv $+{name}$+{sep}$+{ppm} $+{name}");
                    }
                    Logline("[perl] move($imgdirpath/$+{name}$+{sep}$+{ppm}, $imgdirpath/$+{name})");
                    move("$imgdir/$+{name}$+{sep}$+{ppm}", "$imgdir/$+{name}")
                    or die "* Error!!: Couldn't be renamed $+{name}$+{sep}$+{ppm} to $+{name}";
                }
            }
        closedir $DIR;
    }
} # close run

### Constant
my $USEPACK   = quotemeta'\usepackage';
my $CORCHETES = qr/\[ [^]]*? \]/x;
my $findgraphicx = 'true';

### Suport for pst-exa package
my $pstexa = qr/(?:\\ usepackage) \[\s*(.+?)\s*\] (?:\{\s*(pst-exa)\s*\} ) /x;
my @pst_exa;
my %pst_exa;

### Possible packages that load graphicx
my @pkgcandidates = qw (
    rotating epsfig lyluatex xunicode parsa xepersian-hm gregoriotex teixmlslides
    teixml fotex hvfloat pgfplots grfpaste gmbase hep-paper postage schulealt
    schule utfsym cachepic abc doclicense rotating epsfig semtrans mgltex
    graphviz revquantum mpostinl cmpj cmpj2 cmpj3 chemschemex register papercdcase
    flipbook wallpaper asyprocess draftwatermark rutitlepage dccpaper-base
    nbwp-manual mandi fmp toptesi isorot pinlabel cmll graphicx-psmin ptmxcomp
    countriesofeurope iodhbwm-templates fgruler combinedgraphics pax pdfpagediff
    psfragx epsdice perfectcut upmethodology-fmt ftc-notebook tabvar vtable
    teubner pas-cv gcard table-fct pdfpages keyfloat pdfscreen showexpl simplecd
    ifmslide grffile reflectgraphics markdown bclogo tikz-page pst-uml realboxes
    musikui csbulobalka lwarp mathtools sympytex mpgraphics miniplot.sty:77
    dottex pdftricks2 feupphdteses tex4ebook axodraw2 hagenberg-thesis dlfltxb
    hu-berlin-bundle draftfigure quicktype endofproofwd euflag othelloboard
    pdftricks unswcover breqn pdfswitch latex-make figlatex repltext etsvthor
    cyber xcookybooky xfrac mercatormap chs-physics-report tikzscale ditaa
    pst-poker gmp CJKvert asypictureb hletter tikz-network powerdot-fuberlin
    skeyval gnuplottex plantslabels fancytooltips ieeepes pst-vectorian
    phfnote overpic xtuformat stubs graphbox ucs pdfwin metalogo mwe
    inline-images asymptote UNAMThesis authorarchive amscdx pst-pdf adjustbox
    trimclip fixmetodonotes incgraph scanpages pst-layout alertmessage
    svg quiz2socrative realhats autopdf egplot decorule figsize tikzexternal
    pgfcore frontespizio textglos graphicx tikz tcolorbox pst-exa
    );

my $pkgcandidates = join q{|}, map { quotemeta } sort { length $a <=> length $b } @pkgcandidates;
$pkgcandidates = qr/$pkgcandidates/x;
my @graphicxpkg;

### \graphicspath
my $graphicspath= qr/\\ graphicspath \{ ((?: $llaves )+) \}/ix;
my @graphicspath;

### Replacing the extracted environments with \\includegraphics
Log("Convert pstricks extracted environments to \\includegraphics for $name-pdf$ext");
my $grap  =  "\\includegraphics[scale=1]{$name-fig-";
my $close =  '}';
my $imgNo =  1;
$bodydoc  =~ s/$BP.+?$EP/$grap@{[$imgNo++]}$close/msg;

### Add $atbegindoc to $preamble
$preamble = "$atbegindoc$preamble";

### Remove content in preamble
my @tag_remove_preamble = $preamble =~ m/(?:^\%<\*remove$tmp>.+?\%<\/remove$tmp>)/gmsx;
if (@tag_remove_preamble) {
    Log("Removing the content between <*remove> ... </remove> tags in preamble for $name-pdf$ext");
    $preamble =~ s/^\%<\*remove$tmp>\s*(.+?)\s*\%<\/remove$tmp>(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
}

### To be sure that the package is in the main document and not in a
### verbatim write environment we make the changes using the hash and
### range operator in a copy
my %tmpreplace = (
    'graphicx'     => 'TMPGRAPHICXTMP',
    'pst-exa'      => 'TMPPSTEXATMP',
    'graphicspath' => 'TMPGRAPHICSPATHTMP',
);

my $findtmp     = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %tmpreplace;
my $preambletmp = $preamble;
my @lineas = split /\n/, $preambletmp;

### We remove the commented lines
s/\%.*(?:[\t ]*(?:\r?\n|\r))?+//msg foreach @lineas;

### We make the changes in the environments verbatim write
my $DEL;
for (@lineas) {
    if (/\\begin\{($verbatim_w\*?)(?{ $DEL = "\Q$^N" })\}/ .. /\\end\{$DEL\}/) {
        s/($findtmp)/$tmpreplace{$1}/g;
    }
}

### Join lines in $preambletmp
$preambletmp = join "\n", @lineas;

### We removed the blank lines
$preambletmp =~ s/^(?:[\t ]*(?:\r?\n|\r))?+//gmsx;

### Now we're trying to capture
@graphicxpkg = $preambletmp =~ m/($pkgcandidates)/gmsx;
if (@graphicxpkg) {
    Log("Found graphicx package in preamble for $name-pdf$ext");
    $findgraphicx = 'false';
}

### Second search graphicspath
@graphicspath = $preambletmp =~ m/graphicspath/msx;
if (@graphicspath) {
    Log("Found \\graphicspath in preamble for $name-pdf$ext");
    $findgraphicx = 'false';
    while ($preamble =~ /$graphicspath /pgmx) {
        my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
        my $encontrado = ${^MATCH};
        if ($encontrado =~ /$graphicspath/) {
            my  $argumento = $1;
            if ($argumento !~ /\{$imgdir\/\}/) {
                $argumento .= "\{$imgdir/\}";
                my  $cambio = "\\graphicspath{$argumento}";
                substr $preamble, $pos_inicial, $pos_final-$pos_inicial, $cambio;
                pos($preamble) = $pos_inicial + length $cambio;
            }
        }
    }
}

### Third search pst-exa
@pst_exa  = $preambletmp =~ m/\%<\*$dtxverb> .+?\%<\/$dtxverb>(*SKIP)(*F)|$pstexa/xg;
%pst_exa = map { $_ => 1 } @pst_exa;
if (@pst_exa) {
    Log("Comment pst-exa package in preamble for $name-pdf$ext");
    $findgraphicx = 'false';
    $preamble =~ s/(\\usepackage\[)\s*(swpl|tcb)\s*(\]\{pst-exa\})/\%$1$2,pdf$3/msxg;
}
if (exists $pst_exa{tcb}) {
    Log("Suport for \\usepackage[tcb,pdf]\{pst-exa\} for $name-pdf$ext");
    $bodydoc =~ s/(graphic=\{)\[(scale=\d*)\]($imgdir\/$name-fig-exa-\d*)\}/$1$2\}\{$3\}/gsmx;
}

### Try to capture arara:compiler in preamble of <input file>
my @arara_engines = qw (latex pdflatex lualatex xelatex luahbtex);
my $arara_engines = join q{|}, map { quotemeta} sort { length $a <=> length $b } @arara_engines;
$arara_engines = qr/\b(?:$arara_engines)/x;
my $arara_rule = qr /^(?:\%\s{1}arara[:]\s{1}) ($arara_engines) /msx;

### Capture graphicx.sty in .log of LaTeX file
if ($findgraphicx eq 'true') {
    Log("Couldn't capture the graphicx package for $name-pdf$ext in preamble");
    my $ltxlog;
    my @graphicx;
    my $null = devnull();
    Log("Creating $name-fig-$tmp$ext [only preamble]");
    if ($verbose) { say "Creating [$name-fig-$tmp$ext] with only preamble"; }
    open my $OUTfile, '>', "$name-fig-$tmp$ext";
        print {$OUTfile} "$preamble\n\\stop";
    close $OUTfile;
    # Set compiler
    if ($opts_cmd{compiler}{arara}) {
        my @engine = $preamble =~ m/$arara_rule/msx;
        my %engine = map { $_ => 1 } @engine;
        if (%engine) {
            for my $var (@arara_engines) {
                if (defined $engine{$var}) {
                    $compiler = $var;
                }
            }
        }
        else { $compiler = 'pdflatex'; }
    }
    if ($compiler eq 'latex') { $compiler = 'pdflatex'; }
    if ($compiler eq 'dvilualatex') { $compiler = 'lualatex'; }
    # Compiling file
    RUNOSCMD("$compiler $write18 -interaction=batchmode", "$name-fig-$tmp$ext >$null", 'only');
    # Restore arara compiler
    if ($arara) { $compiler = 'arara'; }
    Log("Search graphicx package in $name-fig-$tmp.log");
    open my $LaTeXlog, '<', "$name-fig-$tmp.log";
        {
            local $/;
            $ltxlog = <$LaTeXlog>;
        }
    close $LaTeXlog;
    # Try to capture graphicx
    @graphicx = $ltxlog =~ m/.+? (graphicx\.sty)/xg;
    if (@graphicx) {
        Log("Found graphicx package in $name-fig-$tmp.log");
    }
    else {
        Log("Not found graphicx package in $name-fig-$tmp.log");
        Log("Add \\usepackage\{graphicx\} to preamble of $name-pdf$ext");
        $preamble= "$preamble\n\\usepackage\{graphicx\}";
    }
}

### Regex for clean (pst-?) in preamble
my $PALABRAS = qr/\b (?: pst-\w+ | pstricks (?: -add | -pdf )? | psfrag |psgo |vaucanson-g| auto-pst-pdf(?: -lua )? )/x;
my $FAMILIA  = qr/\{ \s* $PALABRAS (?: \s* [,] \s* $PALABRAS )* \s* \}(\%*)?/x;

Log("Remove pstricks packages in preamble for $name-pdf$ext");
$preamble =~ s/\%<\*$dtxverb> .+?\%<\/$dtxverb>(*SKIP)(*F)|
               ^ $USEPACK (?: $CORCHETES )? $FAMILIA \s*//msxg;
$preamble =~ s/\%<\*$dtxverb> .+?\%<\/$dtxverb>(*SKIP)(*F)|
               (?: ^ $USEPACK \{ | \G) [^}]*? \K (,?) \s* $PALABRAS (\s*) (,?) /$1 and $3 ? ',' : $1 ? $2 : ''/gemsx;
$preamble =~ s/\%<\*$dtxverb> .+?\%<\/$dtxverb>(*SKIP)(*F)|
               \\psset\{(?:\{.*?\}|[^\{])*\}(?:[\t ]*(?:\r?\n|\r))+//gmsx;
$preamble =~ s/\%<\*$dtxverb> .+?\%<\/$dtxverb>(*SKIP)(*F)|
               \\SpecialCoor(?:[\t ]*(?:\r?\n|\r))+//gmsx;
$preamble =~ s/^\\usepackage\{\}(?:[\t ]*(?:\r?\n|\r))+/\n/gmsx;

if (@pst_exa) {
    Log("Uncomment pst-exa package in preamble for $name-pdf$ext");
    $preamble =~ s/(?:\%)(\\usepackage\[\s*)(swpl|tcb)(,pdf\s*\]\{pst-exa\})/$1$2$3/msxg;
}

### Add last lines
if (!@graphicspath) {
    Log("Not found \\graphicspath in preamble for $name-pdf$ext");
    Log("Add \\graphicspath\{\{$imgdir/\}\} to preamble for $name-pdf$ext");
    $preamble= "$preamble\n\\graphicspath\{\{$imgdir/\}\}";
}
Log("Add \\usepackage\{grfext\} to preamble for $name-pdf$ext");
$preamble = "$preamble\n\\usepackage\{grfext\}";
Log("Add \\PrependGraphicsExtensions\*\{\.pdf\} to preamble for $name-pdf$ext");
$preamble = "$preamble\n\\PrependGraphicsExtensions\*\{\.pdf\}";
$preamble =~ s/\%<\*$dtxverb>\s*(.+?)\s*\%<\/$dtxverb>/$1/gmsx;
$preamble =~ s/^\\usepackage\{\}(?:[\t ]*(?:\r?\n|\r))+/\n/gmsx;
$preamble =~ s/^(?:[\t ]*(?:\r?\n|\r))?+//gmsx;

### Create a <output file>
my $out_file = "$preamble\n$bodydoc\n$enddoc";

### Clean \psset content in output file
$out_file =~ s/\\begin\{nopreview\}\%$tmp.+?\\end\{nopreview\}\%$tmp(*SKIP)(*F)|
               \%<\*$dtxverb> .+? \%<\/$dtxverb>(*SKIP)(*F)|
               \\psset\{(?:\{.*?\}|[^\{])*\}(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
$out_file =~ s/\\begin\{nopreview\}\%TMP$tmp\s*(.+?)\s*\\end\{nopreview\}\%TMP$tmp/$1/gmsx;

$out_file =~ s/\\begin\{nopreview\}%$tmp
               (?<code>\\begin\{PSTexample\} .+? \\end\{PSTexample\})
               \\end\{nopreview\}%$tmp
              /$+{code}/gmsx;

### Remove internal mark for verbatim and verbatim write environments
$out_file =~ s/\%<\*$dtxverb>\s*(.+?)\s*\%<\/$dtxverb>/$1/gmsx;
%replace  = (%changes_out);
$find     = join q{|}, map {quotemeta} sort { length $a <=> length $b } keys %replace;
$out_file =~ s/($find)/$replace{$1}/g;

### Write <output file>
if (-e "$name-pdf$ext") {
    Log("Rewriting the file $name-pdf$ext in $workdir");
    Infocolor('Warning', "The file [$name-pdf$ext] already exists and will be rewritten");
}
else{
    Infoline("Creating the file $name-pdf$ext");
    Log("Write the file $name-pdf$ext in $workdir");
}
open my $OUTfile, '>', "$name-pdf$ext";
    print {$OUTfile} $out_file;
close $OUTfile;

### Process <output file>
if (!$norun) {
    if ($compiler eq 'latex') {
        $compiler     = 'pdflatex';
        $msg_compiler = 'pdflatex';
    }
    if ($compiler eq 'dvilualatex') {
        $compiler     = 'lualatex';
        $msg_compiler = 'lualatex';
    }
    if ($compiler eq 'arara') {
        $compiler     = 'arara';
        $msg_compiler = 'arara';
    }
    Log("Compiling the file $name-pdf$ext using [$msg_compiler]");
    print "Compiling the file $name-pdf$ext using ", color('magenta'), "[$msg_compiler]\r\n",color('reset');
    RUNOSCMD("$compiler $opt_compiler", "$name-pdf$ext",'show');
    # makeindex
    if (-e "$name-pdf.idx" && !$arara) {
        RUNOSCMD("makeindex", "$name-pdf.idx",'show');
        RUNOSCMD("$compiler $opt_compiler", "$name-pdf$ext",'show');
    }
    # biber
    if ($runbiber && -e "$name-pdf.bcf" && !$arara) {
        RUNOSCMD("biber", "$name-pdf",'show');
        RUNOSCMD("$compiler $opt_compiler", "$name-pdf$ext",'show');
    }
    # bibtex
    if ($runbibtex && -e "$name-pdf.aux" && !$arara) {
        RUNOSCMD("bibtex", "$name-pdf",'show');
        RUNOSCMD("$compiler $opt_compiler", "$name-pdf$ext",'show');
    }
}

### Compress ./images with generated files
my $archivetar;
if ($zip or $tar) {
    my $stamp = strftime("%Y-%m-%d", localtime);
    $archivetar = "$imgdir-$stamp";

    my @savetozt;
    find(\&zip_tar, $imgdir);
    sub zip_tar{
        my $filesto = $_;
        if (-f $filesto && $filesto =~ m/$name-fig-.+?$/) { # search
            push @savetozt, $File::Find::name;
        }
        return;
    }
    Log('The files are compress are:');
    Logarray(\@savetozt);
    if ($zip) {
        Infoline("Creating  the file $archivetar.zip");
        zip \@savetozt => "$archivetar.zip";
        Log("The file $archivetar.zip are in $workdir");
    }
    if ($tar) {
        Infoline("Creating the file $archivetar.tar.gz");
        my $imgdirtar = Archive::Tar->new();
        $imgdirtar->add_files(@savetozt);
        $imgdirtar->write( "$archivetar.tar.gz" , 9 );
        Log("The file $archivetar.tar.gz are in $workdir");
    }
}

### Remove temporary files
my @tmpfiles;
my @protected = qw();
my $flsline = 'OUTPUT';
my @flsfile;

### Protect generated files
push @protected, "$name-pdf$ext", "$name-pdf.pdf";

find(\&aux_files, $workdir);
sub aux_files{
    my $findtmpfiles = $_;
    if (-f $findtmpfiles && $findtmpfiles =~ m/$name-fig(-exa)?-$tmp.+?$/) { # search
        push @tmpfiles, $_;
    }
    return;
}

if (-e "$name-fig-$tmp.fls") {
    push @flsfile, "$name-fig-$tmp.fls";
}
if (-e "$name-fig-exa-$tmp.fls") {
    push @flsfile, "$name-fig-exa-$tmp.fls";
}
if (-e "$name-pdf.fls") {
    push @flsfile, "$name-pdf.fls";
}

for my $filename(@flsfile){
    open my $RECtmp, '<', $filename;
        push @tmpfiles, grep /^$flsline/,<$RECtmp>;
    close $RECtmp;
}

foreach (@tmpfiles) { s/^$flsline\s+|\s+$//g; }
push @tmpfiles, @flsfile;

@tmpfiles = uniq(@tmpfiles);
@tmpfiles = array_minus(@tmpfiles, @protected);

Log('The files that will be deleted are:');
Logarray(\@tmpfiles);

### Only If exist
if (@tmpfiles) {
    Infoline("Remove temporary files created in $workdir");
    foreach my $tmpfiles (@tmpfiles) {
        move($tmpfiles, $tempDir);
    }
}

### Find dirs created by minted
my @deldirs;
my $mintdir    = "\_minted\-$name-fig-$tmp";
my $mintdirexa = "\_minted\-$name-fig-exa-$tmp";
if (-e $mintdir) { push @deldirs, $mintdir; }
if (-e $mintdirexa) { push @deldirs, $mintdirexa; }

Log('The directory that will be deleted are:');
Logarray(\@deldirs);

### Only If exist
if (@deldirs) {
    Infoline("Remove temporary directories created by minted in $workdir");
    foreach my $deldirs (@deldirs) {
        remove_tree($deldirs);
    }
}

### End of script process
if (!$norun and ($opts_cmd{boolean}{srcenv} or $opts_cmd{boolean}{subenv})) {
    Log("The image file(s): $format and subfile(s) are in $imgdirpath");
}
if (!$norun and (!$opts_cmd{boolean}{srcenv} and !$opts_cmd{boolean}{subenv})) {
    Log("The image file(s): $format are in $imgdirpath");
}
if ($norun and ($opts_cmd{boolean}{srcenv} or $opts_cmd{boolean}{subenv})) {
    Log("The subfile(s) are in $imgdirpath");
}
Log("The file $name-pdf$ext are in $workdir");

Infocolor('Finish', "The execution of $scriptname has been successfully completed");

Log("The execution of $scriptname has been successfully completed");

__END__

Falta
00. Mejorar el nombre de las variables internas (mejor lectura)
0. Ajustar las expresione regulares en el archivo de salida (conservar preview por ejemplo)
1. Añadir --latexmk -lualatex "--shell-escape %O %S" $name-pdf$ext
2. Logear TODAS las opciones
3. Reescribir --help
4. Hacer fake la opción --clear (ya no es necesaria)
5. Documentar TODOS los cambios


if ($runbibtex && $runbiber) {
    LOG ("!!! you cannot run BibTeX and Biber at the same document ...");
    LOG ("!!! Assuming to run Biber");
  $runbibtex = 0;
}

if ($all) {
  LOG ("Generate images eps/pdf/files and clear...");
   $eps =$ppm=$jpg=$png=$svg=$clear = 1;
}
