# x11vis

See https://www.x11vis.org for an introduction.

## Installation

(Tested on Ubuntu 24.04.)

First, install the build dependencies (`xcb-proto`) and the cpanminus Perl
package manager:

```
sudo apt install build-essential cpanminus xcb-proto
```

Then, install the Perl dependencies (can take a few minutes):

```
sudo cpanm AnyEvent AnyEvent::Socket Twiggy Dancer IO::All JSON::XS Moose MooseX::Singleton XML::Twig
```

Afterwards, you should be able to run `sudo make install`.

## Usage

See the manual: https://x11vis.org/docs/manual.html

## Development

### New icing

The 'icing' is the one-line summary of the message.

If you'd like to add/improve the summaries for various kinds of messages, look
in the `reply_icing`, `request_icing` and `event_icing` functions of 
`PacketHandler.pm` to improve the presentation of replies, requests or events.

