use strict;
use warnings;
use Module::Build;

my $class = Module::Build->subclass(
    class => 'Pg::RollDump::Build',
    code => q{
        sub ACTION_distdir {
            my $self = shift;
            my $ret = $self->SUPER::ACTION_distdir(@_);
            my $file = File::Spec->catfile($self->dist_dir, qw(bin pg_rolldump));
            my $lib = File::Spec->catfile(qw(lib Pg RollDump.pm));
            return if -s $file > 200; # Skip if it's big.

            chmod 0222, $file;
            open my $fh, '>>', $file or die "Cannot open $file: $!\n";
            open my $pod, '<', $lib or die "Cannot open $lib: $!\n";
            while (<$pod>) {
                if (/^=head1\s+(?:Usage|Options|Author|Copyright)\b/) {
                    print $fh $_;
                    while (<$pod>) {
                        last if /^=/ && $_ !~ /^=head1\s+(?:Usage|Options|Author|Copyright)\b/;
                        print $fh $_;
                    }
                }
            }

            close $pod or die die "Cannot close $lib: $!\n";
            close $fh or die die "Cannot close $file: $!\n";
            chmod 0555, $file;
            return $ret;
        }
    },
);

$class->new(
    module_name        => 'Pg::RollDump',
    license            => 'perl',
    configure_requires => {
        'Module::Build' => '0.35',
    },
    build_requires     => {
        'Module::Build'    => '0.35',
        'Test::More'       => '0.88',
    },
    requires           => {
        'perl'              => 5.008003,
        'File::Basename'    => 0,
        'Getopt::Long'      => 0,
        'Object::Tiny'      => 0,
        'Pod::Usage'        => 0,
    },
    recommends         => {
        'Test::Pod'           => '1.41',
        'Test::Pod::Coverage' => '1.06',
    },
    meta_merge         => {
        resources => {
            homepage   => 'http://search.cpan.org/dist/Pg-RollDump/',
            bugtracker => 'http://github.com/theory/pg-rolldump/issues/',
            repository => 'http://github.com/theory/pg-rolldump/tree/',
        }
    },
)->create_build_script;


