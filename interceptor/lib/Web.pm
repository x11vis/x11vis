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
use IO::All;
use v5.10;

get '/' => sub {
    # for now, we redirect to /gui/
    redirect '/gui/';
};

get '/gui/' => sub {
    return io('../gui/poc.html')->slurp;
};

get '/gui/:file' => sub {
    if (params->{file} =~ /\.css$/) {
        header 'Content-Type' => 'text/css';
    }
    #sendfile('../gui/' . params->{file});
    return io('../gui/' . params->{file})->slurp;
};

get '/gen/predefined_atoms.json' => sub {
    header 'Content-Type' => 'application/json';
    return '[' . io('gen/predefined_atoms.json')->slurp . ']';
};

get '/tracedata/output.json' => sub {
    #mime_type 'json' => 'application/json';
    #send_file('/tmp/output.json');
    header 'Content-Type' => 'application/json';
    return '[' . io('output.json')->slurp . ']';
};

get '/templates/:file' => sub {
    return io('../gui/templates/' . params->{file})->slurp;
};

1
