use warnings;
use strict;

package TestPeer;

use base qw(Test::Class);
use Test::More;
use Test::MockObject;
use Net::BitTorrent::PeerPacket qw(:all);

my @downloaded = ( 0, 1, 2 );
my $info_hash  = 'A' x 20;
my $client_id  = 'B' x 20;      # local peer id
my $peer_id    = 'C' x 20;      # remote peer id

__PACKAGE__->runtests() unless caller;

sub setup_test : Test( setup => 1 ) {
    my ($self) = @_;

   # mock a communicator object so that we don't have to do any real socket comm
    my $comm = Test::MockObject->new();
    $comm->set_isa('Net::BitTorrent::PeerCommunicator');
    $comm->set_always( 'get_ip', '127.0.0.1' );
    $comm->mock( 'send_message', sub { push @{ shift->{messages} }, @_ } );
    $comm->mock( 'set_callback', sub { $_[0]->{callback} = $_[1]; } );
    $comm->mock( 'callback', sub { my $sub = shift->{callback}; $sub->(@_); } );

    $self->{comm} = $comm;

    # go ahead and create a default peer object too
    my $peer = Net::BitTorrent::Peer->new(
        info_hash    => $info_hash,
        client_id    => $client_id,
        peer_id      => $peer_id,
        downloaded   => \@downloaded,
        communicator => $self->{comm},
    );

    isa_ok( $peer, 'Net::BitTorrent::Peer' );

    $self->{peer} = $peer;

    return;
}

sub use_the_module : Test( startup => 1 ) {
    use_ok('Net::BitTorrent::Peer');
}

sub bad_peer_id_in_handshake : Test {
    my ($self) = @_;
    eval {
        $self->{comm}->callback(
            bt_build_packet(
                bt_code   => BT_HANDSHAKE,
                info_hash => $info_hash,
                peer_id   => $info_hash,     # send the wrong thing
            )
        );
    };
    ok( $@, 'invalid peer id rejected' );
}

sub bad_info_hash_in_handshake : Test {
    my ($self) = @_;

    eval {
        $self->{comm}->callback(
            bt_build_packet(
                bt_code   => BT_HANDSHAKE,
                info_hash => $peer_id,       # send the wrong thing
                peer_id   => $peer_id,
            )
        );
    };
    ok( $@, 'invalid info hash rejected' );
}

sub double_handshake : Tests {
    my ($self) = @_;

    eval {
        $self->{comm}->callback(
            bt_build_packet(
                bt_code   => BT_HANDSHAKE,
                info_hash => $info_hash,
                peer_id   => $peer_id,
            )
        );
    };
    ok( not($@), 'first handshake is okay' );

    eval {
        $self->{comm}->callback(
            bt_build_packet(
                bt_code   => BT_HANDSHAKE,
                info_hash => $info_hash,
                peer_id   => $peer_id,
            )
        );
    };
    ok( $@, 'second handshake is not okay' );

}

sub valid_handshake : Tests {
    my ($self) = @_;

    # expect that a handshake, and only a handshake, was sent
    is(
        shift @{ $self->{comm}->{messages} },
        bt_build_packet(
            bt_code   => BT_HANDSHAKE,
            info_hash => $info_hash,
            peer_id   => $client_id
        ),
        'got a handshake'
    );

    is( shift @{ $self->{comm}->{messages} }, undef, 'only a single message' );

    # be a nice peer and respond with our own handshake
    eval {
        $self->{comm}->callback(
            bt_build_packet(
                bt_code   => BT_HANDSHAKE,
                info_hash => $info_hash,
                peer_id   => $peer_id,
            )
        );
    };
    ok( not($@), 'return on handshake accepted' );

    # check initial settings
    is_deeply( $self->{peer}->has(), [], 'peer has no pieces' );
    is( $self->{peer}->choked(),     1, 'peer is initially choked' );
    is( $self->{peer}->interested(), 0, 'we are initially not interested' );

    # send a bitfield to let the peer know what we've got
    my $bitfield = pack( "b*", '11100000' );
    $self->{comm}->callback(
        bt_build_packet( bt_code => BT_BITFIELD, bitfield_ref => \$bitfield ) );

    is_deeply( $self->{peer}->has(), [ 0, 1, 2 ], 'read bitfield correctly' );

    #print split(//, unpack("b*", $bitfield)), "\n";
    #is($bitfield, $vec, 'bits twiddled');
    #$peer->show_interest();
    #is( $peer->interested(), 1, 'we are interested now' );
    #is($peer->choked(), 0, 'now we are not choked');

}
__END__


