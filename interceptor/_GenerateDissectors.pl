#!/usr/bin/env perl
# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#

use strict;
use warnings;
use Data::Dumper;
use XML::Twig;
use List::Util qw(sum);
use v5.10;

say "reading in XML";

$Data::Dumper::Maxdepth = 2;

open my $fh, '>', 'gen/RequestDissector.pm';
say $fh 'package RequestDissector;';
say $fh 'use Moose;';
say $fh '';
say $fh 'sub dissect_request {';
say $fh '  my ($request) = @_;';
say $fh '  my ($opcode) = unpack("c", $request);';

my $xml = XML::Twig->new();
$xml->parsefile('/usr/share/xcb/xproto.xml');

sub packfmt_to_bytes {
    my ($fmt) = @_;

    my %bytetbl = (
        c => 1,
        x => 1,
        s => 2,
        S => 2,
        L => 4,
        '' => 0,
    );

    my $result = sum map { $bytetbl{$_} } split(//, $fmt);
    return $result || 0;
}

sub handle_field {
    my ($el) = @_;

    if ($el->tag eq 'pad') {
        my $times = $el->att('bytes');
        return ('x' x $times => undef);
    }

    if ($el->tag ne 'field') {
        say "Not a field (instead " . $el->tag . "), skipping";
        return ('', undef);
    }

    my $type = $el->att('type');
    my $name = lc $el->att('name');
    # TODO: look up types
    my @xids = qw(WINDOW DRAWABLE ATOM PIXMAP CURSOR FONT GCONTEXT COLORMAP FONTABLE);
    if ($type ~~ @xids || $type eq 'CARD32') {
        return (L => $name);
    }
    if ($type eq 'INT16') {
        return (s => $name);
    }
    if ($type eq 'BOOL' || $type eq 'CARD8') {
        return (c => $name);
    }
    if ($type eq 'CARD16') {
        return (S => $name);
    }

    say "unhandled $type";
    exit 1;
}

sub handle_list {
    my ($el) = @_;

    say "should calc list";

    my @children = $el->children;
    if (@children == 1 && $children[0]->tag eq 'fieldref') {
        my $ref = $children[0]->text;

        say "ref = $ref";
        return "\$$ref";
    }

    exit 1;
}

sub get_field_name {
    my ($el) = @_;

    if ($el->tag eq 'field' || $el->tag eq 'list') {
        return $el->att('name');
    } elsif ($el->tag eq 'pad' || $el->tag eq 'reply') {
        return undef;
    } else {
        say "unhandled el with tag " . $el->tag . " for name";
        exit 1;
    }
}

my @c = $xml->root->children('request');
for my $req (@c) {
    my $opcode = $req->att('opcode');
    my @handle = qw(3 4 5 8 9 10 11 16 14 20 40 15 43 55 98 99 17 54 38 53 60 95);
    next unless $opcode ~~ @handle;

    my $reqname = $req->att('name');
    say "Handling opcode $opcode ($reqname)";

    say $fh '';
    say $fh "  # $reqname";
    say $fh "  if (\$opcode == $opcode) {";

    #my @all_names = grep { defined($_) } map { get_field_name($_) } $req->children;
    #say $fh "  my (" . join(', ', map { "\$$_" } @all_names) . ");";

    my @names;
    # skip the first byte (opcode)
    my $unpackfmt = 'x';

    my @children = $req->children;
    my $first = shift @children;

    # first field might be padding (→ ignore)
    my ($fmt, $name) = handle_field($first);
    push @names, $name if defined($name);
    $unpackfmt .= $fmt;

    # skip the length-field
    $unpackfmt .= 'x[S]';

    my $cnt = 4;

    my $unpacked = 0;

    # iterate through the remaining children
    for my $child (@children) {
        if ($child->tag eq 'list') {

            if (@names > 0) {
            say $fh "  my (" . join(', ', map { "\$$_" } @names) . ") = unpack('$unpackfmt', \$request);";
            }
            $unpacked = 1;
            say "Handling list at pos $cnt";
            my $len = handle_list($child);
            my $listname = $child->att('name');
            say "list len is $len";
            say $fh "    my \$$listname = substr(\$request, $cnt, $len);";
            push @names, $listname;
            #$cnt += $len;
        } else {
            my ($fmt, $name) = handle_field($child);
            $unpackfmt .= $fmt;
            $cnt += packfmt_to_bytes($fmt);
            push @names, $name if defined($name);
        }
    }

    $unpackfmt =~ s/[x]+$//g;
    say 'done, fmt = ' . $unpackfmt . ", after handled part = $cnt";

    # generate the code
    if (!$unpacked && @names > 0) {
    say $fh "  my (" . join(', ', map { "\$$_" } @names) . ") = unpack('$unpackfmt', \$request);";
    }
    say $fh  q|  my $data = {|;
    say $fh qq|    opcode => $opcode,|;
    say $fh qq|    name => "$reqname",|;
    say $fh qq|    moredetails => {|;
    for my $n (@names) {
    say $fh qq|      $n => \$$n,|;
    }
    say $fh qq|    }|;
    say $fh qq|  };|;
    say $fh  q|  return $data;|;
    say $fh "  }";
    say $fh '';
}

say $fh '}';
say $fh '';
say $fh '__PACKAGE__->meta->make_immutable;';
say $fh '';
say $fh '1';
