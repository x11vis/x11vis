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
use FindBin;
use lib "$FindBin::RealBin/gen/";
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

# shortcut which retuns a formatted ID (within % signs)
sub id {
    return '%' . $mappings->id_for(@_) . '%';
}

sub reply_icing {
    my ($self, $data) = @_;

    my $name = $data->{name};
    my %d = %{$data->{moredetails}};

    #say "(reply) icing for $name, data = " . Dumper(\%d);
    my $req_data = $self->type_of_reply($data->{seq});
    my %rd = %{$req_data->{moredetails}};

    return id($d{focus} => 'window') if $name eq 'GetInputFocus';

    if ($name eq 'InternAtom') {
        $mappings->add_atom($rd{name} => $d{atom});
        my $id = $mappings->id_for($d{atom}, 'atom');
        $self->dump_cleverness({
            id => $id,
            title => $rd{name},
            idtype => 'atom',
            moredetails => {
                name => $rd{name},
            }
        });
        return id($d{atom} => 'atom');
    }

    if ($name eq 'GetAtomName') {
        $mappings->add_atom($d{name} => $rd{atom});
        my $id = $mappings->id_for($rd{atom} => 'atom');
        $self->dump_cleverness({
            id => $id,
            title => $d{name},
            idtype => 'atom',
            moredetails => {
                name => $d{name},
            }
        });
        return "$d{name}";
    }

    if ($name eq 'GetGeometry') {
        return id($rd{drawable}) . " ($d{x}, $d{y}) $d{width} x $d{height}";
    }

    if ($name eq 'TranslateCoordinates') {
        return "($d{dst_x}, $d{dst_y}) on " . id($rd{dst_window});
    }

    if ($name eq 'GetWindowAttributes') {
        return id($rd{window}) . " class $d{class}, state $d{map_state}, o_redir $d{override_redirect}";
    }

    if ($name eq 'QueryBestSize') {
        return "$d{width} x $d{height}";
    }

    if ($name eq 'ListExtensions') {
        return join(', ', map { $_->{name} } @{$d{names}});
    }

    if ($name eq 'ListProperties') {
        return id($rd{window} => 'window') . ' has ' . join(', ', map { id($_ => 'atom') } @{$d{atoms}});
    }

    if ($name eq 'GetProperty') {
        my $atom = $mappings->get_atom_xid('WM_NAME');
        if (defined($atom) && $atom == $rd{property} && $d{type} != 0) {
            $self->dump_cleverness({
                id => $mappings->id_for($rd{window}, 'window'),
                title => $d{value},
                idtype => 'window',
                moredetails => {
                    name => $d{value},
                }
            });
        }
        my $details = id($rd{property} => 'atom');
        if ($d{type} == 0) {
            $details .= ' is not set';
        } else {
            $details .= " = $d{value} (type " . id($d{type} => 'atom') . ')';
        }
        return $details . ' on ' . id($rd{window} => 'window');
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
    my @no_details = qw(GetInputFocus GetModifierMapping ListExtensions);
    return '' if $name ~~ @no_details;

    # display the ASCII names of atoms and extensions
    return $d{name} if $name eq 'InternAtom';
    return id($d{atom} => 'atom') if $name eq 'GetAtomName';
    return $d{name} if $name eq 'QueryExtension';
    return id($d{focus} => 'window') if $name eq 'SetInputFocus';

    my @single_window = qw(MapWindow MapSubWindows DestroySubwindows UnmapWindow ListProperties);
    return id($d{window} => 'window') if $name ~~ @single_window;

    if ($name eq 'DestroyWindow') {
        my $win = $mappings->id_for($d{window}, 'window');
        $mappings->delete_mapping($d{window});
        return "%$win%";
    }

    if ($name eq 'GrabKey') {
        # TODO: modifier human readable
        return "$d{key} on " . id($d{grab_window} => 'window');
    }

    if ($name eq 'GrabButton') {
        return "button $d{button} on " . id($d{grab_window}, 'window');
    }

    if ($name eq 'CopyArea') {
        return "$d{width} x $d{height} from " . id($d{src_drawable}) .
               " ($d{src_x}, $d{src_y}) to " . id($d{dst_drawable}) .
               " ($d{dst_x}, $d{dst_y})";
    }

    if ($name eq 'PolyFillRectangle') {
        return (scalar @{$d{rectangles}}) . " rects on " . id($d{drawable});
    }

    if ($name eq 'PolyLine') {
        return (scalar @{$d{points}}) . " points on " . id($d{drawable});
    }

    if ($name eq 'PolySegment') {
        return (scalar @{$d{segments}}) . " segments on " . id($d{drawable});
    }

    if ($name eq 'FillPoly') {
        return (scalar @{$d{points}}) . " points on " . id($d{drawable});
    }

    if ($name eq 'CreateWindow') {
        return id($d{wid} => 'window') . ' (parent ' . id($d{parent} => 'window') . ") ($d{x}, $d{y}) $d{width} x $d{height}";
    }

    if ($name eq 'GetWindowAttributes') {
        return id($d{window} => 'window');
    }

    if ($name eq 'ReparentWindow') {
        return id($d{window} => 'window') . ' into ' . id($d{parent} => 'window') . " at ($d{x}, $d{y})";
    }

    if ($name eq 'ChangeSaveSet') {
        return "$d{mode} " . id($d{window} => 'window');
    }

    if ($name eq 'GetKeyboardMapping') {
        return "$d{count} codes starting from $d{first_keycode}"
    }

    if ($name eq 'OpenFont') {
        my $id = $mappings->id_for($d{fid} => 'font');
        $self->dump_cleverness({
            id => $id,
            title => $d{name},
            idtype => 'font',
        });
        return "%$id%";
    }

    if ($name eq 'ListFontsWithInfo' ||
        $name eq 'ListFonts') {
        return "$d{pattern}";
    }

    if ($name eq 'QueryFont') {
        return id($d{font} => 'font');
    }

    # display translated X11 IDs
    if ($name eq 'GetProperty') {
        my $property = id($d{property} => 'atom');
        my $window = id($d{window} => 'window');
        $data->{_references} = [ $property, $window ];
        return "$property of $window";
    }

    if ($name eq 'GetGeometry') {
        return id($d{drawable});
    }

    if ($name eq 'TranslateCoordinates') {
        my $src = id($d{src_window});
        my $dst = id($d{dst_window});
        my $src_x = $d{src_x};
        my $src_y = $d{src_y};

        # TODO: better description?
        return "($src_x, $src_y) from $src to $dst";
    }

    if ($name eq 'QueryTree') {
        return id($d{window} => 'window');
    }

    if ($name eq 'CreatePixmap') {
        return id($d{pid} => 'pixmap') . ' on ' . id($d{drawable}) . " ($d{width} x $d{height})";
    }

    if ($name eq 'CreateGC') {
        return id($d{cid} => 'gcontext') . ' on ' . id($d{drawable});
    }

    if ($name eq 'ChangeWindowAttributes') {
        my $details = id($d{window} => 'window');
        delete $d{window};
        delete $d{value_mask};
        say "left:" . Dumper(\%d);
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
        my $details = id($d{window} => 'window');
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
        my $win = $mappings->id_for($d{window}, 'window');
        my $atom = $mappings->get_atom_xid('WM_NAME');
        if (defined($atom) && $atom == $d{property}) {
            $self->dump_cleverness({
                id => $win,
                title => $d{data},
                idtype => 'window',
                moredetails => {
                    name => $d{data},
                }
            });
        }
        return id($d{property} => 'atom') . " on %$win%";
    }

    if ($name eq 'FreePixmap') {
        my $details = id($d{pixmap} => 'pixmap');
        $mappings->delete_mapping($d{pixmap});
        return $details;
    }

    if ($name eq 'FreeGC') {
        my $details = id($d{gc} => 'gcontext');
        $mappings->delete_mapping($d{gc});
        return $details;
    }

    if ($name eq 'CloseFont') {
        my $details = id($d{font} => 'font');
        $mappings->delete_mapping($d{font});
        return $details;
    }

    if ($name eq 'ImageText8') {
        # TODO: ellipsize
        return id($d{drawable}) . " at $d{x}, $d{y}: $d{string}";
    }

    if ($name eq 'ClearArea') {
        return id($d{window} => 'window') . " ($d{x}, $d{y}) $d{width} x $d{height}";
    }

    if ($name eq 'UngrabKey') {
        # TODO: modifier
        return "$d{key} on " . id($d{grab_window});
    }

    if ($name eq 'QueryBestSize') {
        if ($d{class} eq 'LargestCursor') {
            return 'largest cursor size on ' . id($d{drawable} => 'window');
        }
    }

    undef
}

sub event_icing {
    my ($self, $data) = @_;

    my $name = $data->{name};
    my %d = %{$data->{moredetails}};

    say "(event) icing for $name";

    if ($name eq 'MapNotify') {
        return id($d{window} => 'window');
    }

    if ($name eq 'MapRequest') {
        return id($d{window} => 'window') . ' (parent ' . id($d{parent} => 'window') . ')';
    }

    if ($name eq 'PropertyNotify') {
        return id($d{atom} => 'atom') . ' on ' . id($d{window} => 'window');
    }

    if ($name eq 'ConfigureNotify') {
        return id($d{window} => 'window') . " ($d{x}, $d{y}) $d{width} x $d{height}";
    }

    if ($name eq 'Expose') {
        return id($d{window} => 'window') . " ($d{x}, $d{y}) $d{width} x $d{height}, $d{count} following";
    }

    if ($name eq 'FocusIn') {
        return id($d{event} => 'window') . " (mode = $d{mode}, detail = $d{detail})";
    }

    if ($name eq 'ReparentNotify') {
        return id($d{window} => 'window') . ' now in ' . id($d{parent} => 'window') . " at ($d{x}, $d{y})";
    }

    if ($name eq 'NoExposure') {
        return id($d{drawable});
    }

    if ($name eq 'VisibilityNotify') {
        return id($d{window} => 'window') . " $d{state}";
    }

    if ($name eq 'MappingNotify') {
        return "$d{request}";
    }

    if ($name eq 'EnterNotify') {
        return id($d{event} => 'event') . " at ($d{event_x}, $d{event_y})";
    }

    if ($name eq 'KeyPress') {
        return "key $d{detail} on " . id($d{event});
    }

    if ($name eq 'UnmapNotify') {
        return id($d{window} => 'window');
    }

    # TODO: MotionNotify

    undef
}

sub handle_request {
    my ($self, $request) = @_;

    my ($opcode) = unpack('c', $request);

    say "Handling request opcode $opcode";

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
        #say "data = " . Dumper($data);
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
