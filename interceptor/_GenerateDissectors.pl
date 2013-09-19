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
use File::Basename;
use v5.10;

say "reading in XML";

$Data::Dumper::Maxdepth = 2;

# TODO: handle all extensions
my $xproto_xml = XML::Twig->new();
$xproto_xml->parsefile('/usr/share/xcb/xproto.xml');

my $randr_xml = XML::Twig->new();
$randr_xml->parsefile('/usr/share/xcb/randr.xml');

# we replace the <import> nodes with the type elements
for my $xml ($xproto_xml, $randr_xml) {
    for my $import ($xml->root->get_xpath('import')) {
        my $twig = XML::Twig->new;
        $twig->parsefile('/usr/share/xcb/' . $import->text . '.xml');
        my @d = $twig->root->descendants(qr/(enum|struct)/);
        map { $_->cut } @d;
        $import->replace_with(@d);
    }
}

sub field_size {
    my ($type) = @_;

    my @xids = qw(WINDOW DRAWABLE ATOM PIXMAP CURSOR FONT GCONTEXT COLORMAP FONTABLE KEYSYM MODE CRTC OUTPUT);
    if ($type ~~ @xids || $type eq 'CARD32' || $type eq 'VISUALID' || $type eq 'TIMESTAMP') {
        return (L => 4);
    }
    if ($type eq 'INT32' || $type eq 'FIXED') {
        return (l => 4);
    }
    if ($type eq 'INT16') {
        return (s => 2);
    }
    if ($type eq 'INT8') {
        return (c => 1);
    }
    if ($type eq 'BOOL' || $type eq 'CARD8' || $type eq 'char' || $type eq 'void' || $type eq 'BYTE' || $type eq 'KEYCODE' || $type eq 'BUTTON') {
        return (C => 1);
    }
    if ($type eq 'CARD16') {
        return (S => 2);
    }

    return (undef, undef);
}

