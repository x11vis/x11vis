# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#
package Mappings;

use strict;
use warnings;
use Data::Dumper;
use Moose;
use MooseX::Singleton;
use JSON::XS;
use IO::Handle;
use v5.10;

has 'atoms' => (
    traits => [ 'Hash' ],
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
    handles => {
        add_atom => 'set',
        get_atom_xid => 'get',
    }
);

has 'mappings' => (
    traits => [ 'Hash' ],
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} }
);

sub add_mapping {

}

__PACKAGE__->meta->make_immutable;

1
