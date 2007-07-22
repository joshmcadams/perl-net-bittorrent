package Net::BitTorrent::Peer;

use warnings;
use strict;
use Net::BitTorrent::PeerPacket qw(:all);
use Carp qw(croak cluck);

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

    $self->{we_are_interested} = 0;
    $self->{has}               = [];
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
        pack( 'c/a* a8 a20 a20',
            'BitTorrent protocol', '',
            $self->{info_hash},    $self->{client_id},
        )
    );

    return $self;
}

sub has {
    return shift->{has};
}

sub choked {
    return 1;
}

sub interested {
    my ($self) = @_;

    return $self->{we_are_interested};
}

sub show_interest {
    my ($self) = @_;

    $self->{we_are_interested} = 1;

    return $self;
}

sub process_message_from_peer {
    my ( $self, $message ) = @_;

    my $parsed_packet = bt_parse_packet( \$message );

    if ( $parsed_packet->{bt_code} == BT_BITFIELD ) {
        my @pieces =
          split( //, unpack( "b*", ${ $parsed_packet->{bitfield_ref} } ) );
        for my $index ( 0 .. $#pieces ) {
            push @{ $self->{has} }, $index if $pieces[$index] > 0;
        }
    }
}

1;

