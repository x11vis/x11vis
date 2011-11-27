package Dissector::ICCCM;

use strict;
use warnings;

# WM_SIZE_HINTS - ICCCM 4.1.2.3
my $sizeHintsUSPosition	 = 1 << 0;	# user specified x, y 
my $sizeHintsUSSize      = 1 << 1;	# user specified width, height 
my $sizeHintsPPosition   = 1 << 2;	# program specified position 
my $sizeHintsPSize       = 1 << 3;	# program specified size 
my $sizeHintsPMinSize    = 1 << 4;	# program specified minimum size 
my $sizeHintsPMaxSize    = 1 << 5;	# program specified maximum size 
my $sizeHintsPResizeInc  = 1 << 6;	# program specified resize increments 
my $sizeHintsPAspect     = 1 << 7;	# program specified min and max aspect ratios 
my $sizeHintsPBaseSize   = 1 << 8;
my $sizeHintsPWinGravity = 1 << 9;

sub dissect_wm_size_hints {

    # Strictly spoken $x, $y, $height and $width are deprecated, but they 
    # still seem the most reliable source of this information :/
    my ($flags, $x, $y, $width, $height, $min_width, $min_height, $max_width, 
        $max_height, $width_inc, $height_inc, $aspect_x, $aspect_y, $base_width, 
        $base_height, $win_gravity) = unpack("LLLLLLLLLLLLLLLL", shift);

    my %result;
    if ($flags & $sizeHintsUSPosition) {
        $result{USPosition} = "($x, $y)";
    }
    if ($flags & $sizeHintsUSSize) {
        $result{USSize} = "$width x $height";
    }
    if ($flags & $sizeHintsPPosition) {
        $result{PPosition} = "($x, $y)";
    }
    if ($flags & $sizeHintsPSize) {
        $result{PSize} = "$width x $height";
    }
    if ($flags & $sizeHintsPMinSize) {
        $result{PMinSize} = "$min_width x $min_height";
    }
    if ($flags & $sizeHintsPMaxSize) {
        $result{PMaxSize} = "$max_width x $max_height";
    }
    if ($flags & $sizeHintsPResizeInc) {
        $result{PResizeInc} = "$width_inc x $height_inc";
    }
    if ($flags & $sizeHintsPAspect) {
        $result{PAspect} = "$aspect_x : $aspect_y";
    }
    if ($flags & $sizeHintsPBaseSize) {
        $result{PBaseSize} = "$base_width x $base_height";
    }
    if ($flags & $sizeHintsPWinGravity) {
        $result{PWinGravity} = $win_gravity;
    }
    return %result;
}

sub decode_wm_size_hints($) {
    my %sizehints = dissect_wm_size_hints(shift);
    my @hints;
    for my $component (keys %sizehints) {
      push @hints, "$component: $sizehints{$component}";
    }
    return join ', ', @hints;
}
 
