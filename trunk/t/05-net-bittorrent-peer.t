use warnings;
use strict;

package TestPeer;

use base qw(Test::Class);
use Test::More;
use Test::MockObject;
use Net::BitTorrent::PeerPacket qw(:all);

my @downloaded = ( 1, 1, 1, 0, 0, 0, 0, 0 );
my $bitfield  = pack( "b*", join( '', @downloaded ) );
my $info_hash = 'A' x 20;
my $client_id = 'B' x 20;                                # local peer id
my $peer_id   = 'C' x 20;                                # remote peer id

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
    eval { $self->send_handshake_to_peer( peer_id => $info_hash ); };
    ok( $@, 'invalid peer id rejected' );
}

sub bad_info_hash_in_handshake : Test {
    my ($self) = @_;
    eval { $self->send_handshake_to_peer( info_hash => $peer_id ); };
    ok( $@, 'invalid info hash rejected' );
}

sub double_handshake : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer; };
    ok( not($@), $@ || 'first handshake is okay' );

    eval { $self->send_handshake_to_peer; };
    ok( $@, 'second handshake is not okay' );

}

sub valid_handshake : Tests {
    my ($self) = @_;

    # expect that a handshake, and only a handshake, was sent
    is(
        $self->next_message_in_queue,
        bt_build_packet(
            bt_code   => BT_HANDSHAKE,
            info_hash => $info_hash,
            peer_id   => $client_id
        ),
        'got a handshake'
    );

    is( $self->next_message_in_queue, undef, 'only a single message' );

    # be a nice peer and respond with our own handshake
    eval { $self->send_handshake_to_peer; };
    ok( not($@), $@ || 'return on handshake accepted' );

    # after we shake back, we get the bitfield
    is(
        $self->next_message_in_queue,
        bt_build_packet(
            bt_code      => BT_BITFIELD,
            bitfield_ref => \$bitfield
        ),
        'got a bitfield'
    );

    # check initial settings
    is_deeply( $self->{peer}->has(), [], 'peer has no pieces' );
    is( $self->{peer}->interested(), 0, 'we are initially not interested' );

    $self->send_bitfield_to_peer;

    is_deeply( $self->{peer}->has(), [ 0, 1, 2 ], 'tracked what we have' );
}

sub choking : Tests {
    my ($self) = @_;

    $self->send_handshake_to_peer->next_message_in_queue(2); # eat the handshake

    is( $self->{peer}->choking(), 1, 'we are initially choking' );

    $self->{peer}->unchoke();
    is(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_UNCHOKE ),
        'an unchoke packet was sent'
    );

    is( $self->{peer}->choking(), 0, 'we are now not choking' );

    $self->{peer}->choke();
    is(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_CHOKE ),
        'a choke packet was sent'
    );

    is( $self->{peer}->choking(), 1, 'we are now choking' );
}

sub being_choked : Tests {
    my ($self) = @_;

    $self->send_handshake_to_peer->next_message_in_queue;    # eat the handshake

    is( $self->{peer}->choked(), 1, 'we are initially being choked' );

    $self->send_packet_to_peer(BT_UNCHOKE);

    is( $self->{peer}->choked(), 0, 'we are now unchoked' );

    $self->send_packet_to_peer(BT_CHOKE);

    is( $self->{peer}->choked(), 1, 'we are now choked' );
}

sub interested : Tests {
    my ($self) = @_;

    $self->send_handshake_to_peer->next_message_in_queue(2); # eat the handshake

    is( $self->{peer}->interested(),
        0, 'we are initially not interested in the peer' );

    $self->{peer}->show_interest;
    is(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_INTERESTED ),
        'an interested packet was sent'
    );

    is( $self->{peer}->interested(), 1, 'we are now interested in the peer' );

    $self->{peer}->show_disinterest;
    is(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_UNINTERESTED ),
        'an uninterested packet was sent'
    );

    is( $self->{peer}->interested(),
        0, 'we are now not interested in the peer' );
}

sub interesting : Tests {
    my ($self) = @_;

    $self->send_handshake_to_peer->next_message_in_queue;    # eat the handshake

    is( $self->{peer}->interesting,
        0, 'we are initially not interesting to the peer' );

    $self->send_packet_to_peer(BT_INTERESTED);

    is( $self->{peer}->interesting, 1, 'we are now interesting to the peer' );

    $self->send_packet_to_peer(BT_UNINTERESTED);

    is( $self->{peer}->interesting,
        0, 'we are no longer interesting to the peer' );
}

sub bitfield_too_early : Test {
    my ($self) = @_;
    eval { $self->send_bitfield_to_peer; };
    ok( $@, 'need to handshake before calling bitfield' );
}

