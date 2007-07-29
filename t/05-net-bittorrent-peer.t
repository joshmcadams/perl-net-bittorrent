use warnings;
use strict;

package TestPeer;

=head1 DESCRIPTION

There are ten packet types that get passed around among peers, which of course,
leads to quite a few test cases.  This is a fairly heavily commented testing
script because it might not be immediately obvous what is being done with any
of the given test cases.  For the most part, we are testing the inbound and
outbound messaging for each of the ten packet types.  Some types require more
edge cases then others and therefore get some extra testing methods.

In these tests, C<peer> refers to the remote agent and C<client> refers to
the local client.  This termionolgy is somewhat important because in a p2p
network, everyone is a 'p'.

=cut

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

=head1 Consistent Subroutines

=head2 setup_test

The C<Net::BitTorrent::Peer> is an intermediate object that serves as a buffer
between the master torrent organizer and the actual communication layer that
peers communicate on.  In the setup, we create a mocked
C<Net::BitTorrent::PeerComunicator> and set up that C<Communicator> so that it
intercepts and saves messages that would normally be passed over the wire.
Basically, C<send_message> just saves the message to the mocked object and
then some callback ability is added in.

Also, notice that we create a peer in the setup.  The peer is passed some
defaults that work well for most of the tests that are currently performed.
Note, however, that by instantiating the peer, we cause it to give us a
handshake and a bitref, so there will be two messages saved to our mocked
communicator before anything is done.  You'll notice a convienience method
that knocks these messages off the list used a lot below.

=cut

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

=head1 Tests

=head2 use_the_module

duh!

=cut

sub use_the_module : Test( startup => 1 ) {
    use_ok('Net::BitTorrent::Peer');
}

=head2 Handshake and Bitfield Tests

We need to test that the handshake happens once, and only once
and that it is the first peice of communication between peers.
This is also a decent time to check the bitfield.

=cut

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

=head2 Choking Tests

=cut

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

    $self->send_handshake_to_peer->next_message_in_queue(2); # eat the handshake

    is( $self->{peer}->choked(), 1, 'we are initially being choked' );

    $self->send_packet_to_peer(BT_UNCHOKE);

    is( $self->{peer}->choked(), 0, 'we are now unchoked' );

    $self->send_packet_to_peer(BT_CHOKE);

    is( $self->{peer}->choked(), 1, 'we are now choked' );
}

=head2 Interested Tests

=cut

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

=head2 Have Tests

=cut

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

    $self->message_from_peer( bt_code => BT_HAVE, piece_index => 2 );

    is_deeply( $self->{peer}->has(), [2], 'peer has index two' );

    $self->message_from_peer( bt_code => BT_HAVE, piece_index => 0 );

    is_deeply(
        [ sort @{ $self->{peer}->has() } ],
        [ 0, 2 ],
        'peer has indexes zero and two'
    );
}

=head2 Request Tests

=cut

sub request : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue(2); };
    ok( not($@), $@ || 'shaking hands' );

    my %request = ( piece_index => 4, block_offset => 0, block_size => 100 );

    $self->{peer}->request( %request, callback => sub { } );

    is_deeply( scalar( @{ $self->{peer}->requested_by_client } ),
        1, 'request queue populated' );

    is(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_REQUEST, %request ),
        'request the first few bytes of a piece'
    );

    $self->{peer}->request( %request, callback => sub { } );

    is_deeply( scalar( @{ $self->{peer}->requested_by_client } ),
        1, 'request not duplicated' );

    is(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_REQUEST, %request ),
        'request resent'
    );

}

sub requested_by_peer : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue; };
    ok( not($@), $@ || 'shaking hands' );

    my %first_request = (
        piece_index  => 10,
        block_offset => 12345,
        block_size   => 9876
    );

    my %second_request = (
        piece_index  => 12,
        block_offset => 52345,
        block_size   => 876
    );

    $self->message_from_peer( bt_code => BT_REQUEST, %first_request );
    is_deeply(
        $self->{peer}->requested_by_peer(),
        [ \%first_request ],
        'added a request to the queue'
    );

    $self->message_from_peer( bt_code => BT_REQUEST, %second_request );
    is_deeply(
        $self->{peer}->requested_by_peer(),
        [ \%first_request, \%second_request ],
        'added a piece to the queue'
    );

    $self->message_from_peer( bt_code => BT_REQUEST, %first_request );
    is_deeply(
        $self->{peer}->requested_by_peer(),
        [ \%first_request, \%second_request ],
        'ignore duplicate requests'
    );
}

=head2 Piece Tests

=cut

