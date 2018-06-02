#!/usr/bin/perl

use strict;
use warnings;

use Dotter;

sub foreach_dir_invoke {
    my $sub = shift;
    my $mode = scalar @_ ? shift : "";

    $sub->($mode, ".") if not scalar @_;

    for my $path (@_) {
        $sub->($mode, $path);
    }
}

die "Command not specified" if not scalar @ARGV;

my $command = shift @ARGV;
switch ($command) {
    case "init"  { foreach_dir_invoke(\&init,  @ARGV) }
    case "apply" { foreach_dir_invoke(\&apply, @ARGV) }
}
