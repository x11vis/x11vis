#!/usr/bin/env perl
# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#

use strict;
use warnings;
use Data::Dumper;
use JSON::XS;
use v5.10;

# This hash was generated with:
# perl -n -e '/define XA_([^ ]*).*?([0-9]+)/ and print "$2 => \"$1\",\n"' </usr/include/X11/Xatom.h
my %atoms = (
    1 => "PRIMARY",
    2 => "SECONDARY",
    3 => "ARC",
    4 => "ATOM",
    5 => "BITMAP",
    6 => "CARDINAL",
    7 => "COLORMAP",
    8 => "CURSOR",
    9 => "CUT_BUFFER0",
    10 => "CUT_BUFFER1",
    11 => "CUT_BUFFER2",
    12 => "CUT_BUFFER3",
    13 => "CUT_BUFFER4",
    14 => "CUT_BUFFER5",
    15 => "CUT_BUFFER6",
    16 => "CUT_BUFFER7",
    17 => "DRAWABLE",
    18 => "FONT",
    19 => "INTEGER",
    20 => "PIXMAP",
    21 => "POINT",
    22 => "RECTANGLE",
    23 => "RESOURCE_MANAGER",
    24 => "RGB_COLOR_MAP",
    25 => "RGB_BEST_MAP",
    26 => "RGB_BLUE_MAP",
    27 => "RGB_DEFAULT_MAP",
    28 => "RGB_GRAY_MAP",
    29 => "RGB_GREEN_MAP",
    30 => "RGB_RED_MAP",
    31 => "STRING",
    32 => "VISUALID",
    33 => "WINDOW",
    34 => "WM_COMMAND",
    35 => "WM_HINTS",
    36 => "WM_CLIENT_MACHINE",
    37 => "WM_ICON_NAME",
    38 => "WM_ICON_SIZE",
    39 => "WM_NAME",
    40 => "WM_NORMAL_HINTS",
    41 => "WM_SIZE_HINTS",
    42 => "WM_ZOOM_HINTS",
    43 => "MIN_SPACE",
    44 => "NORM_SPACE",
    45 => "MAX_SPACE",
    46 => "END_SPACE",
    47 => "SUPERSCRIPT_X",
    48 => "SUPERSCRIPT_Y",
    49 => "SUBSCRIPT_X",
    50 => "SUBSCRIPT_Y",
    51 => "UNDERLINE_POSITION",
    52 => "UNDERLINE_THICKNESS",
    53 => "STRIKEOUT_ASCENT",
    54 => "STRIKEOUT_DESCENT",
    55 => "ITALIC_ANGLE",
    56 => "X_HEIGHT",
    57 => "QUAD_WIDTH",
    58 => "WEIGHT",
    59 => "POINT_SIZE",
    60 => "RESOLUTION",
    61 => "COPYRIGHT",
    62 => "NOTICE",
    63 => "FONT_NAME",
    64 => "FAMILY_NAME",
    65 => "FULL_NAME",
    66 => "CAP_HEIGHT",
    67 => "WM_CLASS",
    68 => "WM_TRANSIENT_FOR",
);

say "Generating gen/PredefinedAtoms.pm";

open my $fh, '>', 'gen/PredefinedAtoms.pm';
say $fh <<'eot';
package PredefinedAtoms;
use Moose;
use Mappings;

sub add_predefined_atoms {
    my $mappings = Mappings->instance;
eot

for my $key (sort { $a <=> $b } keys %atoms) {
    say $fh "    \$mappings->add_atom('" . $atoms{$key} . "' => $key);";
    say $fh "    \$mappings->id_for($key => 'atom');";
}

say $fh <<'eot';
}

__PACKAGE__->meta->make_immutable;

1
eot
close($fh);

say "Generating gen/predefined_atoms.json";
open $fh, '>', 'gen/predefined_atoms.json';

my @lines = map {
    encode_json({
        type => 'cleverness',
        id => 'a_' . ($_ - 1),
        idtype => 'atom',
        title => $atoms{$_}
    }) } keys %atoms;
say $fh join(', ', @lines);

close($fh);
