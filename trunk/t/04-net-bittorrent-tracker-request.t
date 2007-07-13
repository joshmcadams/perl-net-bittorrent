use warnings;
use strict;
use Test::More qw(no_plan);

use_ok('Net::BitTorrent::Tracker::Request');

my $request = Net::BitTorrent::Tracker::Request::create_request(
    tracker => 'http://my.tracker.com/track',
    info_hash => 'A'x20,
    peer_id => 'B'x20,
    ip => '192.168.0.1',
    port => 6881,
    uploaded => 0,
    downloaded => 0,
    left => 10,
    event => 'started',
);

is($request, 'http://my.tracker.com/track?' .
             'info_hash=AAAAAAAAAAAAAAAAAAAA&' .
             'peer_id=BBBBBBBBBBBBBBBBBBBB&' .
             'ip=192.168.0.1&port=6881&' .
             'uploaded=0&downloaded=0&' .
             'left=10&event=started' );
