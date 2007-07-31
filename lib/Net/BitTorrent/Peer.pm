package Net::BitTorrent::Peer;

use warnings;
use strict;
use Net::BitTorrent::PeerPacket qw(:all);
use Carp qw(croak cluck);
use Data::Dumper;

sub new {
    my ( $class, %args ) = @_;

    my $self = bless {%args}, $class;

    $self->_verify_args()->_set_defaults()->_initiate_communication();

    return $self;
}

sub _verify_args {
    my ($self) = @_;

    for (qw(info_hash client_id peer_id communicator downloaded)) {
        croak("$_ required") unless exists $self->{$_};
    }

    return $self;
}

sub _set_defaults {
    my ($self) = @_;

    $self->{packets_processed} = 0;
    $self->{choked}            = 1;
    $self->{choking}           = 1;
    $self->{interesting}       = 0;
    $self->{interested}        = 0;
    $self->{has}               = [];
    $self->{have}              = [];
    $self->{communicator}->set_callback(
        sub {
            $self->process_message_from_peer(@_);
        }
    );

    return $self;
}

sub _initiate_communication {
    my ($self) = @_;

    $self->{communicator}->send_message(
        bt_build_packet(
            bt_code   => BT_HANDSHAKE,
            info_hash => $self->{info_hash},
            peer_id   => $self->{client_id},
        )
    );

    return $self;
}

sub has {
    return shift->{has};
}

sub have {
    my ( $self, $piece_index ) = @_;

    if ( defined $piece_index ) {
        $self->{communicator}->send_message(
            bt_build_packet(
                bt_code     => BT_HAVE,
                piece_index => $piece_index
            )
        );
        push @{ $self->{have} }, $piece_index;
    }

    return $self->{have};
}

sub choked {
    return shift->{choked};
}

sub choking {
    return shift->{choking};
}

sub choke {
    my ($self) = @_;

    $self->{communicator}
      ->send_message( bt_build_packet( bt_code => BT_CHOKE, ) );

    $self->{choking} = 1;

    return;
}

sub unchoke {
    my ($self) = @_;

    $self->{communicator}
      ->send_message( bt_build_packet( bt_code => BT_UNCHOKE, ) );

    $self->{choking} = 0;

    return;
}

sub interesting {
    return shift->{interesting};
}

sub interested {
    my ($self) = @_;

    return $self->{interested};
}

sub show_interest {
    my ($self) = @_;

    $self->{communicator}
      ->send_message( bt_build_packet( bt_code => BT_INTERESTED, ) );

    $self->{interested} = 1;

    return $self;
}

sub show_disinterest {
    my ($self) = @_;

    $self->{communicator}
      ->send_message( bt_build_packet( bt_code => BT_UNINTERESTED, ) );

    $self->{interested} = 0;

    return $self;
}

sub request {
    my ( $self, %args ) = @_;

    push @{ $self->{requested_by_client} }, {%args}
      unless grep                           {
             $args{piece_index} == $_->{piece_index}
          && $args{block_offset} == $_->{block_offset}
          && $args{block_size} == $_->{block_size}
      } @{ $self->{requested_by_client} };

    delete $args{callback};

    $self->{communicator}->send_message(
        bt_build_packet(
            bt_code => BT_REQUEST,
            %args
        )
    );
}

sub requested_by_peer {
    return shift->{requested_by_peer} || [];
}

sub requested_by_client {
    return shift->{requested_by_client} || [];
}

sub cancel {
    my ( $self, %args ) = @_;

    my $index = 0;
    for my $request ( @{ $self->{requested_by_client} || [] } ) {
        if ( $args{piece_index} eq $request->{piece_index} ) {
            if ( $args{block_offset} eq $request->{block_offset} ) {
                if ( $args{block_size} eq $request->{block_size} ) {

                    $self->{communicator}->send_message(
                        bt_build_packet(
                            bt_code => BT_CANCEL,
                            %args
                        )
                    );

                    splice @{ $self->{requested_by_client} }, $index, 1;

                    return;
                }
            }
        }
        ++$index;
    }

    croak 'unable to find request matching piece';
}