#
# spits out code to $fh which handles the element $el.
# returns the amount of bytes which were handled
#
sub dissect_element {
    my ($fh, $xml, $reqname, $prefix, $cnt, $el) = @_;

    return $el->att('bytes') if $el->tag eq 'pad';

    # XXX: do we need to handle that?
    return 0 if $el->tag eq 'reply';

    if ($el->tag eq 'field') {
        my $type = $el->att('type');
        my $name = lc $el->att('name');

        # check if it is a builtin type
        my ($fmt, $bytes) = field_size($type);
        if (defined($fmt)) {
            say $fh "    $prefix$name} = unpack('$fmt', substr(\$pkt, $cnt, $bytes));";
            if (defined($el->att('enum'))) {
                say $fh "      $prefix$name} = DissectorHelper::enum_" . $el->att('enum') . "_value_to_strings($prefix$name});";
            }
            if (defined($el->att('altenum'))) {
                say $fh "      {";
                say $fh "        my \$_val = DissectorHelper::enum_" . $el->att('altenum') . "_value_to_strings($prefix$name});";
                say $fh "        $prefix$name} = \$_val if defined(\$_val);";
                say $fh "      }";
            }
            return $bytes;
        }

        # check if it is a struct
        say "checking if $type is a struct";
        my ($struct) = $xml->root->get_xpath('struct[@name = "' . $type . '"]');
        if (defined($struct)) {
            my $bytes = $cnt;
            for my $child ($struct->children) {
                $bytes += dissect_element($fh, $xml, $reqname, $prefix . $name . '}->{', $bytes, $child);
            }
            say $fh '';
            return ($bytes - $cnt);
        }

        # check if it is a union
        my ($union) = $xml->root->get_xpath('union[@name = "' . $type . '"]');
        if (defined($union)) {
            # TODO: union
            return 0;
        }
        say "uhm, no?";
    }

    if ($el->tag eq 'exprfield') {
        my $type = $el->att('type');
        my $name = lc $el->att('name');

        # check if it is a builtin type
        my ($fmt) = field_size($type);
        if (defined($fmt)) {
            say $fh "    $prefix$name} = " . expr($el->first_child, $prefix) . ";";
            return 0;
        }

        die;
    }

    # XXX: list is always at the end (should we ensure this in the code?)
    if ($el->tag eq 'list') {
        my $type = $el->att('type');
        my $len = expr($el->first_child(), $prefix);
        my $listname = $el->att('name');
        my $fixlen = 0;
        if (!defined($len)) {
            $fixlen = 1;
            say "no length given, just using rest of the package";
            $len = "(\$length - $cnt)";
        }
        say "list len is $len";
        my ($fmt, $bytes) = field_size($type);

        if (defined($fmt) && $bytes == 1) {
            say $fh "    $prefix$listname} = substr(\$pkt, $cnt, $len);";
            return "$len";
        }

        # check for builtin types with > 1 byte
        if (defined($fmt) && $bytes > 1) {
            say $fh "    {";
            # XXX: a reference to $length is not specified in bytes, but in entities of list-type?
            if ($len eq '$length') {
            say $fh "    my \$_listlen = \$length / $bytes;";
            } else {
                if (substr("$len", 0, 1) eq '#') {
            say $fh "    my \$_listlen = 0;";
                } else {
            say $fh "    my \$_listlen = $len;";
                }
            }
            say $fh "    my \$$listname = substr(\$pkt, $cnt, \$_listlen * $bytes);";
            say $fh "    my \@c;";
            say $fh "    for (my \$c = 0; \$c < \$_listlen; \$c++) {";
            say $fh "    my \$_part = unpack('$fmt', substr(\$$listname, \$c * $bytes));";
            say $fh "      push \@c, \$_part;";
            say $fh "    }";
            say $fh "    $prefix$listname} = [ \@c ];";
            say $fh "    }";

            return 0;
        }

        return 0 if $type eq 'CHAR2B';

        my ($struct) = $xml->root->get_xpath('struct[@name = "' . $type . '"]');
        if (defined($struct)) {

            my $bytes = 0;
            for my $child ($struct->children) {
                my $size = dissect_element($fh, $xml, $reqname, '#', $bytes, $child);
                if ($size =~ /^[0-9]+$/) {
                    $bytes += $size;
                }
            }
            if ($fixlen) {
                $len .= ' / ' . $bytes;
            }

            say $fh "    {";
            say $fh "    my \$_listlen = $len;";
            say $fh "    my \@c;";
            say $fh "    my \$_cnt = $cnt;";
            say $fh "    for (my \$c = 0; \$c < \$_listlen; \$c++) {";
            say $fh "      my \$_part = {};";
            for my $child ($struct->children) {
                my $size = dissect_element($fh, $xml, $reqname, '$_part->{', "\$_cnt", $child);
                say $fh " \$_cnt += $size;";
            }
            say $fh "      push \@c, \$_part;";
            say $fh "    }";
            say $fh "    $prefix$listname} = [ \@c ];";
            say $fh "    }";
            return 0;
        }
        die "unknown type $type";
    }

    if ($el->tag eq 'valueparam') {
        # TODO: we should save what's in crurent scope
        my $maskname = $el->att('value-mask-name');
        # unpack the value-mask
        my ($fmt, $len) = field_size($el->att('value-mask-type'));
        say $fh "    my (\$$maskname) = unpack('$fmt', substr(\$pkt, $cnt, $len));";
        say $fh "    $prefix$maskname} = \$$maskname;";
        $cnt += $len;
        say $fh "    my \$_cnt = $cnt;";
        say $fh "    my \%_merge;";
        my %mapping = (
            ChangeWindowAttributes => 'CW',
            CreateWindow => 'CW',
            ConfigureWindow => 'ConfigWindow',
            ChangeGC => 'GC',
        );
        if (exists $mapping{$reqname}) {
            my @items = $xml->root->get_xpath('enum[@name="' . $mapping{$reqname} . '"]/item');
            for my $item (@items) {
                my ($bit) = $item->children('bit');
                say $fh "    if ((\$$maskname & (1 << " . $bit->text . "))) {";
                say $fh "      my \$ex = unpack('$fmt', substr(\$pkt, \$_cnt, 4));";
                # handle the data itself: either just an int, or an enum, or…
                if (($xml->root->get_xpath('enum[@name="' . $item->att('name') . '"]')) > 0) {
                    say $fh "      my \$_data = DissectorHelper::enum_" . $item->att('name') . "_value_to_strings(\$ex);";
                    say $fh "      \$_data = \$ex unless defined(\$_data);";
                    say $fh "      $prefix" . lc $item->att('name') . "} = \$_data;";
                } else {
                    say $fh "      $prefix" . lc $item->att('name') . "} = \$ex;";
                }

                say $fh "      \$_cnt += $len;";
                say $fh "    }";
            }
        }
        return $cnt;
    }
    warn "Unhandled element " . $el->tag . " in req $reqname with name " . $el->att('name');
}

