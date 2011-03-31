# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#
package IPCConn;

use strict;
use warnings;
use Data::Dumper;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent;
use JSON::XS;
use Moose;
use PacketHandler;
use v5.10;

with 'Elapsed';

has 'fh' => (is => 'ro', isa => 'Ref', required => 1);
has 'client_handle' => (is => 'rw', isa => 'Ref');

sub BUILD {
    my ($self) = @_;
    say "new ipcconn built";

    my $handle;
    $handle = AnyEvent::Handle->new(
        fh     => $self->fh,
        on_error => sub {
            warn "Error on client socket: $_[2]\n";
            $_[0]->destroy;
        },
        on_eof => sub {
            $handle->destroy; # destroy handle
            warn "done.\n";
        }
    );

    $self->client_handle($handle);

    $handle->push_read(line => sub { $self->_got_line(@_) });
}

sub _got_line {
    my ($self, $handle, $line) = @_;

    say "ipc line = $line";

    my $json = decode_json($line);
    if ($json->{type} eq 'marker') {
        say "marker: " . $json->{marker};

        my $data = {
            type => 'marker',
            elapsed => $self->elapsed,
            # TODO: we want the overall elapsed time, not only for this ipcconn
            title => $json->{marker},
            from => $json->{source},
        };
        FileOutput->instance->write(encode_json($data));

        $handle->push_write(encode_json({ ack => JSON::XS::true }) . "\n");
    } else {
        warn "Unknown IPC request";
        $handle->push_write(encode_json({ ack => JSON::XS::false }) . "\n");
    }

    $handle->push_read(line => sub { $self->_got_line(@_) });
}

__PACKAGE__->meta->make_immutable;

1
