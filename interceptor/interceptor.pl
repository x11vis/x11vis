#!/usr/bin/env perl
# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#

use strict;
use warnings;
use AnyEvent::Socket;
use AnyEvent;
use lib qw(lib);
use ProxyConn;
use v5.10;

# provide /tmp/.X11-unix/X8
my $server = tcp_server "unix/", "/tmp/.X11-unix/X8", sub {
    my ($fh, $host, $port) = @_;

    ProxyConn->new(
        fh => $fh,
        host => $host,
        port => $port
    );
}, sub {
    my ($fh, $thishost, $thisport) = @_;
    warn "bound to $thishost, port $thisport\n";
};

AE->cv->recv