sub piece : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue(2); };
    ok( not($@), $@ || 'shaking hands' );

    my $block_size = 0;
    my $data       = '0123456789';
    { use bytes; $block_size = length($data); }

    my %piece = (
        piece_index  => 1,
        block_offset => 0,
        data_ref     => \$data
    );

    my %request = (
        piece_index  => 1,
        block_offset => 0,
        block_size   => $block_size
    );

    $self->message_from_peer( bt_code => BT_REQUEST, %request );

    is_deeply( scalar( @{ $self->{peer}->requested_by_peer } ),
        1, 'added to request queue' );

    $self->{peer}->piece(%piece);

    is_deeply(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_PIECE, %piece ),
        'sent piece successfully'
    );

    is_deeply( $self->{peer}->requested_by_peer, [], 'cleared request queue' );

    eval { $self->{peer}->piece(%piece); };
    ok( $@, 'failed to send unrequested piece' );

    $self->message_from_peer( bt_code => BT_REQUEST, %request );

    is_deeply( scalar( @{ $self->{peer}->requested_by_peer } ),
        1, 'request queue populated' );

    eval {
        $self->{peer}->piece( %piece, piece_index => $piece{piece_index} + 1 );
    };
    ok( $@, 'failed to send unrequested piece because of piece index' );
    is_deeply( scalar( @{ $self->{peer}->requested_by_peer } ),
        1, 'request queue still populated' );

    eval {
        $self->{peer}
          ->piece( %piece, block_offset => $piece{block_offset} + 1 );
    };
    ok( $@, 'failed to send unrequested piece because of block offset' );
    is_deeply( scalar( @{ $self->{peer}->requested_by_peer } ),
        1, 'request queue still populated' );

    my $less_data = 'a';
    eval { $self->{peer}->piece( %piece, data_ref => \$less_data ); };
    ok( $@, 'failed to send unrequested piece because of data ref' );
    is_deeply( scalar( @{ $self->{peer}->requested_by_peer } ),
        1, 'request queue still populated' );
}

sub incoming_piece : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue(2); };
    ok( not($@), $@ || 'shaking hands' );

    my $returned_data_ref;
    my $block_size = 0;
    my $data       = '0123456789';
    my $callback   = sub { $returned_data_ref = shift; };
    { use bytes; $block_size = length($data); }

    my %request = (
        piece_index  => 1,
        block_offset => 10,
        block_size   => $block_size,
    );

    my %piece = (
        piece_index  => 1,
        block_offset => 10,
        data_ref     => \$data,
    );

    $self->{peer}->request( %request, callback => $callback );

    is_deeply(
        $self->{peer}->requested_by_client,
        [ { %request, callback => $callback } ],
        'cleared request queue'
    );

    is_deeply(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_REQUEST, %request ),
        'sent piece successfully'
    );

    $self->message_from_peer( bt_code => BT_PIECE, %piece );

    is_deeply( $self->{peer}->requested_by_client, [],
        'cleared request queue' );

    is_deeply( ${$returned_data_ref}, $data, 'returned data matches' );

    eval { $self->message_from_peer( bt_code => BT_PIECE, %piece ); };
    ok( $@, 'got a piece when we were not expecting one' );

    $self->{peer}->request( %request, callback => $callback );

    is( scalar( @{ $self->{peer}->requested_by_client() } ),
        1, 'made a reqeust' );

    eval {
        $self->message_from_peer(
            bt_code => BT_PIECE,
            %piece, piece_index => $piece{piece_index} + 1
        );
    };
    ok( $@, 'got a piece for the wrong piece index' );
    is( scalar( @{ $self->{peer}->requested_by_client() } ),
        1, 'reqeust still queued' );

    eval {
        $self->message_from_peer(
            bt_code => BT_PIECE,
            %piece, block_offset => $piece{block_offset} + 1
        );
    };
    ok( $@, 'got a piece for the wrong block offset' );
    is( scalar( @{ $self->{peer}->requested_by_client() } ),
        1, 'reqeust still queued' );

    my $less_data = 'a';
    eval {
        $self->message_from_peer(
            bt_code => BT_PIECE,
            %piece, data_ref => \$less_data
        );
    };
    ok( $@, 'got a piece for the wrong data block' );
    is( scalar( @{ $self->{peer}->requested_by_client() } ),
        1, 'reqeust still queued' );
}

