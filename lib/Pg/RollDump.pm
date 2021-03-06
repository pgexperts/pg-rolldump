package Pg::RollDump;

use strict;
use warnings;
use List::Util 'first';
use File::Spec;
use File::Path 'make_path';
use POSIX 'strftime';
use Object::Tiny qw(
    pg_dump
    pg_dump_options
    directory
    prefix
    keep_hours
    keep_days
    keep_weeks
    keep_months
    keep_years
    hard_links
    verbose
);

our $VERSION = '0.10';
my @intervals = qw(hours days weeks months years);

sub go {
    my $class = shift;
    $class->new( %{ $class->_getopts } )->run;
}

sub run {
    my $self = shift;

    # Fail early.
    require File::Copy unless $self->hard_links;

    my $dir = $self->directory;
    die "Directory $dir does not exist\n" unless -e $dir;
    die "$dir is not a directory\n" unless -d $dir;

    # Determine finest-grained interval.
    my $finest = first { defined $self->{"keep_$_"} } @intervals;

    die "Missing required interval parameter. Specify one or more of:\n    "
        . join "\n    ", map { "keep_$_" } @intervals
        unless $finest;

    # Where we gonna put this?
    my $path = File::Spec->catdir($dir, $finest);
    my $file = File::Spec->catfile($path, $self->dumpfile);
    make_path $path;

    my @cmd = ($self->pg_dump, @{ $self->pg_dump_options }, '--file' => $file);

    system(@cmd) == 0 or die "system @cmd failed: $?\n";

    # Roll wid'it.
    return $self->_rolldump($file);
}

sub _rolldump {
    my ($self, $file) = @_;
    my $date = _parse_date($self->dumpfile);

    for my $interval (
        grep { defined $self->{"keep_$_"} } @intervals
    ) {
        make_path +File::Spec->catdir($self->directory, $interval);
        my $keep = $self->{"keep_$interval"};
        my $files = $self->_files_for($interval);
        push @{ $files }, $self->_link_for($interval, $file)
            if $self->_need_link($interval, $date, $files);
        while (@{ $files } > $keep) {
            my $to_delete = shift @{ $files };
            unlink $to_delete or die "Cannot unlink $to_delete: $!\n";
        }
    }
    return $self;
}

my %compare = (
    hours => sub {
        my ($c, $n) = @_;
        my $f = '%u-%02u-%02u-%02u';
        return sprintf($f, @{ $c }{qw(year month day hour)})
            lt sprintf($f, @{ $n }{qw(year month day hour)});
    },
    days => sub {
        my ($c, $n) = @_;
        my $f = '%u-%02u-%02u';
        return sprintf($f, @{ $c }{qw(year month day)})
            lt sprintf($f, @{ $n }{qw(year month day)})
    },
    weeks => sub {
        my ($c, $n, $t) = @_;
        my $f = '%u-%02u-%02u';
        return sprintf($f, @{ $c }{qw(year month day)})
            lt sprintf($f, @{ $n }{qw(year month day)})
            && (gmtime($t))[6] == 0;
    },
    months => sub {
        my ($c, $n) = @_;
        my $f = '%u-%02u';
        return sprintf($f, @{ $c }{qw(year month)})
            lt sprintf($f, @{ $n }{qw(year month)})
    },
    years => sub {
        $_[0]->{year} < $_[1]->{year}
    },
);

sub _need_link {
    my ($self, $interval, $date, $files) = @_;
    return !@{ $files } || $compare{$interval}->(
        _parse_date($files->[-1]),
        $date,
        $self->{time}
    );
}

sub _link_for {
    my ($self, $interval, $file) = @_;

    my $dest = File::Spec->catfile($self->directory, $interval, $self->dumpfile);
    return if $dest eq $file;

    if ($self->hard_links) {
        link $file, $dest or die "Cannot link $file to $dest: $!\n";
    } else {
        File::Copy::copy($file, $dest)
            or die "Cannot copy $file to $dest: $!\n";
    }
    return $dest;
}