sub double_bitfield : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->send_bitfield_to_peer; };
    ok( not($@), $@ || 'send a handshake and a bitfield' );

    eval { $self->send_bitfield_to_peer; };
    ok( $@, 'can only send a bitfield once' );
}

sub bitfield_after_choke : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->send_packet_to_peer(BT_CHOKE); };
    ok( not($@), $@ || 'choked the peer' );

    eval { $self->send_bitfield_to_peer; };
    ok( $@, 'can not send bitfield after choke' );
}

sub have : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue(2); };
    ok( not($@), $@ || 'shaking hands' );

    is_deeply( $self->{peer}->have(), [], 'nothing to start with' );

    $self->{peer}->have(4);

    is(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_HAVE, piece_index => 4 ),
        'a notice about packet four was sent'
    );

    is_deeply( $self->{peer}->have(), [4], 'now I have piece four' );

    $self->{peer}->have(3);

    is(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_HAVE, piece_index => 3 ),
        'a notice about packet three was sent'
    );

    is_deeply(
        [ sort @{ $self->{peer}->have() } ],
        [ 3, 4 ],
        'now I have piece four'
    );
}

sub has : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue; };
    ok( not($@), $@ || 'shaking hands' );

    is_deeply( $self->{peer}->has(), [], 'nothing to start with' );

    $self->send_to_peer( bt_code => BT_HAVE, piece_index => 2 );

    is_deeply( $self->{peer}->has(), [2], 'peer has index two' );

    $self->send_to_peer( bt_code => BT_HAVE, piece_index => 0 );

    is_deeply(
        [ sort @{ $self->{peer}->has() } ],
        [ 0, 2 ],
        'peer has indexes zero and two'
    );
}

sub request : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue(2); };
    ok( not($@), $@ || 'shaking hands' );

    my %request = ( piece_index => 4, block_offset => 0, block_size => 100 );

    $self->{peer}->request( %request, callback => sub { } );

    is(
        $self->next_message_in_queue,
        bt_build_packet(
            bt_code      => BT_REQUEST,
            piece_index  => 4,
            block_offset => 0,
            block_size   => 100
        ),
        'request the first few bytes of a piece'
    );
}

sub requested_by_peer : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue; };
    ok( not($@), $@ || 'shaking hands' );
    $self->send_to_peer(
        bt_code      => BT_REQUEST,
        piece_index  => 10,
        block_offset => 12345,
        block_size   => 9876
    );
    is_deeply(
        $self->{peer}->requested_by_peer(),
        [ { piece_index => 10, block_offset => 12345, block_size => 9876 } ],
        'added a piece to the queue'
    );
    $self->send_to_peer(
        bt_code      => BT_REQUEST,
        piece_index  => 12,
        block_offset => 0,
        block_size   => 1000
    );
    is_deeply(
        $self->{peer}->requested_by_peer(),
        [
            { piece_index => 10, block_offset => 12345, block_size => 9876 },
            { piece_index => 12, block_offset => 0,     block_size => 1000 },
        ],
        'added a piece to the queue'
    );
}

sub piece : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue(2); };
    ok( not($@), $@ || 'shaking hands' );

    my $piece_index  = 1;
    my $block_offset = 0;
    my $block_size   = 0;
    my $data         = '0123456789';
    { use bytes; $block_size = length($data); }

    $self->send_to_peer(
        bt_code      => BT_REQUEST,
        piece_index  => $piece_index,
        block_offset => $block_offset,
        block_size   => $block_size
    );

    $self->{peer}->piece( $piece_index, $block_offset, \$data );

    is_deeply(
        $self->next_message_in_queue,
        bt_build_packet(
            bt_code      => BT_PIECE,
            piece_index  => $piece_index,
            block_offset => $block_offset,
            data_ref     => \$data
        ),
        'sent piece successfully'
    );

    is_deeply( $self->{peer}->requested_by_peer, [], 'cleared request queue' );
}

sub zincoming_piece : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue(2); };
    ok( not($@), $@ || 'shaking hands' );

    my $returned_data_ref;
    my $piece_index  = 1;
    my $block_offset = 0;
    my $block_size   = 0;
    my $data         = '0123456789';
    my $callback     =
      sub { print "CALLING BACK MOTHER FUCKER\n"; $returned_data_ref = shift; };
    { use bytes; $block_size = length($data); }

    $self->{peer}->request(
        piece_index  => $piece_index,
        block_offset => $block_offset,
        block_size   => $block_size,
        callback     => $callback,
    );

    is_deeply(
        $self->{peer}->requested_by_client,
        [
            {
                piece_index  => $piece_index,
                block_offset => $block_offset,
                block_size   => $block_size,
                callback     => $callback,
            }
        ],
        'cleared request queue'
    );
    is_deeply(
        $self->next_message_in_queue,
        bt_build_packet(
            bt_code      => BT_REQUEST,
            piece_index  => $piece_index,
            block_offset => $block_offset,
            block_size   => $block_size,
        ),
        'sent piece successfully'
    );

    $self->send_to_peer(
        bt_code      => BT_PIECE,
        piece_index  => $piece_index,
        block_offset => $block_offset,
        data_ref     => \$data
    );

    is_deeply( $self->{peer}->requested_by_client, [],
        'cleared request queue' );

    is_deeply( ${$returned_data_ref}, $data, 'returned data matches' );
}

