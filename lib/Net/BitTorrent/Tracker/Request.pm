package Net::BitTorrent::Tracker::Request;

use warnings;
use strict;

sub create_request {
    return 'http://my.tracker.com/track?' .
         'info_hash=AAAAAAAAAAAAAAAAAAAA&' .
         'peer_id=BBBBBBBBBBBBBBBBBBBB&' .
         'ip=192.168.0.1&port=6881&' .
         'uploaded=0&downloaded=0&' .
         'left=10&event=started';
}

1;

