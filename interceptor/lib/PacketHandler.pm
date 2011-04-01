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
use Burst;
use lib qw(gen);
use RequestDissector;
use ReplyDissector;
use EventDissector;
use ErrorDissector;
use Mappings;
use FileOutput;
use v5.10;

with 'Elapsed';

has 'conn_id' => (is => 'ro', isa => 'Int', required => 1);

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

has [ 'child_burst', 'x11_burst' ] => (
    is => 'rw',
    isa => 'Burst',
);

# shortcut to the Mappings singleton
my $mappings = Mappings->instance;

sub BUILD {
    my ($self) = @_;
    $self->child_burst(Burst->new(conn_id => $self->conn_id));
    $self->x11_burst(Burst->new(conn_id => $self->conn_id));
}

sub dump_request {
    my ($self, $data) = @_;
    $data->{type} = 'request';
    $data->{seq} = $self->sequence;
    $data->{elapsed} = $self->elapsed;
    $self->child_burst->add_packet(encode_json($data));
    $self->expect_reply($self->sequence, $data);
    $self->inc_sequence;
}

sub dump_reply {
    my ($self, $data) = @_;

    $data->{type} = 'reply';
    $data->{elapsed} = $self->elapsed;
    $self->x11_burst->add_packet(encode_json($data));
}

sub dump_event {
    my ($self, $data) = @_;

    $data->{type} = 'event';
    $data->{elapsed} = $self->elapsed;
    $self->x11_burst->add_packet(encode_json($data));
}

sub dump_error {
    my ($self, $data) = @_;

    $data->{type} = 'error';
    $data->{elapsed} = $self->elapsed;
    $self->x11_burst->add_packet(encode_json($data));
}

sub dump_cleverness {
    my ($self, $data) = @_;

    $data->{type} = 'cleverness';
    $data->{elapsed} = $self->elapsed;
    FileOutput->instance->write(encode_json($data));
}

sub reply_icing {
    my ($self, $data) = @_;

    my $name = $data->{name};
    my %d = %{$data->{moredetails}};

    say "(reply) icing for $name, data = " . Dumper(\%d);
    my $req_data = $self->type_of_reply($data->{seq});
    my %rd = %{$req_data->{moredetails}};

    return "%$d{focus}%" if $name eq 'GetInputFocus';

    if ($name eq 'InternAtom') {
        $mappings->add_atom($rd{name} => $d{atom});
        $self->add_mapping($d{atom}, 'atom_' . $d{atom});
        $self->dump_cleverness({
            id => 'atom_' . $d{atom},
            title => $req_data->{moredetails}->{name},
            idtype => 'atom',
            moredetails => {
                name => $req_data->{moredetails}->{name}
            }
        });
        return "%atom_" . $d{atom} . "%";
    }

    if ($name eq 'GetAtomName') {
        # TODO: update mapping
        return "$d{$name}";
    }

    if ($name eq 'GetGeometry') {
        return "%$rd{drawable}% ($d{x}, $d{y}) $d{width} x $d{height}";
    }

    if ($name eq 'TranslateCoordinates') {
        return "($d{dst_x}, $d{dst_y}) on %$rd{dst_window}%";
    }

    if ($name eq 'GetProperty') {
        my $atom = $mappings->get_atom_xid('WM_NAME');
        if (defined($atom) && $atom == $rd{property}) {
            $self->dump_cleverness({
                id => $req_data->{moredetails}->{window},
                title => $d{value},
                idtype => 'window',
                moredetails => {
                    name => $d{value},
                }
            });
        }
        #if ($d{value} == 0) {
        #    return 'not set';
        #} else {
            return $d{value} . ' (type %atom_' . $d{type} . '%)';
        #}
    }

    if ($name eq 'QueryTree') {
        return "(" . (scalar @{$d{children}}) . ' children)';
    }

    if ($name eq 'QueryExtension') {
        return "$rd{name} " . ($d{present} ? 'present' : 'not present');
    }

    undef;
}

