package Dist::Zilla::Plugin::Release::DuploadDist;

# ABSTRACT: Create deb package and upload it

use Moose;

with 'Dist::Zilla::Role::Releaser';

use Path::Class qw(dir);
use File::pushd qw(pushd);
use Archive::Tar;
use Dpkg::Changelog::Parse;

has test_release => (is => 'ro', isa => 'Int', required => 1, default => 0);

sub release {
    my ($self, $archive) = @_;
    $archive = $archive->absolute;

    my $build_root = $self->zilla->root->subdir('.build');
    $build_root->mkpath unless -d $build_root;

    my $tmpdir = dir(File::Temp::tempdir(DIR => $build_root));

    $self->log("Extracting $archive to $tmpdir");

    my @files = do {
        my $pushd = pushd($tmpdir);
        Archive::Tar->extract_archive("$archive");
    };

    $self->log_fatal(["Failed to extract archive: %s", Archive::Tar->error])
      unless @files;

    my $pushd = pushd("$tmpdir/$files[0]");

    my $cmd = "debuild -b";
    $cmd .= " -uc -us" if $self->test_release;
    $cmd .= " 2>&1";

    $self->_run_cmd($cmd, 'Building package', 'Failed to build package');

    if ($self->test_release) {
        `touch dupload.conf`;
        `echo 'package config;
\$preupload{"changes"} = "true %1";
1;' > ./dupload.conf`;
    }

    $cmd = "dupload";
    $cmd .= " --to $ENV{DUPLOAD_TO_HOST}" if $ENV{DUPLOAD_TO_HOST};
    $cmd .= " --no -c ./dupload.conf" if $self->test_release;
    my $changelog = changelog_parse(file => 'debian/changelog');
    my $changes_fn = '../' . join('_', $changelog->{'Source'}, $changelog->{'Version'}, 'amd64.changes');
    $cmd .= " $changes_fn 2>&1";

    $self->_run_cmd($cmd, 'Uploading package', 'Failed to upload package');

    undef($pushd);
    $tmpdir->rmtree;
}

sub _run_cmd {
    my ($self, $cmd, $desc, $error) = @_;

    $self->log("$desc:");
    open(my $fh, "$cmd |") || $self->log_fatal('Cannot run `$cmd`: $!');
    while (<$fh>) {
        chomp;
        $self->log("  $_");
    }
    close($fh);

    $self->log_fatal($error) if $?;
}

1;
