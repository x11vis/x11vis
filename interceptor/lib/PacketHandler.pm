# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#
package PacketHandler;

use strict;
use warnings;
use Data::Dumper;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent;
use Moose;
use JSON::XS;
use IO::Handle;
use Time::HiRes qw(gettimeofday tv_interval);
use lib qw(gen);
use RequestDissector;
use v5.10;

has 'History' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
);

# mapping of X11 IDs to our own IDs
has 'x_ids' => (
    traits => [ 'Hash' ],
    is => 'rw',
    isa => 'HashRef[Str]',
    default => sub { {} },
    handles => {
        add_mapping => 'set',
        id_for_xid => 'get',
        xid_known => 'exists'
    }
);

has 'start_timestamp' => (
    is => 'rw',
    isa => 'ArrayRef'
);

has 'sequence' => (
    traits => [ 'Counter' ],
    is => 'rw',
    isa => 'Int',
    default => 1, # sequence 0 is the x11 connection handshake
    handles => {
        inc_sequence => 'inc',
    }
);

has '_outstanding_replies' => (
    traits => [ 'Hash' ],
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
    handles => {
        expect_reply => 'set',
        awaiting_reply => 'exists',
        type_of_reply => 'get',
    }
);

has 'output_file' => (
    is => 'rw',
    isa => 'Ref',
    default => sub {
        open(my $fh, '>', 'output.json');
        $fh->autoflush(1);
        # TODO: don't hardcode
        print $fh qq|[\n{"type":"cleverness","id":277, "title":"root", "idtype":"window"},\n|;
        return $fh;
    }
);

# XXX: the following two need to be refactored
has '_in_burst' => (
    traits => [ 'Bool' ],
    is => 'rw',
    isa => 'Bool',
    default => 0,
    handles => {
        start_of_burst => 'set',
        end_of_burst => 'unset',
    }
);
has '_fresh_burst' => (
    traits => [ 'Bool' ],
    is => 'rw',
    isa => 'Bool',
    default => 1,
    handles => {
        make_burst_fresh => 'set',
        burst_data_written => 'unset',
    }
);
has '_current_burst' => (is => 'rw', isa => 'Str');

sub BUILD {
    my ($self) = @_;

    $self->start_timestamp([ gettimeofday ]);
}


sub _new_burst {
    my ($self) = @_;

    my $elapsed = tv_interval($self->start_timestamp);
    $self->_current_burst(qq|{"type":"burst", "elapsed":$elapsed, "packets":[|);
    $self->start_of_burst;
    $self->make_burst_fresh;
}

# just dumps to a file at the moment
sub dump_request {
    my ($self, $data) = @_;
    $data->{type} = 'request';
    $data->{seq} = $self->sequence;
    $data->{elapsed} = tv_interval($self->start_timestamp(), [ gettimeofday ]);
    if (!$self->_fresh_burst) {
        $self->_current_burst($self->_current_burst . ", \n");
    } else {
        $self->burst_data_written;
    }
    $self->_current_burst($self->_current_burst . encode_json($data));

    $self->expect_reply($self->sequence, $data);
    $self->inc_sequence;
}

sub dump_reply {
    my ($self, $data) = @_;

    $data->{type} = 'reply';
    $data->{elapsed} = tv_interval($self->start_timestamp(), [ gettimeofday ]);
    if (!$self->_fresh_burst) {
        $self->_current_burst($self->_current_burst . ", \n");
    } else {
        $self->burst_data_written;
    }
    $self->_current_burst($self->_current_burst . encode_json($data));
}

sub dump_cleverness {
    my ($self, $data) = @_;

    $data->{type} = 'cleverness';
    $data->{elapsed} = tv_interval($self->start_timestamp(), [ gettimeofday ]);
    if (!$self->_fresh_burst) {
        $self->_current_burst($self->_current_burst . ", \n");
    } else {
        $self->burst_data_written;
    }
    $self->_current_burst($self->_current_burst . encode_json($data));
}

sub request_icing {
    my ($self, $data) = @_;

    my $name = $data->{name};
    my %d = %{$data->{moredetails}};

    say "icing for $name";

    # GetInputFocus has no details
    return '' if $name eq 'GetInputFocus';

    # display the ASCII names of atoms and extensions
    return $d{name} if $name eq 'InternAtom';
    return $d{name} if $name eq 'QueryExtension';

    # display translated X11 IDs
    if ($name eq 'GetProperty') {
        my $property = $d{property};
        my $window = $d{window};
        if ($self->xid_known($property)) {
            $property = $self->id_for_xid($property);
        }
        $data->{_references} = [ $property, $window ];
        return "%$property% of %$window%";
    }

    if ($name eq 'GetGeometry') {
        my $drawable = $d{drawable};
        if ($self->xid_known($drawable)) {
            $drawable = $self->id_for_xid($drawable);
        }
        return "%$drawable%";
    }

    if ($name eq 'TranslateCoordinates') {
        my $src = $d{src_window};
        my $dst = $d{dst_window};
        my $src_x = $d{src_x};
        my $src_y = $d{src_y};
        # TODO: translate

        # TODO: better description?
        return "($src_x, $src_y) from %$src% to %$dst%";
    }

    if ($name eq 'QueryTree') {
        my $window = $d{window};
        # TODO: translate

        return "%$window%";
    }

    undef
}

sub handle_request {
    my ($self, $request) = @_;

    my ($opcode) = unpack('c', $request);

    # TODO: id-magie bei GetWindowAttributes

    my $data = RequestDissector::dissect_request($request);
    if (defined($data) && length($data) > 5) {
        # add the icing to the cake
        my $details = $self->request_icing($data);
        $details = '<strong>NOT YET IMPLEMENTED</strong>' unless defined($details);
        $data->{details} = $details;
        $self->dump_request($data);
        return;
    }
    say "Unhandled event with opcode $opcode";
    $self->inc_sequence;
}

sub handle_error {
    my ($self, $error) = @_;
}

sub handle_reply {
    my ($self, $reply) = @_;

    say "Should dump a reply with length ". length($reply);
    my ($format, $sequence) = unpack('x[c]cS', $reply);
    say "reply format = $format for seq $sequence";
    # TODO: the wrapping of seq ids needs to be handled
    if (!$self->awaiting_reply($sequence)) {
        say "didn't expect that coming";
        return;
    }
    my $data = $self->type_of_reply($sequence);
    my $name = $data->{name};
    say "name = $name";

    if ($name eq 'InternAtom') {
        my ($atom) = unpack('x[ccSL]L', $reply);

        say "\n ADDING MAPPING FROM $atom \n";
        $self->add_mapping($atom, 'atom_' . $atom);

        $self->dump_reply({
            name => $name,
            details => "%atom_$atom%",
            seq => $sequence,
            moredetails => {
                atom => $atom
            }
        });

        $self->dump_cleverness({
            id => 'atom_' . $atom,
            title => $data->{moredetails}->{name},
            idtype => 'atom',
            moredetails => {
                name => $data->{moredetails}->{name}
            }
        });
        return;
    }

    if ($name eq 'GetProperty') {
        my ($type, $bytes_after, $value_len) = unpack('x[ccSL]LLL', $reply);
        say "type = $type, bytes_after = $bytes_after, value_len = $value_len";
        my $val = substr($reply, 32, $value_len);
        say "val = $val";
        $self->dump_reply({
            name => 'Property',
            details => "type $type",
            seq => $sequence,
            moredetails => {
                type => $type,
                data => $val
            }
        });
        return;
    }

    if ($name eq 'GetGeometry') {
        my ($root, $x, $y, $width, $height, $border_width) = unpack('x[ccSL]LssSSS', $reply);
        $self->dump_reply({
            name => 'Geometry',
            details => "($x, $y) $width x $height",
            seq => $sequence,
            moredetails => {
                root => $root,
                x => $x,
                y => $y,
                width => $width,
                height => $height,
                border_width => $border_width
            }
        });
        return;
    }

    if ($name eq 'QueryTree') {
        my ($root, $parent, $children_len) = unpack('x[ccSL]LLS', $reply);
        say "root = $root, parent = $parent, children_len = $children_len";
        # TODO: handle the children list
        return;
    }

    if ($name eq 'TranslateCoordinates') {
        my ($same_screen, $child, $dst_x, $dst_y) = unpack('x[c]cx[SL]LSS', $reply);
        $self->dump_reply({
            name => $name,
            details => "($dst_x, $dst_y)",
            seq => $sequence,
            moredetails => {
                same_screen => $same_screen,
                child => $child,
                dst_x => $dst_x,
                dst_y => $dst_y,
            }
        });
        return;
    }

}

sub handle_event {
    my ($self, $event) = @_;
}

sub now_in_burst {
    my ($self) = @_;

    return if $self->_in_burst;

    $self->_new_burst;
}

sub burst_finished {
    my ($self) = @_;

    my $fh = $self->output_file;
    print $fh $self->_current_burst . "]},";
    $self->end_of_burst;
}

sub client_disconnected {
    my ($self) = @_;

    my $fh = $self->output_file;
    print $fh "]";

}

__PACKAGE__->meta->make_immutable;

1
