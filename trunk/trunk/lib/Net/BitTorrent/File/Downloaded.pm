package Net::BitTorrent::File::Downloaded;

use warnings;
use strict;
use Carp;
use IO::File;
use List::MoreUtils qw(first_index);
use File::Slurp qw(read_file);
use Digest::SHA1 qw(sha1);
use File::Spec;

sub new {
    my ( $class, %args ) = @_;
    my $self = bless \%args, $class;

    $self->_check_arguments()->_pick_up_where_we_left_off();

    return $self;
}

sub _check_arguments {
    my ($self) = @_;

    croak('A DotTorrent object is required')
      unless $self->{dt_obj};

    $self->{files}            = $self->{dt_obj}->get_files();
    $self->{remaining_pieces} =
      [ 0 .. $self->{dt_obj}->get_total_piece_count() - 1 ];
    $self->{completed_pieces}      = [];
    $self->{pieces_sha1_hashes}    = $self->{dt_obj}->get_pieces_array();
    $self->{standard_piece_length} =
      $self->{dt_obj}->get_standard_piece_length();
    $self->{final_partial_piece_length} =
      $self->{dt_obj}->get_final_partial_piece_length();
    $self->{total_piece_count} = $self->{dt_obj}->get_total_piece_count();

    return $self;
}

sub _pick_up_where_we_left_off {
    my ($self) = @_;

    for my $piece_file ( glob('*.piece') ) {
        my ($piece_number) = $piece_file;
        $piece_number =~ s/\D//g;

        if ( $self->{pieces_sha1_hashes}->[$piece_number] eq
            sha1( read_file( $piece_file, binmode => ':raw' ) ) )
        {
            my $index_in_remaining =
              first_index { $_ == $piece_number }
              @{ $self->{remaining_pieces} };
            push @{ $self->{completed_pieces} },
              splice @{ $self->{remaining_pieces} }, $index_in_remaining, 1;
            $self->_are_we_done_yet($piece_number);
        }
        else {
            unlink $piece_file;
        }
    }

    return $self;
}

sub get_remaining_piece_list {
    return $_[0]->{remaining_pieces};
}

sub get_completed_piece_list {
    return $_[0]->{completed_pieces};
}

sub get_remaining_blocks_list_for_piece {
    my ( $self, $piece ) = @_;

    if ( ( first_index { $piece == $_ } @{ $self->{completed_pieces} } ) >= 0 )
    {
        return [];
    }

    my $piece_length =
      ( $self->{final_partial_piece_length}
          && ( $piece == ( $self->{total_piece_count} - 1 ) ) )
      ? $self->{final_partial_piece_length}
      : $self->{standard_piece_length};

    if ( my $size = -s $piece . '.piece' ) {
        return [ { offset => $size, size => $piece_length - $size } ];
    }

    return [ { offset => 0, size => $piece_length } ];
}

sub write_block {
    my ( $self, %args ) = @_;

    my $piece_index =
      first_index { $_ == $args{piece} } @{ $self->{remaining_pieces} };
    return unless $piece_index >= 0;

    my $piece_file = $args{piece} . '.piece';

    # write the data to a 'piece' file
    {
        my $fh = IO::File->new( $piece_file, 'a' ) || croak($!);
        binmode $fh;
        $fh->seek( $args{offset}, 0 );
        print {$fh} ${ $args{data_ref} } || croak($!);
        $fh->close();
    }

    my $completed_piece_length =
        $piece_index == $self->{total_piece_count} - 1
      ? $self->{final_partial_piece_length}
      : $self->{standard_piece_length};

    if (
        ( -s $piece_file == $completed_piece_length )
        && ( $self->{pieces_sha1_hashes}->[ $args{piece} ] eq
            sha1( read_file( $piece_file, binmode => ':raw' ) ) )
      )
    {
        push @{ $self->{completed_pieces} },
          splice @{ $self->{remaining_pieces} }, $piece_index, 1;

        $self->_are_we_done_yet($piece_index);
    }

    return 1;
}

sub _are_we_done_yet {
    my ( $self, $piece_index ) = @_;

    return if @{ $self->{remaining_pieces} };

    my $final_file = $self->{files}->[0]->{path};

    my @dirs = File::Spec->splitdir($final_file);
    pop @dirs;
    my $long_dir;
    for my $dir (@dirs) {
        $long_dir =
          defined $long_dir ? File::Spec->join( $long_dir, $dir ) : $dir;
        mkdir $long_dir;
    }

    my $fh = IO::File->new( $final_file, O_RDWR | O_CREAT ) || croak $!;
    binmode($fh);

    for my $piece ( sort { $a <=> $b } @{ $self->{completed_pieces} } ) {
        my $piece_file = $piece . '.piece';
        print {$fh} read_file( $piece_file, binmode => ':raw' ) || croak $!;
        unlink $piece_file;
    }

    $fh->close();
}

1;

