package Dotter;

use strict;
use warnings;

use feature 'say';
use Switch;

use Exporter;
our $VERSION = '1.00';
our @ISA     = qw(Exporter);
our @EXPORT  = qw(init apply);

use System::Info qw(sysinfo_hash);
use Sys::Hostname::Long qw(hostname_long);

use File::Spec::Functions qw(catdir catfile);
use File::Basename qw(fileparse);
use File::Slurp qw(read_dir);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Copy::Recursive qw(fcopy dircopy);

use constant ANY => '_';

my $sysinfo       = sysinfo_hash;
my $osname        = $sysinfo->{osname};
my $osver         = $sysinfo->{osvers};
my $hostname      = $sysinfo->{hostname};
my $long_hostname = hostname_long;

my @relevant_paths = (
    catdir(ANY,            ANY,     ANY),
    catdir(ANY,            $osname, ANY),
    catdir(ANY,            $osname, $osver),
    catdir($hostname,      ANY,     ANY),
    catdir($hostname,      $osname, ANY),
    catdir($hostname,      $osname, $osver),
    catdir($long_hostname, ANY,     ANY),
    catdir($long_hostname, $osname, ANY),
    catdir($long_hostname, $osname, $osver),
);

sub make_path_or_die {
    my $path = shift;
    make_path $path or die "Could not create directory `${path}`: $!";
}

sub dircopy_or_die {
    my ($source_path, $target_path) = @_;
    dircopy($source_path, $target_path)
      or die "Could not recursively copy the contents of directory `${source_path}` to `${target_path}`: $!";
}

sub symlink_or_die {
    my ($target_filename, $link_filename) = @_;
    symlink($target_filename, $link_filename)
      or die "Could not create symlink from `${link_filename}` to `${target_filename}`: $!";
}

sub get_target_filename {
    my ($target_base_path, $source_path_prefix, $source_path, $source_basename) = @_;
    my $target_relative_path = $source_path =~ s/^$source_path_prefix//r;
    my $target_path          = catdir($target_base_path, $target_relative_path);
    my $target_filename      = catfile($target_path, "${source_basename}.m4");
    return $target_filename;
}

sub get_filename {
    my ($file_path, $file_basename) = @_;
    my $filename = catfile($file_path, $file_basename);
    return $filename;
}

sub collect_macros_file {
    my ($source_filename, $target_filename) = @_;
    open(my $target_handle, '>>', $target_filename)
      or die "Could not open file `${target_filename}` for appending: $!";
    my $macro_filename = "${source_filename}.m4";
    say $target_handle "include(`${macro_filename}')dnl"
      or die "Could not write to file `${target_filename}`: $!";
    close $target_handle
      or die "Could not close file `${target_filename}`: $!";
}

sub expand_macros_file {
    my $target_filename = shift;
    my $source_filename = "${target_filename}.m4";
    system "m4 '${source_filename}' > '${target_filename}'";
    unlink $source_filename
      or die "Could not delete file `${source_filename}`: $!";
}

sub invoke_foreach_m4_script {
    my ($path, $invoke_if_m4_script, $invoke_unless_m4_script) = @_;
    my $invoke_foreach = sub {
        my $filename = $File::Find::name;
        my ($file_basename, $file_path, $file_extension) = fileparse($filename, qr/\.[^.]*/);
        if ($file_extension eq ".m4") {
            $invoke_if_m4_script->($file_path, $file_basename);
        } elsif (defined $invoke_unless_m4_script) {
            $invoke_unless_m4_script->($file_path, $file_basename);
        }
    };
    find($invoke_foreach, $path);
}

sub collect_macros {
    my ($target_base_path, $source_path_prefix, $do_copy) = @_;
    my $prepare_filenames_and_invoke_action = sub {
        my ($source_path, $source_basename, $action) = @_;
        my $source_filename = get_filename($source_path, $source_basename);
        my $target_filename = get_target_filename($target_base_path, $source_path_prefix, $source_path, $source_basename);
        $action->($source_filename, $target_filename);
    };
    my $invoke_if_m4_script = sub {
        my ($source_path, $source_basename) = @_;
        $prepare_filenames_and_invoke_action->($source_path, $source_basename, \&collect_macros_file);
    };
    my $invoke_unless_m4_script = sub {
        return if not $do_copy;
        my ($source_path, $source_basename) = @_;
        $prepare_filenames_and_invoke_action->($source_path, $source_basename, \&fcopy);
    };
    invoke_foreach_m4_script($source_path_prefix, $invoke_if_m4_script, $invoke_unless_m4_script);
}

sub expand_macros {
    my $base_path           = shift;
    my $invoke_if_m4_script = sub {
        my ($file_path, $file_basename) = @_;
        my $filename = get_filename($file_path, $file_basename);
        expand_macros_file($filename);
    };
    invoke_foreach_m4_script($base_path, $invoke_if_m4_script);
}

sub init {
    my $mode      = scalar @_ ? shift : "";
    my $base_path = scalar @_ ? shift : "";

    my @paths;

    switch ($mode) {
        case "full" { @paths = @relevant_paths; }
        case "regular" { @paths = ($relevant_paths[0], $relevant_paths[1], $relevant_paths[3], $relevant_paths[4]); }
    }

    for my $path (@paths) {
        my $path = catdir($base_path, ".files", $path);
        make_path_or_die $path;
    }
}

sub apply {
    my $mode      = scalar @_ ? shift : "";
    my $base_path = scalar @_ ? shift : "";

    if ($mode eq "expand") {
        expand_macros $base_path;
        return;
    }

    for my $path (@relevant_paths) {
        my $source_path = catdir($base_path, ".files", $path);

        switch ($mode) {
            case "copy" {
                dircopy_or_die($source_path, $base_path);
            }

            case "symlink" {
                my @file_basenames = read_dir($source_path);
                for my $file_basename (@file_basenames) {
                    my $source_filename = catfile($source_path, $file_basename);
                    my $target_filename = catfile($base_path,   $file_basename);
                    symlink_or_die($source_filename, $target_filename);
                }
            }

            case "collect" {
                collect_macros($base_path, $source_path);
            }

            case "copy-collect" {
                collect_macros($base_path, $source_path, 1);
            }

            case "copy-collect-expand" {
                collect_macros($base_path, $source_path, 1);
            }
        }
    }

    if ($mode eq "copy-collect-expand") {
        expand_macros $base_path;
    }
}

1;

__END__
