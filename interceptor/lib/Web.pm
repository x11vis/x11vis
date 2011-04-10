# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#
# XXX: This is just a proof of concept implementation to providing the
# XXX: webinterface. It’s quick and dirty and needs to be cleaned up.
#
package Web;

use strict;
use warnings;
use Dancer ':syntax';
use FindBin;
use IO::All;
use v5.10;

set logger => 'console';
set log => 'debug';
set charset => 'utf-8';
set public => "$FindBin::RealBin/../gui/";

get '/' => sub {
    send_file 'poc.html';
};

get '/tracedata/output.json' => sub {
    #mime_type 'json' => 'application/json';
    #send_file('/tmp/output.json');
    header 'Content-Type' => 'application/json';
    return '[' . io('output.json')->slurp . ']';
};

1