sub _files_for {
    my ($self, $interval) = @_;
    my $path = File::Spec->catdir($self->directory, $interval);
    [ glob File::Spec->catfile($path, '*.dmp') ];
}

sub dumpfile {
    my $self = shift;
    $self->{dumpfile} ||= $self->prefix . strftime(
        '-%Y%m%d-%H%M%S',
        gmtime($self->{time} = time)
    ) . '.dmp';
}

sub _parse_date {
    $_[0] =~ qr{\b(\d{4})(\d{2})(\d{2})-(\d{2})\d{2}\d{2}(?:[.]dmp)?$};
    return {
        year  => $1,
        month => $2 + 0,
        day   => $3 + 0,
        hour  => $4 + 0,
    };
}

sub _pod2usage {
    shift;
    require Pod::Usage;
    Pod::Usage::pod2usage(
        '-verbose'  => 99,
        '-sections' => '(?i:(Usage|Options))',
        '-exitval'  => 1,
        '-input'    => __FILE__,
        @_
    );
}

sub _getopts {
    my $self = shift;
    require Getopt::Long;
    Getopt::Long::Configure( qw(bundling) );

    my %opts = (
        verbose    => 0,
        pg_dump    => 'pg_dump',
        hard_links => 1,
    );

    Getopt::Long::GetOptions(
        'pg-dump|b=s'            => \$opts{pg_dump},
        'output-dir|dir|o=s'     => \$opts{directory},
        'file-prefix|prefix|p=s' => \$opts{prefix},
        'keep-hours|hours|h=i'   => \$opts{keep_hours},
        'keep-days|days|d=i'     => \$opts{keep_days},
        'keep-weeks|weeks|w=i'   => \$opts{keep_weeks},
        'keep-months|months|m=i' => \$opts{keep_months},
        'keep-years|years|y=i'   => \$opts{keep_years},
        'hard-links!'            => \$opts{hard_links},
        'verbose|V+'             => \$opts{verbose},
        'help|H'                 => \$opts{help},
        'man|M'                  => \$opts{man},
        'version|v'              => \$opts{version},
    ) or $self->_pod2usage;

    # Handle documentation requests.
    $self->_pod2usage(
        ( $opts{man} ? ( '-sections' => '.+' ) : ()),
        '-exitval' => 0,
    ) if $opts{help} or $opts{man};

    # Handle version request.
    if ($opts{version}) {
        require File::Basename;
        print File::Basename::basename($0), ' (', __PACKAGE__, ') ',
            __PACKAGE__->VERSION, $/;
        exit;
    }

    # Check required options.
    $self->_pod2usage( '-message' => 'Missing required --output-dir option' )
        unless $opts{directory};

    $self->_pod2usage(
        '-message' => "Missing required interval option. Specify one or more of:\n    "
            . join "\n    ", map { "--keep-$_" } @intervals
    ) unless grep { $opts{"keep_$_"} } @intervals;

    if (@ARGV) {
        # Strip out the -f and --file options.
        shift @ARGV if $ARGV[0] eq '--';
        Getopt::Long::Configure( qw(bundling passthrough) );
        Getopt::Long::GetOptions(
            'file|f=s' => \my $file,
            'host|h=s' => \my $host,
        );
        warn "WARNING: The pg_dump `--file $file` option will be ignored\n"
            if defined $file;

        # Use --host for the default prefix.
        if ($host) {
            push @ARGV => '--host' => $host;
            $opts{prefix} ||= $host
        } else {
            $opts{prefix} ||= 'localhost';
        }
    }

    $opts{pg_dump_options} = \@ARGV;

    return \%opts;
}

1;
__END__

=head1 Name

Pg::RollDump - Time-based rolling PostgreSQL cluster backups

=head1 Synopsis

 use Pg::RollDump;
 Pg::RollDump->go;

=head1 Usage

  pg_rolldump --dir /path/to/backup/dir [OPTIONS] -- [pg_dump options]

=head1 Description

This program manages rotating backups from C<pg_dump>. Simply tell it a root
directory in which to store the backups, and the number of hourly, daily
weekly, and yearly backups you'd like to keep. Then put it into a cron job to
run at the highest resolution increment. So if you want hourly backups, run it
hourly. If you want daily backups but no hourly backups, run it daily. Backups
will be stored in subdirectories of the backup directory named for the
increments.