sub expr {
    my ($el, $prefix) = @_;

    return unless defined($el);

    if ($el->tag eq 'fieldref') {
        # the 'length' field is special: we have it in current scope instead of
        # in the moredetails hash
        return '$length' if $el->text eq 'length';

        return $prefix . $el->text . '}';
    }
    if ($el->tag eq 'op') {
        my @children = $el->children;
        return '(' . expr($children[0], $prefix) . ' ' . $el->att('op') . ' ' . expr($children[1], $prefix) . ')';
    }
    if ($el->tag eq 'value') {
        return $el->text;
    }
say "--> unhandled tag " . $el->tag . " in expr";
exit 0;
}

# XXX: well, this is not using 'expressions' correctly, only caring for value and bit tags
sub generate_helper {
    my ($xmls) = @_;
    open my $fh, '>', 'gen/DissectorHelper.pm';
    say $fh 'package DissectorHelper;';
    say $fh 'use Moose;';
    say $fh '';

    for my $xml (@$xmls) {
        for my $enum ($xml->root->children('enum')) {
            my $name = $enum->att('name');
            say $fh "sub enum_${name}_value_to_strings {";
            say $fh '  my ($value) = @_;';
            say $fh '  my @retvals;';
            my $is_bitmask = 0;
            for my $item ($enum->children('item')) {
                my $iname = $item->att('name');
                for my $child ($item->children) {
                    next if ($child->tag eq '#PCDATA');
                    if ($child->tag eq 'value') {
                        say $fh '  if ($value == ' . $child->text . ') {';
                        say $fh "    return '$iname';";
                        say $fh '  }';
                    } elsif ($child->tag eq 'bit') {
                        say $fh '  if (($value & (1 << ' . $child->text . '))) {';
                        say $fh "    push \@retvals, '$iname';";
                        say $fh '  }';
                        $is_bitmask = 1;
                    } else {
                        say "unhandled enum child: " . $child->tag . " in enum $name";
                        die 1;
                    }
                }
            }
            if ($is_bitmask) {
                say $fh '  return \@retvals;';
            } else {
                say $fh '  return undef;';
            }
            say $fh "}";
        }
    }
    say $fh '1;';
    close $fh;
}

sub generate_requests {
    # write header
    open my $fh, '>', 'gen/RequestDissector.pm';
    say $fh <<'eot';
package RequestDissector;
use Moose;
use DissectorHelper;

sub dissect_request {
  my ($pkt) = @_;
  my ($opcode, $length) = unpack("cxS", $pkt);
  $length *= 4;
  my $data = {
      opcode => $opcode,
  };
  my $m = {};
eot

    for my $req ($xproto_xml->root->children('request')) {
        my $opcode = $req->att('opcode');
        my $reqname = $req->att('name');
        say "Handling opcode $opcode ($reqname)";

        say $fh <<"eot";
  # $reqname
  if (\$opcode == $opcode) {
      \$data->{name} = "$reqname";
eot

        my @children = $req->children;
        my $first = shift @children;

        # dissect the first field, if there is one at all
        dissect_element($fh, $xproto_xml, $reqname, '$m->{', 1, $first) if defined($first);

        # skip the length-field
        my $cnt = 4;

        # iterate through the remaining children
        for my $child (@children) {
            my $size = dissect_element($fh, $xproto_xml, $reqname, '$m->{', $cnt, $child);
            if ($size =~ /^[0-9]+$/) {
                $cnt += $size;
            }
        }

        say $fh  <<'eot';
    $data->{moredetails} = $m;
    return $data;
  }
eot
    }

    say $fh <<eot;
  undef
}

__PACKAGE__->meta->make_immutable;

1;
eot
}

