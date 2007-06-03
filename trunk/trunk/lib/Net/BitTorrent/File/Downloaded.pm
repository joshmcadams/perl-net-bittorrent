package Net::BitTorrent::File::Downloaded;

use warnings;
use strict;
use Carp;
use IO::File;
use List::MoreUtils qw(first_index);

sub new {
    my ( $class, %args ) = @_;
    my $self = bless \%args, $class;

    $self->_check_arguments();

    return $self;
}

sub _check_arguments {
    my ($self) = @_;

    croak('A DotTorrent object is required')
      unless $self->{dt_obj};

    $self->{files}            = $self->{dt_obj}->get_files();
    $self->{remaining_pieces} =
      [ 0 .. $self->{dt_obj}->get_total_piece_count() - 1 ];
    $self->{completed_pieces} = [];

    return $self;
}

sub get_remaining_piece_list {
    return $_[0]->{remaining_pieces};
}

sub get_completed_piece_list {
    return $_[0]->{completed_pieces};
}

sub get_remaining_segments_list_for_piece {
    my ( $self, $piece ) = @_;
    return [ { offset => 0, size => 6169 } ];
}

sub write_segment {
    my ( $self, %args ) = @_;

    my $piece_index =
      first_index { $_ == $args{piece} } @{ $self->{remaining_pieces} };
    return unless $piece_index >= 0;

    my $fh = IO::File->new( $self->{files}->[0]->{path}, 'w' ) || croak($!);
    print {$fh} ${ $args{data_ref} } || croak($!);
    $fh->close();

    if ( $self->{remaining_pieces}->[$piece_index] == $args{piece} ) {
        push @{ $self->{completed_pieces} },
          splice @{ $self->{remaining_pieces} }, $piece_index, 1;
    }

    return 1;
}

1;

