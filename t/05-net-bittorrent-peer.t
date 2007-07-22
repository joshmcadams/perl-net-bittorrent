use warnings;
use strict;
use Test::More qw(no_plan);
use Test::MockObject;
use Net::BitTorrent::PeerPacket qw(:all);
use Bit::Vector::Minimal;

use_ok('Net::BitTorrent::Peer');

my @downloaded = ( 0, 1, 2 );
my $comm = Test::MockObject->new();
$comm->set_isa('Net::BitTorrent::PeerCommunicator');
$comm->set_always( 'get_ip', '127.0.0.1' );
$comm->mock( 'send_message', sub { push @{ shift->{messages} }, @_ } );
$comm->mock( 'set_callback', sub { $_[0]->{callback} = $_[1]; } );
$comm->mock( 'callback', sub { my $sub = shift->{callback}; $sub->(@_); } );

my $info_hash = 'A' x 20;
my $client_id = 'B' x 20;
my $peer_id   = 'C' x 20;

my $peer = Net::BitTorrent::Peer->new(
    info_hash    => $info_hash,
    client_id    => $client_id,
    peer_id      => $peer_id,
    downloaded   => \@downloaded,
    communicator => $comm,
);

isa_ok( $peer, 'Net::BitTorrent::Peer' );

# expect that a handshake, and only a handshake, was sent
is(
    shift @{ $comm->{messages} },
    bt_build_packet(
        bt_code   => BT_HANDSHAKE,
        info_hash => $info_hash,
        peer_id   => $client_id
    ),
    'got a handshake'
);

is( shift @{ $comm->{messages} }, undef, 'only a single message' );

# be a nice peer and respond with our own handshake
$comm->callback(
    bt_build_packet(
        bt_code   => BT_HANDSHAKE,
        info_hash => $info_hash,
        peer_id   => $peer_id
    )
);

# check initial settings
is_deeply( $peer->has(), [], 'peer has no pieces' );
is( $peer->choked(),     1, 'peer is initially choked' );
is( $peer->interested(), 0, 'we are initially not interested' );

# send a bitfield to let the peer know what we've got
my $bitfield = pack( "b*", '11100000' );
$comm->callback(
    bt_build_packet( bt_code => BT_BITFIELD, bitfield_ref => \$bitfield ) );

is_deeply( $peer->has(), [ 0, 1, 2 ], 'read bitfield correctly' );

############

#print split(//, unpack("b*", $bitfield)), "\n";

#is($bitfield, $vec, 'bits twiddled');

#$peer->show_interest();
#is( $peer->interested(), 1, 'we are interested now' );
#is($peer->choked(), 0, 'now we are not choked');

