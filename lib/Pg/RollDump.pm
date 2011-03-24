package Pg::RollDump;

use strict;
use warnings;
use Object::Tiny qw(
    verbose
);

our $VERSION = '0.10';

sub go {
    my $class = shift;
    $class->new( $class->_getopts )->run;
}

sub run {
    my $self = shift;
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
            . join "\n    ", map { "--keep-$_" } qw(hours days weeks months years)
    ) unless grep { $opts{"keep_$_"} } qw(hours days weeks months years);

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

=head1 Examples

  pg_rolldump --dir /var/backup/db1 \
    --keep-days    8 \
    --keep-weeks   3 \
    --keep-months 11 \
    -- -U postgres -h db1 -Fc

  pg_rolldump --dir /var/backup/db2 \
    --keep-days    8 \
    --keep-weeks   3 \
    -- -U postgres -h db2 -Fc

  pg_rolldump --dir /var/backup/dbdev1 \
    --keep-weeks   3 \
    -- -U postgres -h dbdev1 -Fc

  pg_rolldump --dir /var/backup/dbdev2 \
    --keep-weeks   3 \
    -- -U postgres -h dbdev2 -Fc

=head1 Description

This program manages rotating backups from C<pg_dump>.

=head1 Options

  -b --pg-dump PATH         Path to C<pg_dump>
  -o --dir    --output-dir  DIR     Directory in which to store dump files
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

=item C<directory>

Directory in which to store the dump files. Required.

=item C<keep_hours>

Number of hours' worth of dump files to keep. Must be run hourly in order for
this parameter to have an effect.

=item C<keep_days>

Number of days' worth of dump files to keep. Must be run at least daily in
order for this parameter to have an effect.

=item C<keep_weeks>

Number of weeks' worth of dump files to keep. Must be run at least weekly in
order for this parameter to have an effect.

=item C<keep_months>

Number of months' worth of dump files to keep. Must be run at least monthly in
order for this parameter to have an effect.

=item C<keep_years>

Number of years' worth of dump files to keep. Must be run at least yearly in
order for this parameter to have an effect.

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

=head2 Instance Accessors

=head3 C<verbose>

  my $verbose = $rolldump->verbose;

Returns the value passed for the C<verbose> parameter to C<new()>. Defaults to
0.

=head1 Support

This module is stored in an open GitHub repository,
L<http://github.com/theory/pg-rolldump/>. Feel free to fork and contribute!

Please file bug reports at L<http://github.com/theory/pg-rolldump/issues/>.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2011 PostgreSQL Experts, Inc. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