C<pg_rolldump> uses C<pg_dump> to do the actual dumping. You can specify any
options to C<pg_dump> on the C<pg_rolldump> command line simply by separating
them from the C<pg_rolldump> options with a lone double-dash (C<-->). The only
C<pg_dump> option that's disallowed is C<--file>, because C<pg_rolldump>
itself determines the location of the dump file. If C<--file> is specified,
C<pg_rolldump> will remove it an issue a warning.

=head1 Examples

So let's look at some examples.

  pg_rolldump --dir /var/backup/db1 \
    --keep-days    8 \
    --keep-weeks   3 \
    --keep-months 11 \
    -- -U postgres -h db1 -Fc

This invocation should be run daily. It calls C<pg_dump> with the options C<-h
db1 -Fc> and will keep up to 8 daily, 3 weekly, and 11 monthly backups. Daily
backups will live in F</var/backup/db1/days> and each time it's run, a new
backup will be stored in that directory. Weekly and monthly backups will be
added as hard links to the daily backup if a week or month has gone by. So the
directory structure under F</var/backup/db1> after a few months of daily runs
should look something like this:

  days/localhost-20110915-043326.dmp
  days/localhost-20110916-043334.dmp
  days/localhost-20110917-043343.dmp
  days/localhost-20110918-043534.dmp
  days/localhost-20110919-043456.dmp
  days/localhost-20110920-043545.dmp
  days/localhost-20110921-043634.dmp
  days/localhost-20110922-043643.dmp
  weeks/localhost-20110908-043223.dmp
  weeks/localhost-20110915-043326.dmp
  weeks/localhost-20110922-043643.dmp
  months/

Note that duplicate file names, such as F<days/localhost20110915-043326.dmp>
and F<weeks/localhost20110915-043326.dmp>, are actually the same file.
C<pg_rolldump> achieves this via hard links, thereby reducing disk usage.

Here's another one:

  pg_rolldump --dir /var/backup/db2 \
    --keep-days    8 \
    --keep-weeks   3 \
    --prefix       mydump \
    -- -U postgres -h db2 -Fc

This invocation should also be run daily. It will call C<pg_dump> with the
options C<-h db2 -Fc> and keep up to 8 daily and three weekly backups.
Normally backup file names begin with the host name being backed up (which
allows one to store backups from multiple hosts in one directory), but here
the C<--prefix> option has been used to start file names with C<mydump>
instead. So after a couple of weeks running this script, the backup files in
C</var/backup/db2> will look something like this:

  days/mydump-20110915-043326.dmp
  days/mydump-20110916-043334.dmp
  days/mydump-20110917-043343.dmp
  days/mydump-20110918-043534.dmp
  days/mydump-20110919-043456.dmp
  days/mydump-20110920-043545.dmp
  days/mydump-20110921-043634.dmp
  days/mydump-20110922-043643.dmp
  weeks/mydump-20110915-043326.dmp
  weeks/mydump-20110922-043643.dmp

We can do without hard links, if necessary, like so:

  pg_rolldump --dir /var/backup/dbdev1 \
    --keep-weeks   3 \
    --keep-months   1 \
    --no-hard-links \
    -- -U postgres -h dbdev1 -Fc

This invocation should be run weekly. After a month or so, it should have
backup files something like this:

  weeks/localhost-20110908-043223.dmp
  weeks/localhost-20110915-043326.dmp
  weeks/localhost-20110922-043643.dmp
  months/localhost-20110922-043643.dmp

Because we've used C<--no-hard-links>, F<weeks/localhost-20110922-043643.dmp>
and F<months/localhost-20110922-043643.dmp> are not hard-linked, but
completely separate files. This obviously uses more disk space and will make
the backup slower whenever a new monthly copy needs to be made, but may be
necessary on some file systems.

We can also back up other hosts, like so:

  pg_rolldump --dir /var/backup/dbdev2 \
    --keep-weeks   3 \
    -- -U postgres -h dbdev2 -Fc

