#!/usr/bin/env perl
# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#

use strict;
use warnings;
use Socket qw(sockaddr_in SOL_SOCKET SO_PEERCRED);
use AnyEvent::Socket;
use AnyEvent;
use Twiggy::Server;
use FindBin;
use lib "$FindBin::RealBin/lib/";
use ProxyConn;
use IPCConn;
use Web;
use IO::Handle;
use IO::All;
use JSON::XS;
use v5.10;

my $conn_id = 0;

# provide /tmp/.X11-unix/X8
my $server = tcp_server "unix/", "/tmp/.X11-unix/X8", sub {
    my ($fh, $host, $port) = @_;

    say "fh = $fh, fileno = " . $fh->fileno;

    # struct ucred, containing a pid_t, uid_t, gid_t
    my $peercred = getsockopt($fh, SOL_SOCKET, SO_PEERCRED);
    my $remote_pid = unpack("L", $peercred);
    my $cmdline = io("/proc/$remote_pid/cmdline")->slurp;
    $cmdline =~ s/\0/ /g;

    my $data = {
        type => 'cleverness',
        elapsed => 0,
        id => 'conn_' . $conn_id,
        title => $cmdline,
        idtype => 'connection',
        moredetails => {
            cmdline => $cmdline
        }
    };
    FileOutput->instance->write(encode_json($data));

    ProxyConn->new(
        fh => $fh,
        conn_id => $conn_id,
        host => $host,
        port => $port
    );

    $conn_id++;
}, sub {
    my ($fh, $thishost, $thisport) = @_;
    warn "bound to $thishost, port $thisport\n";
};

# TODO: configurable path
my $ipc_server = tcp_server "unix/", "/tmp/x11vis.sock", sub {
    my ($fh, $host, $port) = @_;

    say "new ipc client";
    IPCConn->new(
        fh => $fh
    );
}, sub {
    my ($fh, $thishost, $thisport) = @_;
    warn "(unix-ipc) bound to $thishost, port $thisport\n";
};

# setup the web interface
my $twiggy = Twiggy::Server->new(
    host => '0.0.0.0',
    port => '5523'
);

my $app = sub {
    my $env = shift;
    my $req = Dancer::Request->new(env => $env);
    Dancer->dance($req);
};

$twiggy->register_service($app);
warn "(http) bound to $$twiggy{host}, port $$twiggy{port}\n";

AE->cv->recv