sub generate_randr_requests {
    # write header
    open my $fh, '>', 'gen/RequestDissector/RANDR.pm';
    say $fh <<'eot';
package RequestDissector::RANDR;
use Moose;
use DissectorHelper;

sub dissect_request {
  my ($pkt) = @_;
  my ($opcode, $subreq, $length) = unpack("CCS", $pkt);
  $length *= 4;
  my $data = {
      opcode => $opcode,
      subreq => $subreq,
  };
  my $m = {};
eot

    for my $req ($randr_xml->root->children('request')) {
        my $opcode = $req->att('opcode');
        my $reqname = $req->att('name');
        say "Handling opcode $opcode ($reqname)";

        say $fh <<"eot";
  # $reqname
  if (\$subreq == $opcode) {
      \$data->{name} = "RANDR:$reqname";
eot

        my @children = $req->children;
        # skip the length-field
        my $cnt = 4;

        # iterate through the remaining children
        for my $child (@children) {
            my $size = dissect_element($fh, $randr_xml, $reqname, '$m->{', $cnt, $child);
            if ($size =~ /^[0-9]+$/) {
                $cnt += $size;
            }
        }

        say $fh  <<'eot';
    $data->{moredetails} = $m;
    return $data;
  }
eot
    }

    say $fh <<eot;
  undef
}

__PACKAGE__->meta->make_immutable;

1;
eot
}

sub generate_replies {
    my ($xml) = @_;
    open my $fh, '>', 'gen/ReplyDissector.pm';
    say $fh <<'eot';
package ReplyDissector;
use Moose;
use v5.10;

sub dissect_reply {
  my ($pkt, $ph) = @_;
  my ($type, $format, $sequence, $length) = unpack("ccSL", $pkt);
  $length *= 4;
  my $m = {};
  my $data = {
      seq => $sequence
  };
  my $_data = $ph->type_of_reply($sequence);
  my $name = $_data->{name};
  $data->{name} = $name;
eot

    for my $rep ($xml->root->get_xpath('request//reply')) {
        #say Dumper($req);
        my $opcode = $rep->parent->att('opcode');

        my $reqname = $rep->parent->att('name');
        say "Handling opcode $opcode ($reqname)";

        say $fh <<"eot";
# $reqname
if (\$name eq \"$reqname\") {
eot

        my @children = $rep->children;
        my $first = shift @children;

        # first field goes into the gap
        dissect_element($fh, $xml, $reqname, '$m->{', 1, $first) if defined($first);

        my $cnt = 8;

        # iterate through the children
        for my $child (@children) {
            my $size = dissect_element($fh, $xml, $reqname, '$m->{', $cnt, $child);
            if ($size =~ /^[0-9]+$/) {
                $cnt += $size;
            }
        }

        say $fh  <<'eot';
    $data->{moredetails} = $m;
    return $data;
  }
eot
    }

    say $fh <<'eot';
  undef
}

__PACKAGE__->meta->make_immutable;

1
eot
}

sub generate_randr_replies {
    my ($xml) = @_;
    open my $fh, '>', 'gen/ReplyDissector/RANDR.pm';
    say $fh <<'eot';
package ReplyDissector::RANDR;
use Moose;
use DissectorHelper;
use v5.10;

sub dissect_reply {
  my ($pkt, $ph) = @_;
  my ($type, $format, $sequence, $length) = unpack("ccSL", $pkt);
  $length *= 4;
  my $m = {};
  my $data = {
      seq => $sequence
  };
  # TODO: the wrapping of seq ids needs to be handled
  if (!$ph->awaiting_reply($sequence)) {
      say "didnt expect that coming";
      return;
  }
  my $_data = $ph->type_of_reply($sequence);
  my $name = $_data->{name};
  $data->{name} = $name;
eot

    for my $rep ($xml->root->get_xpath('request//reply')) {
        #say Dumper($req);
        my $opcode = $rep->parent->att('opcode');

        my $reqname = $rep->parent->att('name');
        say "Handling opcode $opcode ($reqname)";

        say $fh <<"eot";
# $reqname
if (\$name eq \"RANDR:$reqname\") {
eot

        my @children = $rep->children;
        my $first = shift @children;

        # first field goes into the gap
        dissect_element($fh, $xml, $reqname, '$m->{', 1, $first) if defined($first);

        my $cnt = 8;

        # iterate through the children
        for my $child (@children) {
            my $size = dissect_element($fh, $xml, $reqname, '$m->{', $cnt, $child);
            if ($size =~ /^[0-9]+$/) {
                $cnt += $size;
            }
        }

        say $fh  <<'eot';
    $data->{moredetails} = $m;
    return $data;
  }
eot
    }

    say $fh <<'eot';
  undef
}

__PACKAGE__->meta->make_immutable;

1
eot
}


