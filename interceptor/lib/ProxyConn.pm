# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#
package ProxyConn;

use strict;
use warnings;
use Data::Dumper;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent;
use Moose;
use PacketHandler;
use v5.10;

has 'fh' => (is => 'ro', isa => 'Ref', required => 1);
has 'conn_id' => (is => 'ro', isa => 'Int', required => 1);
has 'client_handle' => (is => 'rw', isa => 'Ref');
has 'x11_handle' => (is => 'rw', isa => 'Ref', predicate => 'has_x11_handle');
has 'packet_handler' => (
    is => 'rw',
    isa => 'PacketHandler',
);

sub BUILD {
    my ($self) = @_;
    say "new proxyconn built";

    $self->packet_handler(PacketHandler->new(conn_id => $self->conn_id));

    my $handle;
    $handle = AnyEvent::Handle->new(
        fh     => $self->fh,
        on_error => sub {
            warn "Error on client socket: $_[2]\n";
            # Kill x11_handle too (if exists)
            if ($self->has_x11_handle) {
                warn "Closing connection to X11 for this client\n";
                $self->x11_handle->destroy;
            }
            $self->packet_handler->client_disconnected;
            $_[0]->destroy;
        },
        on_eof => sub {
            $handle->destroy; # destroy handle
            warn "done.\n";
        }
    );

    $self->client_handle($handle);

    # Expect 12 bytes (byte order + 11 bytes of request) of protocol setup
    $handle->push_read(chunk => 12, sub { $self->_got_setup_request(@_) });
}

#
# Called when the first 12 bytes were read from the client. They contain a
# setup request consisting of the byte order, expected major/minor version and
# the authentication data.
#
# We establish a connection to X11 and forward everything we got from the
# client. The next step is _got_setup_reply which will be called when X11
# replies to the setup request.
#
sub _got_setup_request {
    my ($self, $handle, $request) = @_;

    my ($byteorder, $pad0, $major, $minor, $auth_name_len, $auth_data_len) = unpack('ccSSSS', $request);
    say "byteorder = $byteorder, major = $major, minor = $minor, auth name len = $auth_name_len, auth data len = $auth_data_len";

    # TODO: socket path
    tcp_connect "unix/", "/tmp/.X11-unix/X0", sub {
        # TODO: handle errors when connecting
        my ($fh) = @_;

        say "connected";
        my $x11;
        $x11 = AnyEvent::Handle->new(
            fh => $fh,
            on_error => sub {
                warn "error (x11) $_[2]\n";
                $_[0]->destroy;
            },
            on_eof => sub {
                $x11->destroy;
                warn "done (x11)";
            }
        );

        $self->x11_handle($x11);

        # forward the request to the X11 server
        say "pushing req now";
        $x11->push_write($request);
        $x11->push_read(chunk => 8, sub { $self->_got_setup_reply(@_) });

        # TODO: why + 2? padding until it reaches 4, i guess
        my $comb = ($auth_name_len ) + 2 + ($auth_data_len );
        if ($auth_data_len == 0 && $auth_name_len == 0) {
            say "auth null, not reading";
            return;
        }
        $handle->push_read(chunk => $comb, sub {
            my ($handle, $auth) = @_;
            say "got auth, sending";
            $x11->push_write($auth);
        });
    };
}

#
# Called when X11 replied to the setup request. There are three cases:
# 1) Everything went fine. In that case we forward the reply (plus all the
#    server info) to the client, then call _push_client_read and _push_x11_read
#    to handle data flowing in both directions.
#
# 2) Authentication failed for some reason. We display an error and exit.
#
# 3) Two-step authentication is required (Kerberos for example). We don’t
#    support that.
#
sub _got_setup_reply {
    my ($self, $x11, $reply) = @_;

    my ($status, $words) = unpack('cx[cSS]S', $reply);
    my $length = ($words * 4);

    # failed
    if ($status == 0) {
        say "setup failed answer:";
        $x11->push_read(chunk => $length, sub {
            my ($x11, $errormsg) = @_;

            say "error authenticating at the X11 server: $errormsg";
            exit 0;
        });
        return;
    }

    if ($status == 1) {
        # see xcb_setup_t, should we ever want to display some parts of $reply

        say "[conn] successfully authenticated";
        $self->client_handle->push_write($reply);
        $x11->push_read(
            chunk => $length,
            sub {
                my ($x11, $chunk) = @_;
                $self->client_handle->push_write($chunk);
                $self->_push_client_read;
                $self->_push_x11_read;
            }
        );
        return;
    }

    if ($status == 2) {
        print STDERR "Two-part authentication is not implemented\n";
        exit 1;
    }
}

#
# Read 4 bytes (and possibly more, depending on the request), then call
# _pkt_to_server
#
sub _push_client_read {
    my ($self) = @_;

    $self->client_handle->push_read(
        chunk => 4,
        sub {
            my ($handle, $header) = @_;

            my ($words) = unpack('x[cc]S', $header);
            my $length = (($words * 4) - 4);
            if ($length == 0) {
                # request is only 4 bytes long, immediately call _pkt_to_server
                #say "complete, sending now";
                $self->_pkt_to_server($handle, $header);
                $self->_push_client_read;
                return;
            }
            #say "waiting for length $length";
            $handle->push_read(chunk => $length, sub {
                my ($handle, $request) = @_;

                #say "got complete req";
                $self->_pkt_to_server($handle, $header . $request);
                $self->_push_client_read;
            });
        }
    );
}

#
# Read 32 bytes (and possibly more in the handler), then call _pkt_from_server
#
sub _push_x11_read {
    my ($self) = @_;

    $self->x11_handle->push_read(
        chunk => 32,
        sub {
            my ($x11, $packet) = @_;

            my ($type, $words) = unpack('cx[ccc]L', $packet);
            my $length = ($words * 4);
            #say "additional length = " . $length;

            # Only replies (type 1) can have additional bytes
            if ($type != 1 || $length == 0) {
                #say "no additional bytes, sending now";
                $self->_pkt_from_server($x11, $packet);
                $self->_push_x11_read;
                return;
            }

            $x11->push_read(chunk => $length, sub {
                my ($x11, $rest) = @_;

                #say "got additional bytes, sending to client";
                $self->_pkt_from_server($x11, $packet . $rest);
                $self->_push_x11_read;
            });
        }
    );
}

#
# Packet from client to X11 server
#
sub _pkt_to_server {
    my ($self, $handle, $packet) = @_;

    my $ph = $self->packet_handler;

    # make sure we are in a burst currently (starts a new one when first invoked)
    $ph->child_burst->ensure_in_burst;

    $self->x11_handle->push_write($packet);

    $ph->handle_request($packet);
    $ph->child_burst->finish if length($handle->{rbuf}) == 0;
}

sub _pkt_from_server {
    my ($self, $x11, $packet) = @_;

    $self->client_handle->push_write($packet);

    my $ph = $self->packet_handler;

    # make sure we are in a burst currently (starts a new one when first invoked)
    $ph->x11_burst->ensure_in_burst;

    my ($type) = unpack('c', $packet);

    if ($type == 0) {
        $ph->handle_error($packet);
    } elsif ($type == 1) {
        $ph->handle_reply($packet);
    } else {
        $ph->handle_event($packet);
    }
    $ph->x11_burst->finish if length($x11->{rbuf}) == 0;
}

__PACKAGE__->meta->make_immutable;

1