sub request_icing {
    my ($self, $data) = @_;

    my $name = $data->{name};
    my %d = %{$data->{moredetails}};

    say "icing for $name, data = " . Dumper($data);

    # these requests have no details
    return '' if $name eq 'GetInputFocus';
    return '' if $name eq 'GetModifierMapping';

    # display the ASCII names of atoms and extensions
    return $d{name} if $name eq 'InternAtom';
    return "%atom_$d{atom}%" if $name eq 'GetAtomName';
    return $d{name} if $name eq 'QueryExtension';
    return "%$d{focus}%" if $name eq 'SetInputFocus';

    my @single_window = qw(MapWindow DestroyWindow DestroySubwindows UnmapWindow);
    return "%$d{window}%" if $name ~~ @single_window;

    if ($name eq 'GrabKey') {
        # TODO: modifier human readable
        return "$d{key} on %$d{grab_window}%";
    }

    if ($name eq 'GrabButton') {
        return "button $d{button} on %$d{grab_window}%";
    }

    if ($name eq 'CopyArea') {
        return "$d{width} x $d{height} from %$d{src_drawable}% ($d{src_x}, $d{src_y}) to %$d{dst_drawable}% ($d{dst_x}, $d{dst_y})";
    }

    if ($name eq 'PolyFillRectangle') {
        return (scalar @{$d{rectangles}}) . " rects on %$d{drawable}%";
    }

    if ($name eq 'PolyLine') {
        return (scalar @{$d{points}}) . " points on %$d{drawable}%";
    }

    if ($name eq 'PolySegment') {
        return (scalar @{$d{segments}}) . " segments on %$d{drawable}%";
    }

    if ($name eq 'FillPoly') {
        return (scalar @{$d{points}}) . " points on %$d{drawable}%";
    }

    if ($name eq 'CreateWindow') {
        # TODO: save id
        return "%$d{wid}% (parent %$d{parent}%) ($d{x}, $d{y}) $d{width} x $d{height}";
    }

    if ($name eq 'GetWindowAttributes') {
        return "%$d{window}%";
    }

    if ($name eq 'ReparentWindow') {
        return "%$d{window}% into %$d{parent}% at ($d{x}, $d{y})";
    }

    if ($name eq 'ChangeSaveSet') {
        return "$d{mode} %$d{window}%";
    }

    if ($name eq 'GetKeyboardMapping') {
        return "$d{count} codes starting from $d{first_keycode}"
    }

    if ($name eq 'OpenFont') {
        # TODO: save id $d{fid}
        return "$d{name}";
    }

    if ($name eq 'ListFontsWithInfo' ||
        $name eq 'ListFonts') {
        return "$d{pattern}";
    }

    if ($name eq 'QueryFont') {
        return "%$d{font}%";
    }

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

    if ($name eq 'CreatePixmap') {
        return "%$d{pid}% on %$d{drawable}% ($d{width} x $d{height})";
    }

    if ($name eq 'CreateGC') {
        return "%$d{cid}% on %$d{drawable}%";
    }

    if ($name eq 'ChangeWindowAttributes') {
        my $window = $d{window};
        delete $d{window};
        say "left:" . Dumper(\%d);
        my $details = "%$window%";
        if ((keys %d) == 1) {
            my $key = (keys %d)[0];
            if (ref($d{$key}) eq 'ARRAY') {
                $details .= " $key=" . join(', ', @{$d{$key}});
            } else {
                $details .= " $key=$d{$key}";
            }
        }
        return $details;
    }

    if ($name eq 'ConfigureWindow') {
        my $details = "%$d{window}%";
        if (exists $d{x} && exists $d{y}) {
            $details .= " ($d{x}, $d{y})";
        }
        # TODO: single of x, y, w, h
        if (exists $d{width} && exists $d{height}) {
            $details .= " $d{width} x $d{height}";
        }
        return $details;
    }

    if ($name eq 'ChangeProperty') {
        my $atom = $mappings->get_atom_xid('WM_NAME');
        if (defined($atom) && $atom == $d{property}) {
            $self->dump_cleverness({
                id => $d{window},
                title => $d{data},
                idtype => 'window',
                moredetails => {
                    name => $d{data},
                }
            });
        }
        # TODO
        return "%atom_$d{property}% on %$d{window}%";

#        mode => $mode,
#        window => $window,
#        property => $property,
#        type => $type,
#        format => $format,
#        data_len => $data_len,
#        data => $data,

    }

    if ($name eq 'FreePixmap') {
        # TODO: id cleanup
        return "%$d{pixmap}%";
    }

    if ($name eq 'FreeGC') {
        # TODO: id cleanup
        return "%$d{gc}%";
    }

    if ($name eq 'CloseFont') {
        # TODO: id cleanup
        return "%$d{font}%";
    }

    if ($name eq 'ImageText8') {
        # TODO: ellipsize
        return "%$d{drawable}% at $d{x}, $d{y}: $d{string}";
    }

    if ($name eq 'ClearArea') {
        return "%$d{window}% ($d{x}, $d{y}) $d{width} x $d{height}";
    }

    if ($name eq 'UngrabKey') {
        # TODO: modifier
        return "$d{key} on %$d{grab_window}%";
    }


    # TODO: UnmapWindow

    undef
}