sub piece {
    my ( $self, %args ) = @_;

    my $block_size;
    { use bytes; $block_size = length( ${ $args{data_ref} } ); }

    my $index = 0;
    for my $request ( @{ $self->{requested_by_peer} || [] } ) {
        if ( $args{piece_index} eq $request->{piece_index} ) {
            if ( $args{block_offset} eq $request->{block_offset} ) {
                if ( $block_size eq $request->{block_size} ) {

                    $self->{communicator}->send_message(
                        bt_build_packet(
                            bt_code => BT_PIECE,
                            %args
                        )
                    );

                    splice @{ $self->{requested_by_peer} }, $index, 1;

                    return;
                }
            }
        }
        ++$index;
    }

    croak 'unable to find request matching piece';
}

sub process_message_from_peer {
    my ( $self, $message ) = @_;

    my $parsed_packet = bt_parse_packet( \$message );

    $self->{packets_processed}++;

    if ( $parsed_packet->{bt_code} == BT_HANDSHAKE ) {
        croak 'handshake can only be the first message processed'
          unless $self->{packets_processed} == 1;
        croak 'unexpected info hash received'
          unless $parsed_packet->{info_hash} eq $self->{info_hash};
        croak 'unexpected peer id received'
          unless $parsed_packet->{peer_id} eq $self->{peer_id};

        my $bitfield = pack( "b*", join( '', @{ $self->{downloaded} } ) );
        $self->{communicator}->send_message(
            bt_build_packet(
                bt_code      => BT_BITFIELD,
                bitfield_ref => \$bitfield,
            )
        );

        return;
    }

    if ( $parsed_packet->{bt_code} == BT_BITFIELD ) {
        croak 'bitfield can only be the second message processed'
          unless $self->{packets_processed} == 2;
        my @pieces =
          split( //, unpack( "b*", ${ $parsed_packet->{bitfield_ref} } ) );
        for my $index ( 0 .. $#pieces ) {
            push @{ $self->{has} }, $index if $pieces[$index] > 0;
        }
        return;
    }

    croak 'all peer communication must begin with a handshake'
      unless $self->{packets_processed} > 1;

    if ( $parsed_packet->{bt_code} == BT_UNCHOKE ) {
        $self->{choked} = 0;
    }
    elsif ( $parsed_packet->{bt_code} == BT_CHOKE ) {
        $self->{choked} = 1;
    }
    elsif ( $parsed_packet->{bt_code} == BT_INTERESTED ) {
        $self->{interesting} = 1;
    }
    elsif ( $parsed_packet->{bt_code} == BT_UNINTERESTED ) {
        $self->{interesting} = 0;
    }
    elsif ( $parsed_packet->{bt_code} == BT_HAVE ) {
        push @{ $self->{has} }, $parsed_packet->{piece_index};
    }
    elsif ( $parsed_packet->{bt_code} == BT_REQUEST ) {
        delete $parsed_packet->{bt_code};
        push @{ $self->{requested_by_peer} }, $parsed_packet
          unless grep {
                 $parsed_packet->{piece_index} == $_->{piece_index}
              && $parsed_packet->{block_offset} == $_->{block_offset}
              && $parsed_packet->{block_size} == $_->{block_size}
          } @{ $self->{requested_by_peer} };
    }
    elsif ( $parsed_packet->{bt_code} == BT_PIECE ) {
        my $index      = 0;
        my $block_size = 0;
        { use bytes; $block_size = length( ${ $parsed_packet->{data_ref} } ); }
        for my $request ( @{ $self->{requested_by_client} || [] } ) {
            if ( $parsed_packet->{piece_index} eq $request->{piece_index} ) {
                if (
                    $parsed_packet->{block_offset} eq $request->{block_offset} )
                {
                    if ( $block_size eq $request->{block_size} ) {
                        $self->{requested_by_client}->[$index]->{callback}
                          ->( $parsed_packet->{data_ref} )
                          if exists $self->{requested_by_client}->[$index]
                          ->{callback};
                        splice @{ $self->{requested_by_client} }, $index, 1;
                        return;
                    }
                }
            }
            ++$index;
        }

        croak 'unable to find request matching piece';

    }
    elsif ( $parsed_packet->{bt_code} == BT_CANCEL ) {
        my $index = 0;
        for my $request ( @{ $self->{requested_by_peer} || [] } ) {
            if ( $parsed_packet->{piece_index} eq $request->{piece_index} ) {
                if (
                    $parsed_packet->{block_offset} eq $request->{block_offset} )
                {
                    if (
                        $parsed_packet->{block_size} eq $request->{block_size} )
                    {
                        splice @{ $self->{requested_by_peer} }, $index, 1;
                        return;
                    }
                }
            }
            ++$index;
        }

        croak 'unable to find request matching cancel';

    }

    return;
}

1;

__END__

=head1 NAME

Net::BitTorrent::Peer

=head1 DESCRIPTION

The C<Net::BitTorrent::Peer> object provides an internal interface for communicating
with peers in a BitTorrent swarm.  The interface doesn't do any networking, but instead
relies on a communicator to do the socket-talking on it's behalf and reply to incoming
messages with callbacks.

=head1 SYNOPSYS

=head1 METHODS

=head2 Public

=head3 new

Creates a new C<Net::BitTorrent::Peer> object.  There are a few arguments that
the constructor requires:

=head4 info_hash

The info hash that uniquely identifies the swarm that the C<.torrent> represents.

=head4 client_id

The 20-byte identifier for the local client.

=head4 peer_id

The 20-byte identifier for the remote peer.

=head4 downloaded

A reference to an array that contains an entry for each piece in the torrent.  If the
piece has already been successfully downloaded by the client, the array element with
the same index contains a value of 1.  If the piece has not been downloaded, the array
element with the same index contains a value of 0.

=head5 communicator

A reference to a C<Net::BitTorrent::PeerCommunicator> object.

=head3 has

Returns an array reference containing a list of piece indexes that the peer has.

=head3 have

Informs the peer that the local client has a new piece.

=head3 choked

Returns true if we are choked, false if not.

=head3 choking

Returns true if we are choking the peer, false if not.

=head3 choke

Informs the peer that we are choking it.

=head3 unchoke

Informs the peer that we are uncoking it.

=head3 interesting

Returns true if the peer finds us interesting, false if not.

=head3 interested

Returns true if we are intested in the peer, false if not.

=head3 show_interest

Informs the peer that we are interested in it.

=head3 show_disinterest

Informs the peer that we are not interested in it.

=head3 request

Requests a block of a piece from a peer.

=head4 piece_index

Zero-based index of the piece that we need.

=head4 block_offset

Zero-based offset of the starting point of the block that we
are requesting.

=head4 block_size

Size of the block that we are requesting.

=head4 callback

Subroutine reference that will be called back when the peer responds to the
request.  The first argument to the callback will be a reference to the 
data that the peer returned.

=head3 requested_by_peer

Returns a reference to an array of requests made by the peer.  Each request
is a hash reference with the following three keys:

=head4 piece_index

Zero-based index of the piece that was requested.

=head4 block_offset

Zero-based offset of the start of the block that is being requested from
within the piece.

=head4 block_size

Size of the data block being requested from within the piece.

=head3 requested_by_client

Returns a reference to an array of requests made by the client.  Each request
is a hash reference with the following four keys:

=head4 piece_index

Zero-based index of the piece that was requested.

=head4 block_offset

Zero-based offset of the start of the block that is being requested from
within the piece.

=head4 block_size

Size of the data block being requested from within the piece.

=head4 callback

Reference to a subroutine that will be called back when the peer responds to
the request.

=head3 cancel

Tell the peer that we no longer need a piece the we requested.

=head3 piece

Return a block of data to the peer.  Each piece call requires the following
arguments:

=head4 piece_index

Zero-based index of the piece that was requested.

=head4 block_offset

Zero-based offset of the start of the block that is being requested from
within the piece.

=head4 data_ref

Reference to the data that will be sent to the peer.

=head3 process_message_from_peer

=head2 Private

=head3 _verify_args

Verifies that the constructor was passed reasonable arguments.

=head3 _set_defaults

Sets default arguments for the constructor.

=head3 _initiate_communication

Send a handshake and bitfield to the peer.

=cut

