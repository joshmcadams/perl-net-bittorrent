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

    return;
}

1;

