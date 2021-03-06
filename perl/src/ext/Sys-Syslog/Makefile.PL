use strict;
use Config;
use ExtUtils::MakeMaker;
eval 'use ExtUtils::MakeMaker::Coverage';
use File::Copy;
use File::Path;
use File::Spec;
require 5.005;


# create a typemap for Perl 5.6
if ($] < 5.008) {
    open(TYPEMAP, ">typemap") or die "fatal: can't write typemap: $!";
    print TYPEMAP "const char *\t\tT_PV\n";
    close(TYPEMAP);
}

# create a lib/ dir in order to avoid warnings in Test::Distribution
mkdir "lib", 0755;

# virtual paths given to EU::MM
my %virtual_path = ( 'Syslog.pm' => '$(INST_LIBDIR)/Syslog.pm' );

# detect when to use Win32::EvenLog
my (@extra_params, @extra_prereqs);
my $use_eventlog = eval "use Win32::EventLog; 1";

if ($use_eventlog) {
    print " * Win32::EventLog detected.\n";
    my $name = "PerlLog";

    push @extra_prereqs, 
        Win32 => 0,  "Win32::TieRegistry" => 0,  "Win32::EventLog" => 0;

    $virtual_path{'win32/Win32.pm'   } = '$(INST_LIBDIR)/Syslog/Win32.pm';
    $virtual_path{'win32/PerlLog.dll'} = '$(INST_ARCHAUTODIR)/PerlLog.dll';

    push @extra_params, CCFLAGS => "-Ifallback";

    # recreate the DLL from its uuencoded form if it's not here
    if (! -f File::Spec->catfile("win32", "$name.dll")) {
        # read the uuencoded data
        open(UU, '<' . File::Spec->catfile("win32", "$name\_dll.uu"))
            or die "fatal: Can't read file '$name\_dll.uu': $!";
        my $uudata = do { local $/; <UU> };
        close(UU);

        # write the DLL
        open(DLL, '>' . File::Spec->catfile("win32", "$name.dll"))
            or die "fatal: Can't write DLL '$name.dll': $!";
        binmode(DLL);
        print DLL unpack "u", $uudata;
        close(DLL);
    }
}
elsif ($^O =~ /Win32/) {
    print <<"NOTICE"
 *** You're running on a Win32 system,  but you lack the Win32::EventLog\a
 *** module, part of the libwin32 distribution. Although Sys::Syslog can 
 *** be used without Win32::EventLog, it won't be very useful except for 
 *** sending remote syslog messages.  If you want to log messages on the 
 *** local host as well, please install libwin32 then Sys::Syslog again.
NOTICE
}

# detect when being built in Perl core
if (grep { $_ eq 'PERL_CORE=1' } @ARGV) {
    push @extra_params, 
        MAN3PODS    => {};      # Pods will be built by installman.
}
else {
    push @extra_params, 
        DEFINE      => '-DUSE_PPPORT_H';
}

# on pre-5.6 Perls, add warnings::compat to the prereq modules
push @extra_prereqs, "warnings::compat" => "0.06"  if $] < 5.006;

WriteMakefile(
    NAME            => 'Sys::Syslog',
    LICENSE         => 'perl',
    AUTHOR          => 'Sebastien Aperghis-Tramoni <sebastien@aperghis.net>',
    VERSION_FROM    => 'Syslog.pm', 
    ABSTRACT_FROM   => 'Syslog.pm', 
    INSTALLDIRS     => 'perl',
    XSPROTOARG      => '-noprototypes',
    PM              => \%virtual_path, 
    PREREQ_PM       => {
        # run prereqs
        'Carp'              => 0,
        'Fcntl'             => 0,
        'File::Basename'    => 0,
        'File::Spec'        => 0,
        'POSIX'             => 0,
        'Socket'            => 0,
        'XSLoader'          => 0,
        @extra_prereqs,

        # build/test prereqs
        'Test::More'        => 0,
    },
    PL_FILES        => {},
    dist            => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean           => { FILES => 'Sys-Syslog-*' }, 
    realclean       => { FILES => 'lib const-c.inc const-xs.inc macros.all '
        .'PerlLog.h typemap *.bak *.bin *.rc win32/PerlLog_dll' },
    @extra_params
);


# find a default value for _PATH_LOG
my $_PATH_LOG;