sub event_icing {
    my ($self, $data) = @_;

    my $name = $data->{name};
    my %d = %{$data->{moredetails}};

    say "(event) icing for $name";

    if ($name eq 'MapNotify') {
        return "%$d{window}%";
    }

    if ($name eq 'MapRequest') {
        return "%$d{window}% (parent %$d{parent}%)";
    }

    if ($name eq 'PropertyNotify') {
        return "%atom_$d{atom}% on %$d{window}%"
    }

    if ($name eq 'ConfigureNotify') {
        return "%$d{window}% ($d{x}, $d{y}) $d{width} x $d{height}";
    }

    if ($name eq 'Expose') {
        return "%$d{window}% ($d{x}, $d{y}) $d{width} x $d{height}, $d{count} following";
    }

    if ($name eq 'FocusIn') {
        return "%$d{event}% (mode = $d{mode}, detail = $d{detail})";
    }

    if ($name eq 'ReparentNotify') {
        return "%$d{window}% now in %$d{parent}% at ($d{x}, $d{y})";
    }

    if ($name eq 'NoExposure') {
        return "%$d{drawable}%";
    }

    if ($name eq 'VisibilityNotify') {
        return "%$d{window}% $d{state}";
    }

    if ($name eq 'MappingNotify') {
        return "$d{request}";
    }

    if ($name eq 'EnterNotify') {
        return "%$d{event}% at ($d{event_x}, $d{event_y})";
    }

    if ($name eq 'KeyPress') {
        return "key $d{detail} on %$d{event}%";
    }

    if ($name eq 'UnmapNotify') {
        return "%$d{window}%";
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
    say "Unhandled request with opcode $opcode";
    $self->inc_sequence;
}

sub handle_error {
    my ($self, $error) = @_;

    say "handling error";

    my $data = ErrorDissector::dissect_error($error, $self);
    if (defined($data) && length($data) > 5) {
        # add the icing to the cake
        #my $details = $self->error_icing($data);
        my $details = undef;
        $details = '<strong>NOT YET IMPLEMENTED</strong>' unless defined($details);
        $data->{details} = $details;
        $self->dump_error($data);
        return;
    }
    say "Unhandled error";
}

sub handle_reply {
    my ($self, $reply) = @_;

    say "Should dump a reply with length ". length($reply);

    my $data = ReplyDissector::dissect_reply($reply, $self);
    if (defined($data) && length($data) > 5) {
        say "data = " . Dumper($data);
        ## add the icing to the cake
        my $details = $self->reply_icing($data);
        $details = '<strong>NOT YET IMPLEMENTED</strong>' unless defined($details);
        $data->{details} = $details;
        $self->dump_reply($data);
        return;
    }
    return;
}

sub handle_event {
    my ($self, $event) = @_;

    my ($number) = unpack('c', $event);

    say "Should dump an event with length ". length($event);

    my $data = EventDissector::dissect_event($event, $self);
    if (defined($data) && length($data) > 5) {
        say "data = " . Dumper($data);
        ## add the icing to the cake
        my $details = $self->event_icing($data);
        $details = '<strong>NOT YET IMPLEMENTED</strong>' unless defined($details);
        $data->{details} = $details;
        $self->dump_event($data);
        return;
    }

    say "Unhandled event with number $number";
    return;
}

sub client_disconnected {
    my ($self) = @_;

    my $fo = FileOutput->instance;
    my $fh = $fo->output_file;
    #print $fh "]";

}

__PACKAGE__->meta->make_immutable;

1