sub generate_events {
    my ($xml) = @_;
    open my $fh, '>', 'gen/EventDissector.pm';
    say $fh <<'eot';
package EventDissector;
use Moose;
use v5.10;

sub dissect_event {
  my ($pkt, $ph) = @_;
  my ($type, $format, $sequence) = unpack("ccS", $pkt);
  my $m = {};

  $type &= 0x7F;
eot

    for my $rep ($xml->root->children('event')) {
        my $number = $rep->att('number');
        my $reqname = $rep->att('name');
        say "Handling event number $number ($reqname)";

        say $fh <<"eot";
  # $reqname
  if (\$type == $number) {
    my \$data = {
      seq => \$sequence,
      name => "$reqname",
      moredetails => {}
    };
eot

        my @children = $rep->children;
        my $first = shift @children;

        # first field goes into the gap
        dissect_element($fh, $xml, $reqname, '$m->{', 1, $first) if defined($first);

        my $cnt = 4;

        # iterate through the children
        for my $child (@children) {
            $cnt += dissect_element($fh, $xml, $reqname, '$m->{', $cnt, $child);
        }

        say $fh  <<'eot';
    $data->{moredetails} = $m;
    return $data;
  }
eot
    }

    say $fh <<'eot';
  undef
}

__PACKAGE__->meta->make_immutable;

1
eot
}

sub generate_errors {
    my ($xml) = @_;
    open my $fh, '>', 'gen/ErrorDissector.pm';
    say $fh <<'eot';
package ErrorDissector;
use Moose;
use v5.10;

sub dissect_error {
  my ($pkt, $ph) = @_;
  my ($type, $error_code, $sequence) = unpack("ccS", $pkt);
  my $m = {};
eot

    for my $rep ($xml->root->children('error')) {
        my $number = $rep->att('number');
        my $reqname = $rep->att('name');
        say "Handling error number $number ($reqname)";

        say $fh <<"eot";
  # $reqname
  if (\$error_code == $number) {
    my \$data = {
      seq => \$sequence,
      name => "$reqname",
      moredetails => {}
    };
eot

        my $cnt = 4;
        # iterate through the children
        for my $child ($rep->children) {
            $cnt += dissect_element($fh, $xml, $reqname, '$m->{', $cnt, $child);
        }

        say $fh  <<'eot';
    $data->{moredetails} = $m;
    return $data;
  }
eot
    }
    for my $rep ($xml->root->children('errorcopy')) {
        my $number = $rep->att('number');
        my $reqname = $rep->att('name');
        say "Handling error number $number ($reqname)";
        my $ref = $rep->att('ref');
        ($rep) = $xml->root->get_xpath('error[@name="' . $ref . '"]');

        say $fh <<"eot";
  # $reqname
  if (\$error_code == $number) {
    my \$data = {
      seq => \$sequence,
      name => "$reqname",
      moredetails => {}
    };
eot

        my $cnt = 4;
        # iterate through the children
        for my $child ($rep->children) {
            $cnt += dissect_element($fh, $xml, $reqname, '$m->{', $cnt, $child);
        }

        say $fh  <<'eot';
    $data->{moredetails} = $m;
    return $data;
  }
eot
    }


    say $fh <<'eot';
  undef
}

__PACKAGE__->meta->make_immutable;

1
eot
}

say "--- GENERATING HELPER ---";
generate_helper([$randr_xml]);

say "--- GENERATING REQUESTS ---";
generate_requests();
say "";
say "--- GENERATING RandR REQUESTS ---";
generate_randr_requests();
say "";
say "--- GENERATING REPLIES";
say "";
generate_replies($xproto_xml);
say "--- GENERATING RandR REQUESTS ---";
generate_randr_replies($randr_xml);
say "";
say "";
say "--- GENERATING EVENTS";
say "";
generate_events($xproto_xml);
say '';
say '--- GENERATING ERRORS';
say '';
generate_errors($xproto_xml);
