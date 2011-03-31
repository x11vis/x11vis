# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#
package Elapsed;
use Moose::Role;
use Time::HiRes qw(gettimeofday tv_interval);

has 'start_timestamp' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [ gettimeofday ] },
);

sub elapsed {
    my ($self) = @_;

    return tv_interval($self->start_timestamp);
}

1