sub unrequested_piece : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue(2); };
    ok( not($@), $@ || 'shaking hands' );

    my $block_size;
    my $data = '0123456789';
    { use bytes; $block_size = length($data); }

    my %piece = (
        piece_index  => 1,
        block_offset => 0,
        data_ref     => \$data
    );

    my %request = (
        piece_index  => 1,
        block_offset => 0,
        block_size   => $block_size
    );

    eval { $self->{peer}->piece(%piece); };
    ok( $@, 'got an unrequested piece when no requests have been made' );

    my @requests;
    for my $offset ( 0 .. 2 ) {
        $self->message_from_peer(
            bt_code => BT_REQUEST,
            %request, piece_index => $request{piece_index} + $offset
        );
        push @requests,
          { %request, piece_index => $request{piece_index} + $offset };
    }

    eval {
        $self->{peer}
          ->piece( %piece, piece_index => $piece{piece_index} + 1234 );
    };
    ok( $@, 'got an unrequested piece on piece index' );

    eval {
        $self->{peer}
          ->piece( %piece, block_offset => $piece{block_offset} + 1234 );
    };
    ok( $@, 'got an unrequested piece on block offset' );

    eval {
        my $d = substr( $data, 1, 1 );
        $self->{peer}->piece( %piece, data_ref => \$d );
    };
    ok( $@, 'got an unrequested piece on block size' );

    is_deeply( $self->{peer}->requested_by_peer,
        \@requests, 'kept request queue' );

    $self->{peer}->piece(%piece);

    is_deeply(
        $self->next_message_in_queue,
        bt_build_packet( bt_code => BT_PIECE, %piece ),
        'sent piece successfully'
    );

    shift @requests;
    is_deeply( $self->{peer}->requested_by_peer,
        \@requests, 'cleared request queue' );
}

=head2 Cancel Tests

=cut

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

    eval { $self->{peer}->cancel(%request); };
    ok( $@, 'attempt to cancel an unrequested piece' );
    is( $self->next_message_in_queue, undef, 'no request sent to peer' );

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

    $self->{peer}->request(%request);
    $self->next_message_in_queue;

    eval { $self->{peer}->cancel( %request, piece_index => 1234 ); };
    ok( $@, 'attempt to cancel an unrequested piece by piece index' );
    is( $self->next_message_in_queue, undef, 'no request sent to peer' );

    eval { $self->{peer}->cancel( %request, block_offset => 1234 ); };
    ok( $@, 'attempt to cancel an unrequested piece by block offset' );
    is( $self->next_message_in_queue, undef, 'no request sent to peer' );

    eval { $self->{peer}->cancel( %request, block_size => 1234 ); };
    ok( $@, 'attempt to cancel an unrequested piece by block size' );
    is( $self->next_message_in_queue, undef, 'no request sent to peer' );

}

sub incoming_cancel : Tests {
    my ($self) = @_;

    eval { $self->send_handshake_to_peer->next_message_in_queue(2); };
    ok( not($@), $@ || 'shaking hands' );

    my %request = ( piece_index => 0, block_offset => 100, block_size => 10 );

    $self->message_from_peer( bt_code => BT_REQUEST, %request );

    is_deeply(
        $self->{peer}->requested_by_peer,
        [ \%request ],
        'made the request'
    );

    $self->message_from_peer( bt_code => BT_CANCEL, %request );

    is_deeply( $self->{peer}->requested_by_peer, [], 'canceled the request' );

    $self->message_from_peer( bt_code => BT_REQUEST, %request );

    is_deeply(
        $self->{peer}->requested_by_peer,
        [ \%request ],
        'made the request'
    );

    eval {
        $self->message_from_peer(
            bt_code => BT_CANCEL,
            %request, piece_index => 1234
        );
    };
    ok( $@, 'cancel rejected' );

    is_deeply(
        $self->{peer}->requested_by_peer,
        [ \%request ],
        'unable to cancel the request because of piece index'
    );

    eval {
        $self->message_from_peer(
            bt_code => BT_CANCEL,
            %request, block_offset => 1234
        );
    };
    ok( $@, 'cancel rejected' );

    is_deeply(
        $self->{peer}->requested_by_peer,
        [ \%request ],
        'unable to cancel the request because of block offset'
    );

    eval {
        $self->message_from_peer(
            bt_code => BT_CANCEL,
            %request, block_size => 1234
        );
    };
    ok( $@, 'cancel rejected' );

    is_deeply(
        $self->{peer}->requested_by_peer,
        [ \%request ],
        'unable to cancel the request because of block size'
    );
}

=head2 Convenience Methods

=cut

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
    return $self->message_from_peer(%args);
}

sub send_bitfield_to_peer {
    my $self = shift;
    my %args = (
        bt_code      => BT_BITFIELD,
        bitfield_ref => \$bitfield,
        @_
    );
    return $self->message_from_peer(%args);
}

sub send_packet_to_peer {
    my ( $self, $packet_type ) = @_;
    return $self->message_from_peer( bt_code => $packet_type );
}

sub message_from_peer {
    my $self = shift;
    $self->{comm}->callback( bt_build_packet(@_) );
    return $self;
}

1;