if (-c "/dev/conslog" and -w _) {
    # SunOS 5.8 has a worldwritable /dev/conslog STREAMS log driver.
    # The /dev/log STREAMS log driver on this platform has permissions
    # and ownership `crw-r----- root sys'.  /dev/conslog has more liberal
    # permissions.
    $_PATH_LOG = "/dev/conslog";
}
elsif (-S "/var/run/syslog" and -w _) {
    # Mac OS X puts it at a different path.
    $_PATH_LOG = "/var/run/syslog";
}
elsif (-p "/dev/log" and -w _) {
    # On HP-UX, /dev/log isn't a unix domain socket but a named pipe.
    $_PATH_LOG = "/dev/log";
}
elsif ((-S "/dev/log" or -c _) and -w _) {
    # Most unixes have a unix domain socket /dev/log.
    $_PATH_LOG = "/dev/log";
}
else {
    $_PATH_LOG = "";
}


# if possible, generate the code that handles the constants with 
# ExtUtils::Constant, otherwise use cached copy in fallback/
if(eval {require ExtUtils::Constant; 1}) {
    my @levels = qw(
        LOG_ALERT LOG_CRIT LOG_DEBUG LOG_EMERG LOG_ERR 
        LOG_INFO LOG_NOTICE LOG_WARNING
    );

    my @facilities = (
        # standard facilities
        qw(
            LOG_AUTH LOG_AUTHPRIV LOG_CRON LOG_DAEMON LOG_FTP LOG_KERN
            LOG_LOCAL0 LOG_LOCAL1 LOG_LOCAL2 LOG_LOCAL3 LOG_LOCAL4
            LOG_LOCAL5 LOG_LOCAL6 LOG_LOCAL7 LOG_LPR LOG_MAIL LOG_NEWS
            LOG_SYSLOG LOG_USER LOG_UUCP
        ),
        # Mac OS X specific facilities
        { name => "LOG_INSTALL",    type => "IV", default => [ "IV", "LOG_USER"  ] },
        { name => "LOG_LAUNCHD",    type => "IV", default => [ "IV", "LOG_DAEMON"] },
        { name => "LOG_NETINFO",    type => "IV", default => [ "IV", "LOG_DAEMON"] },
        { name => "LOG_RAS",        type => "IV", default => [ "IV", "LOG_AUTH"  ] },
        { name => "LOG_REMOTEAUTH", type => "IV", default => [ "IV", "LOG_AUTH"  ] },
        # modern BSD specific facilities
        { name => "LOG_CONSOLE",    type => "IV", default => [ "IV", "LOG_USER"  ] },
        { name => "LOG_NTP",        type => "IV", default => [ "IV", "LOG_DAEMON"] },
        { name => "LOG_SECURITY",   type => "IV", default => [ "IV", "LOG_AUTH"  ] },
        # IRIX specific facilities
        { name => "LOG_AUDIT",      type => "IV", default => [ "IV", "LOG_AUTH"  ] },
        { name => "LOG_LFMT",       type => "IV", default => [ "IV", "LOG_USER"  ] },
    );

    my @options = qw(
        LOG_CONS LOG_PID LOG_NDELAY LOG_NOWAIT LOG_ODELAY LOG_PERROR 
    );

    my @others_macros = (
        qw(LOG_FACMASK),
        { name => "_PATH_LOG", type => "PV", default => [ "PV", qq("$_PATH_LOG") ] },
        { name => "LOG_PRIMASK",     type => "IV", default => [ "IV", 7] },
        { name => "LOG_NFACILITIES", type => "IV", default => [ "IV", scalar @facilities] },
    );

    ExtUtils::Constant::WriteConstants(
        NAME => 'Sys::Syslog',
        NAMES => [ @levels, @facilities, @options, @others_macros ],
        ($] > 5.009002 ? (PROXYSUBS => 1) : ()),
    );

    my @names = map { ref $_ ? $_->{name} : $_ } @levels, @facilities, @options;
    open(MACROS, '>macros.all') or warn "warning: Can't write 'macros.all': $!\n";
    print MACROS join $/, @names;
    close(MACROS);
}
else {
    foreach my $file ('const-c.inc', 'const-xs.inc') {
        my $fallback = File::Spec->catfile('fallback', $file);
        copy($fallback, $file) or die "fatal: Can't copy $fallback to $file: $!";
    }
}