This invocation should be run weekly. After three weeks, the files will
look something like this:

  weeks/dbdev2-20110908-043223.dmp
  weeks/dbdev2-20110915-043326.dmp
  weeks/dbdev2-20110922-043643.dmp

Note that C<pg_rolldump> is smart enough to grab the host name from the
C<pg_dump parameters>, C<-h dbdev2 -Fc>, and use it as the prefix for the
dump file names.

=head1 Options

  -b --pg-dump              PATH    Path to C<pg_dump>
  -o --dir    --output-dir  DIR     Directory in which to store dump files
  -p --prefix --file-prefix PREFIX  Prefix to use in dump file names.
  -h --hours  --keep-hours  HOURS   Number of hours' worth of dumps to keep.
  -d --days   --keep-days   DAYS    Number of days' worth of dumps to keep.
  -w --weeks  --keep-weeks  WEEKS   Number of weeks' worth of dumps to keep.
  -m --months --keep-months MONTHS  Number of months' worth of dumps to keep.
  -y --years  --keep-years  YEARS   Number of years' worth of dumps to keep.
     --hard-links                   Hard link duplicate dump files (default).
     --no-hard-links                Do not hard link duplicate dump files.
  -V --verbose                      Incremental verbose mode.
  -H --help                         Print a usage statement and exit.
  -M --man                          Print the complete documentation and exit.
  -v --version                      Print the version number and exit.

=head1 Class Interface

=head2 Class Method

=head3 C<go>

  Pg::RollDump->go;

Called from C<pg_rolldump>, this class method parses command-line options in
C<@ARGV>, passes them to the constructor, and runs the backups.

=head2 Constructor

=head3 C<new>

  my $rolldump = Pg::RollDump->new(\%params);

Constructs and returns a Pg::RollDump object. The supported parameters are:

=over

=item C<pg_dump>

Location of the C<pg_dump> executable. Defaults to just C<pg_dump>, which will
work fine if it's in the path.

=item C<pg_dump_options>

An array of command-line options to be passed to C<pg_dump>.

=item C<directory>

Directory in which to store the dump files. Required.

=item C<prefix>

Prefix to use at the beginning of dump file names.

=item C<keep_hours>

Number of hours' worth of dump files to keep. Must be run hourly in order for
this parameter to have an effect. An hour is assumed to have passed if the
current hour is greater than the hour of the last retained dump.

=item C<keep_days>

Number of days' worth of dump files to keep. Must be run at least daily in
order for this parameter to have an effect. A day is assumed to have passed if
the current date is greater than the date of the last retained dump.

=item C<keep_weeks>

Number of weeks' worth of dump files to keep. Must be run at least weekly in
order for this parameter to have an effect. A week is assumed to have passed
if the current date is greater than the date of the last retained dump and the
day of the week is Sunday.

=item C<keep_months>

Number of months' worth of dump files to keep. Must be run at least monthly in
order for this parameter to have an effect. A month is assumed to have passed
if the current year and month are greater than the year and month of the last
retained dump.

=item C<keep_years>

Number of years' worth of dump files to keep. Must be run at least yearly in
order for this parameter to have an effect. A year is assumed to have passed
if the current year is greater than the year and month of the last retained
dump.

=item C<hard_links>

Boolean indicating whether or not duplicate dump files should be stored as
hard links. Defaults to true to minimize disk usage.

=item C<verbose>

Pass a value greater than 0 for verbose output. The higher the number, the
more verbose (up to 3).

=back

=head1 Instance Interface

=head2 Instance Methods

=head3 C<run>

  $rolldump->run;

Runs the backups and manages the rolling backups.

=head3 C<dumpfile>

  my $filename = $rolldump->dumpfile;

Returns the base file name to be used for the dump file.

=head1 Support

This module is stored in an open GitHub repository,
L<http://github.com/pgexperts/pg-rolldump/>. Feel free to fork and contribute!

Please file bug reports at L<http://github.com/pgexperts/pg-rolldump/issues/>.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2011 PostgreSQL Experts, Inc. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
