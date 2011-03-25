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

sub field_size {
    my ($type, $name) = @_;

    my @xids = qw(WINDOW DRAWABLE ATOM PIXMAP CURSOR FONT GCONTEXT COLORMAP FONTABLE);
    if ($type ~~ @xids || $type eq 'CARD32' || $type eq 'VISUALID') {
        return (L => $name);
    }
    if ($type eq 'INT16') {
        return (s => $name);
    }
    if ($type eq 'BOOL' || $type eq 'CARD8' || $type eq 'char' || $type eq 'void') {
        return (c => $name);
    }
    if ($type eq 'CARD16') {
        return (S => $name);
    }

    return (undef, undef);
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
    my ($fmt, $_name) = field_size($type, $name);
    if (!defined($fmt)) {
        say "handle_field unhandled field_size";
        exit 1;
    }
    return ($fmt => $name);
}

sub handle_list {
    my ($el) = @_;

    if ($el->tag eq 'fieldref') {
        return '$' . $el->text;
    }
    if ($el->tag eq 'op') {
        my @children = $el->children;
        return '(' . handle_list($children[0]) . ' ' . $el->att('op') . ' ' . handle_list($children[1]) . ')';
    }
    if ($el->tag eq 'value') {
        return $el->text;
    }
say "--> unhandled tag " . $el->tag . " in handle_list";
exit 0;
}

sub dissect_struct {
    my ($fh, $type) = @_;

    # see if there is a struct entry in the XML
    my ($elm) = $xml->root->get_xpath('struct[@name = "' . $type . '"]');
    if (!defined($elm)) {
        say "unhandled type as struct $type";
        exit 1;
    }
    my $unpackfmt;
    my $cnt = 0;
    say "got a struct, using";
    my @names;
    for my $child ($elm->children) {
        if ($child->tag eq 'list') {
            say "Handling list at pos $cnt";
            my $len = handle_list($child->first_child());
            my $listname = $child->att('name');
            say "list len is $len";
            say $fh "    my \$$listname = substr(\$request, \$_cnt, $len);";
            push @names, "$listname";
        } else {
            my ($fmt, $name) = handle_field($child);
            say "fmt = $fmt, name = $name";
            $unpackfmt .= $fmt;
            $cnt += packfmt_to_bytes($fmt);
            say $fh "    my (\$$name) = unpack('$fmt', substr(\$request, \$_cnt));";
            say $fh "    \$_cnt++;";
            push @names, "$name";
        }
    }
    say $fh "    push \@c, { ";
    for (@names) {
        say $fh " $_ => \$$_,";
    }
    say $fh "    };";

    say "end of struct";
                    #dissect_single_field($fh, $child->att('type'));
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

sub generate_requests {
    open my $fh, '>', 'gen/RequestDissector.pm';
    say $fh 'package RequestDissector;';
    say $fh 'use Moose;';
    say $fh '';
    say $fh 'sub dissect_request {';
    say $fh '  my ($request) = @_;';
    say $fh '  my ($opcode) = unpack("c", $request);';

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
                say $fh "    my (" . join(', ', map { "\$$_" } @names) . ") = unpack('$unpackfmt', \$request);";
                }
                $unpacked = 1;
                say "Handling list at pos $cnt";
                my $len = handle_list($child->first_child());
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
        say $fh "    my (" . join(', ', map { "\$$_" } @names) . ") = unpack('$unpackfmt', \$request);";
        }
        say $fh  q|    my $data = {|;
        say $fh qq|      opcode => $opcode,|;
        say $fh qq|      name => "$reqname",|;
        say $fh qq|      moredetails => {|;
        for my $n (@names) {
        say $fh qq|        $n => \$$n,|;
        }
        say $fh qq|      }|;
        say $fh qq|    };|;
        say $fh  q|    return $data;|;
        say $fh "    }";
        say $fh '';
    }

    say $fh '}';
    say $fh '';
    say $fh '__PACKAGE__->meta->make_immutable;';
    say $fh '';
    say $fh '1';
}

