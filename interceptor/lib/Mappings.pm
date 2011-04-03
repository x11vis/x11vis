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
    default => sub { {} },
    handles => {
        mapping_for => 'get',
        add_mapping => 'set',
        delete_mapping => 'delete',
    }
);

my %prefixes = (
    window => 'w',
    atom => 'a',
    pixmap => 'p',
    font => 'f',
    gcontext => 'g',
);

my %counters = ();

sub id_for {
    my ($self, $x_id, $class) = @_;

    my $mapping = $self->mapping_for($x_id);
    return $mapping->{id} if defined($mapping);

    if (!defined($class)) {
        warn "class not given but ID unknown!";
    }

    # We need to create a new mapping
    my $id = $counters{$class};
    $id ||= 0;
    $counters{$class} = $id + 1;
    $id = $prefixes{$class} . '_' . $id;
    $self->add_mapping($x_id => {
        id => $id,
        class => $class
    });

    if ($class eq 'pixmap') {
        my $clever = encode_json({
            type => 'cleverness',
            id => $id,
            title => 'pixmap ' . $counters{$class},
            idtype => 'pixmap',
        });
        FileOutput->instance->write($clever);
    }

    if ($class eq 'gcontext') {
        my $clever = encode_json({
            type => 'cleverness',
            id => $id,
            title => 'gc ' . $counters{$class},
            idtype => 'gcontext',
        });
        FileOutput->instance->write($clever);
    }

    return $id;
}

__PACKAGE__->meta->make_immutable;

1
