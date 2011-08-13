# vim:ts=4:sw=4:expandtab
# x11vis - an X11 protocol visualizer
# © 2011 Michael Stapelberg and contributors (see ../LICENSE)
#
package Extension;
use Moose;

has 'name' => (is => 'rw', isa => 'Str', required => 1);
has 'opcode' => (is => 'rw', isa => 'Int', required => 1);
has 'first_error' => (is => 'rw', isa => 'Int', required => 1);
has 'first_event' => (is => 'rw', isa => 'Int', required => 1);

1
