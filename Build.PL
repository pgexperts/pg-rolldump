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

        sub ACTION_code {
            my $self = shift;
            $self->SUPER::ACTION_code(@_);
            # Copy the test scripts and then set the shebang line and make
            # sure that they're executable.
            my $to_dir = $self->localize_file_path("t/scripts");
            my $name = 'test_pg_dump';
            my $script = "$to_dir/$name";
            my $localized = $self->localize_file_path($script);
            my $orig = $self->localize_file_path("t/bin/$name");
            $self->copy_if_modified(
                from    => $orig,
                to_dir  => $to_dir,
                flatten => 1,
            );
            $self->fix_shebang_line($localized);
            $self->make_executable($localized);
            $self->add_to_cleanup($to_dir);
        }
    },
);

$class->new(
    module_name        => 'Pg::RollDump',
    license            => 'perl',
    add_to_cleanup     => [ 't/scripts' ],
    configure_requires => {
        'Module::Build' => '0.35',
    },
    build_requires     => {
        'File::Spec::Functions' => 0,
        'Module::Build'         => '0.35',
        'Test::File'            => '1.08',
        'Test::More'            => '0.88',
    },
    requires           => {
        'perl'              => 5.008003,
        'File::Basename'    => 0,
        'File::Path'        => 0,
        'File::Spec'        => 0,
        'Getopt::Long'      => 0,
        'List::Util'        => 0,
        'Object::Tiny'      => 0,
        'Pod::Usage'        => 0,
        'POSIX'             => 0,
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