sub unrequested_piece : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue(2); };
    ok( not($@), $@ || 'shaking hands' );

    my $piece_index  = 1;
    my $block_offset = 0;
    my $block_size   = 0;
    my $data         = '0123456789';
    { use bytes; $block_size = length($data); }

    eval { $self->{peer}->piece( $piece_index, $block_offset, \$data ); };
    ok( $@, 'got an unrequested piece when no requests have been made' );

    my @requests;
    for my $offset ( 0 .. 2 ) {
        $self->send_to_peer(
            bt_code      => BT_REQUEST,
            piece_index  => $piece_index + $offset,
            block_offset => $block_offset,
            block_size   => $block_size
        );
        push @requests,
          {
            piece_index  => $piece_index + $offset,
            block_offset => $block_offset,
            block_size   => $block_size
          };
    }

    eval { $self->{peer}->piece( $piece_index + 10, $block_offset, \$data ); };
    ok( $@, 'got an unrequested piece on piece index' );

    eval { $self->{peer}->piece( $piece_index, $block_offset + 1, \$data ); };
    ok( $@, 'got an unrequested piece on block offset' );

    eval {
        my $d = substr( $data, 1, 1 );
        $self->{peer}->piece( $piece_index, $block_offset, \$d );
    };
    ok( $@, 'got an unrequested piece on block size' );

    is_deeply( $self->{peer}->requested_by_peer,
        \@requests, 'kept request queue' );

    $self->{peer}->piece( $piece_index, $block_offset, \$data );
    is_deeply(
        $self->next_message_in_queue,
        bt_build_packet(
            bt_code      => BT_PIECE,
            piece_index  => $piece_index,
            block_offset => $block_offset,
            data_ref     => \$data
        ),
        'sent piece successfully'
    );

    shift @requests;
    is_deeply( $self->{peer}->requested_by_peer,
        \@requests, 'cleared request queue' );
}

sub cancel : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue(2); };
    ok( not($@), $@ || 'shaking hands' );

    my %request = (
        piece_index  => 0,
        block_offset => 100,
        block_size   => 10,
        callback     => sub { }
    );

    $self->{peer}->request(%request);
    $self->next_message_in_queue;

    is_deeply(
        $self->{peer}->requested_by_client,
        [ \%request ],
        'made a request'
    );

    $self->{peer}->cancel(%request);

    is_deeply( $self->{peer}->requested_by_client, [], 'canceled the request' );

    is(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_CANCEL, %request ),
        'cancel message sent'
    );
}

sub incoming_cancel : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue; };
    ok( not($@), $@ || 'shaking hands' );

    my %request = ( piece_index => 0, block_offset => 100, block_size => 10 );

    $self->send_to_peer( bt_code => BT_REQUEST, %request );

    is_deeply(
        $self->{peer}->requested_by_peer,
        [ \%request ],
        'canceled the request'
    );

    $self->send_to_peer( bt_code => BT_CANCEL, %request );

    is_deeply( $self->{peer}->requested_by_peer, [], 'canceled the request' );
}

sub next_message_in_queue {
    my ( $self, $message_count ) = ( @_, 1 );
    my @messages;
    for ( 1 .. $message_count ) {
        push @messages, ( shift @{ $self->{comm}->{messages} } );
    }
    return $message_count == 1 ? $messages[0] : @messages;
}

sub send_handshake_to_peer {
    my $self = shift;
    my %args = (
        bt_code   => BT_HANDSHAKE,
        info_hash => $info_hash,
        peer_id   => $peer_id,
        @_
    );
    return $self->send_to_peer(%args);
}

sub send_bitfield_to_peer {
    my $self = shift;
    my %args = (
        bt_code      => BT_BITFIELD,
        bitfield_ref => \$bitfield,
        @_
    );
    return $self->send_to_peer(%args);
}

sub send_packet_to_peer {
    my ( $self, $packet_type ) = @_;
    return $self->send_to_peer( bt_code => $packet_type );
}

sub send_to_peer {
    my $self = shift;
    $self->{comm}->callback( bt_build_packet(@_) );
    return $self;
}

1;
