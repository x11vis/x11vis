# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#
package FileOutput;

use strict;
use warnings;
use Data::Dumper;
use Moose;
use MooseX::Singleton;
use JSON::XS;
use IO::Handle;
use Time::HiRes qw(gettimeofday tv_interval);
use v5.10;

has 'output_file' => (
    is => 'rw',
    isa => 'Ref',
    default => sub {
        open(my $fh, '>', 'output.json');
        $fh->autoflush(1);
        # TODO: don't hardcode
        print $fh qq|[\n{"type":"cleverness","id":176, "title":"root", "idtype":"window"}\n|;
        return $fh;
    }
);

sub write {
    my ($self, $data) = @_;
    my $fh = $self->output_file;
    say $fh ', ' . $data;
}

__PACKAGE__->meta->make_immutable;

1