sub generate_replies {
    open my $fh, '>', 'gen/ReplyDissector.pm';
    say $fh 'package ReplyDissector;';
    say $fh 'use Moose;';
    say $fh 'use v5.10;';
    say $fh '';
    say $fh 'sub dissect_reply {';
    say $fh '  my ($request, $ph) = @_;';
    say $fh '  my ($type, $format, $sequence, $length) = unpack("ccSL", $request);';
    say $fh '  # TODO: the wrapping of seq ids needs to be handled';
    say $fh '  if (!$ph->awaiting_reply($sequence)) {';
    say $fh '      say "didnt expect that coming";';
    say $fh '      return;';
    say $fh '  }';
    say $fh '  my $data = $ph->type_of_reply($sequence);';
    say $fh '  my $name = $data->{name};';


    my @c = $xml->root->get_xpath('request//reply');
    for my $rep (@c) {
        #say Dumper($req);
        my $opcode = $rep->parent->att('opcode');
        my @handle = qw(3 4 5 8 9 10 11 16 14 20 40 15 43 55 98 99 17 54 38 53 60 95);
        next unless $opcode ~~ @handle;

        my $reqname = $rep->parent->att('name');
        say "Handling opcode $opcode ($reqname)";

        say $fh '';
        say $fh "  # $reqname";
        say $fh "  if (\$name eq \"$reqname\") {";

        my @names;
        # skip the first byte (reply_type)
        my $unpackfmt = 'x';

        my @children = $rep->children;
        my $first = shift @children;

        # first field goes into the gap
        my ($fmt, $name) = handle_field($first);
        push @names, $name if defined($name);
        $unpackfmt .= $fmt;

        # skip the length-field
        $unpackfmt .= 'x[SL]';

        my $cnt = 8;

        my $unpacked = 0;

        # iterate through the children
        for my $child (@children) {
            if ($child->tag eq 'list') {
                if (@names > 0) {
                say $fh "    my (" . join(', ', map { "\$$_" } @names) . ") = unpack('$unpackfmt', \$request);";
                }
                $unpacked = 1;
                say "Handling list at pos $cnt";
                my $len = handle_list($child->first_child());
                my $listname = $child->att('name');
                say "list name = $listname, len is $len, type is " . $child->att('type');
                my ($listfmt, $__) = field_size($child->att('type'), $listname);
                my $bytes = (defined($listfmt) ? packfmt_to_bytes($listfmt) : 0);
                #if (!defined($listfmt)) {
                #    say "Cannot determine field size for type " . $child->att('type');
                #    exit 1;
                #}
                #my $bytes = packfmt_to_bytes($listfmt);

                say "each type is $bytes";
                say $fh "    my \$_listlen = $len;";
                if ($bytes > 1) {
                    say $fh "    my \$$listname = substr(\$request, $cnt, \$_listlen * $bytes);";
                    say $fh "    my \@c;";
                    say $fh "    for (my \$c = 0; \$c < \$_listlen; \$c++) {";
                    my ($fmt, $name) = field_size($child->att('type'), $name);
                    say $fh "    my \$_part = unpack('$fmt', substr(\$children, \$c * $bytes));";
                    #say $fh "      my \$_part = substr(\$children, \$c * $bytes, $bytes);";
                    say $fh "      push \@c, \$_part;";
                    say $fh "    }";
                    say $fh "    \$children = [ \@c ];";
                } else {
                    if ($bytes == 0) {
                        # step for step dissecting of a struct
                        say $fh " my \@c;";
                        say $fh " my \$_cnt = $cnt;";
                        say $fh " for (my \$i = 0; \$i < \$_listlen; \$i++) {";
                        say "fh = $fh";
                        dissect_struct($fh, $child->att('type'));
                        say $fh " }";
                        say $fh " my \$$listname = [ \\\@c ];";
                    } else {
                        say $fh "    my \$$listname = substr(\$request, $cnt, \$_listlen);";
                    }
                }
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
        say $fh "    my (" . join(', ', map { "\$$_" } @names) . ") = unpack('$unpackfmt', \$request);";
        }
        say $fh  q|    my $data = {|;
        say $fh qq|      seq => \$sequence,|;
        say $fh qq|      name => "$reqname",|;
        say $fh qq|      moredetails => {|;
        for my $n (@names) {
        say $fh qq|        $n => \$$n,|;
        }
        say $fh qq|      }|;
        say $fh qq|    };|;
        say $fh  q|    return $data;|;
        say $fh "  }";
        say $fh '';
    }

    say $fh '}';
    say $fh '';
    say $fh '__PACKAGE__->meta->make_immutable;';
    say $fh '';
    say $fh '1';
}

generate_requests();
say "";
say "--- GENERATING REPLIES";
say "";
generate_replies();
