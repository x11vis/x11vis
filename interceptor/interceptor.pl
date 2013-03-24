#!/usr/bin/env perl
# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#

use strict;
use warnings;
use Socket qw(sockaddr_in);
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
use Getopt::Long qw(GetOptions);
use v5.10;

#
# Figure out the cmdline of the remote endpoint of the given TCP socket file
# descriptor $fileno by examining /proc/ (only works if the endpoint is on
# the local system, of course)
#
sub endpoint_cmdline {
    my ($fh) = @_;

    if (-e '/proc/net/tcp') { # a Linuxism
	my ($port, $addr) = sockaddr_in(getpeername($fh));
	my @bytes = unpack('C4', $addr);
	my $remote = sprintf("%02X%02X%02X%02X:%04X",
            $bytes[3], $bytes[2], $bytes[1], $bytes[0], $port);

	# get the info line from /proc/net/tcp for the remote endpoint
	my ($info) = grep { /^\s+[^:]+: \b$remote\b/ } io('/proc/net/tcp')->slurp;

	# extract the inode of the remote endpoint
	$info =~ s/^\s+//g;
	$info =~ s/\s+/ /g;
	my $remote_inode = (split(/ /, $info))[9];

	# find the corresponding process which has a link to this inode
	for (</proc/*/fd/*>) {
	    my $target = readlink or next;
	    next unless $target =~ /^socket:\[$remote_inode\]$/;
	    my ($pid) = ($_ =~ m,/proc/([0-9]+)/,);
	    # return its commandline
	    my $cmdline = io("/proc/$pid/cmdline")->slurp;
	    $cmdline =~ s/\0/ /g;
	    return $cmdline;
	}
    }

    return '<fd ' . $fh->fileno . '>';
}


## provide /tmp/.X11-unix/X8
#my $server = tcp_server "unix/", "/tmp/.X11-unix/X7", sub {
#    my ($fh, $host, $port) = @_;
#
#    say "fh = $fh, fileno = " . $fh->fileno;
#
#    ProxyConn->new(
#        fh => $fh,
#        host => $host,
#        port => $port
#    );
#}, sub {
#    my ($fh, $thishost, $thisport) = @_;
#    warn "bound to $thishost, port $thisport\n";
#};

my $server_ip = '127.0.0.1';
my $server_port = '6000';
GetOptions("display=s" => sub {
	       if ($_[1] !~ m{^(.*):(\d+(?:\.\d+)?)$}) {
		   die "Cannot parse '$_[1]', use something like 127.0.0.1:0\n";
	       }
	       $server_ip = $1;
	       $server_port = 6000 + $2;
	   })
    or die "usage: $0 [--display=host:port]\n";

my $conn_id = 0;

# We need to use TCP so that we can do a remote endpoint lookup
my $tcp_server = tcp_server $server_ip, $server_port, sub {
    my ($fh, $host, $port) = @_;

    my $cmdline = endpoint_cmdline($fh);
    say "cmdline = $cmdline";
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
    warn "(tcp) bound to $thishost, port $thisport\n";
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
