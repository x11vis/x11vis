# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#
package Burst;

use strict;
use warnings;
use Data::Dumper;
use Moose;
use JSON::XS;
use IO::Handle;
use Time::HiRes qw(gettimeofday tv_interval);
use FileOutput;
use v5.10;

has 'start_timestamp' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub { [ gettimeofday ] }
);

has 'elapsed' => (
    is => 'rw',
    isa => 'Num'
);

has '_packets' => (
    traits => [ 'Array' ],
    is => 'rw',
    isa => 'ArrayRef[Str]',
    handles => {
        add_packet => 'push',
        packets => 'elements',
        clear_packets => 'clear',
    }
);

has '_in_burst' => (
    traits => [ 'Bool' ],
    is => 'rw',
    isa => 'Bool',
    default => 0,
    handles => {
        now_in_burst => 'set',
        end_of_burst => 'unset',
    }
);

#
# Ensure that we are currently in a burst (create a new header)
#
sub ensure_in_burst {
    my ($self) = @_;

    return if $self->_in_burst;

    $self->elapsed(tv_interval($self->start_timestamp));
    $self->now_in_burst;
}

# finishes the burst
sub finish {
    my ($self) = @_;
    my $packets = '';
    if (defined($self->_packets)) {
        $packets = join(', ', $self->packets);
    }
    my $fo = FileOutput->instance;
    $fo->write('{"type":"burst", "elapsed":' . $self->elapsed . ', "packets":[' . $packets . ']}');
    $self->clear_packets;
    $self->end_of_burst;
}

__PACKAGE__->meta->make_immutable;

1
