use warnings;
use strict;
use Test::More qw(no_plan);
use Test::MockObject;
use String::Random qw(random_string);
use File::Slurp;
use Digest::SHA1 qw(sha1);
use Data::Dumper;
use File::Remove qw(remove);
use IO::File;

use_ok('Net::BitTorrent::File::Downloaded');

remove \1, '*.piece';
remove \1, '*.delete*';

sub setup_new_dl_object {
    my ($mocks) = @_;
    my $dt_obj = Test::MockObject->new();
    $dt_obj->mock( $_, $mocks->{$_} ) for keys %{$mocks};

    my $dl = Net::BitTorrent::File::Downloaded->new( dt_obj => $dt_obj );
    isa_ok( $dl, 'Net::BitTorrent::File::Downloaded' );

    return $dl;
}

sub check_status_of_pieces {
    my ( $dl, %args ) = @_;
    is_deeply(
        [ sort @{ $dl->get_remaining_piece_list } ],
        [ sort @{ $args{remaining} } ],
        ( $args{label} || '' ) . ' - remaining piece list'
    );
    is_deeply(
        [ sort @{ $dl->get_completed_piece_list } ],
        [ sort @{ $args{completed} } ],
        ( $args{label} || '' ) . ' - completed piece list'
    );
    for my $piece ( keys %{ $args{remaining_blocks} } ) {
        is_deeply(
            $dl->get_remaining_blocks_list_for_piece($piece),
            $args{remaining_blocks}{$piece},
            ( $args{label} || '' ) . ' - remaining blocks for piece ' . $piece
        );
    }
}

ONE_PIECE_IN_ONE_BLOCK: {
    my $label     = 'one piece in one block';
    my $file_name = random_string('ccccc') . '.delete';
    my $file_size = 10;

    my $data = random_string( '.' x $file_size );

    my %mocks = (
        'get_torrent_file_name'          => sub { $file_name . '.torrent' },
        'multiple_files_exist'           => sub { 0 },
        'get_suggested_file_name'        => sub { $file_name },
        'get_standard_piece_length'      => sub { 32768 },
        'get_total_piece_count'          => sub { 1 },
        'get_total_download_size'        => sub { $file_size },
        'get_whole_piece_count'          => sub { 0 },
        'final_partial_piece_exists'     => sub { 1 },
        'get_final_partial_piece_length' => sub { $file_size },
        'get_tracker' => sub { 'http://my.tracker:6969/announce' },
        'get_files'   =>
          sub { [ { 'length' => $file_size, 'path' => $file_name, }, ] },
        'get_pieces_array' => sub { [ sha1($data) ] },
    );

    my $dl = setup_new_dl_object( \%mocks );

    check_status_of_pieces(
        $dl,
        remaining        => [0],
        completed        => [],
        remaining_blocks => { 0 => [ { offset => 0, size => 10 } ], },
        label            => "$label, pre-write",
    );

    ok( $dl->write_block( piece => 0, offset => 0, data_ref => \$data ),
        "$label, first write" );

    my $data_from_file = read_file($file_name);
    is( $data_from_file, $data, "$label, everything wrote appropriately" );

    check_status_of_pieces(
        $dl,
        remaining        => [],
        completed        => [0],
        remaining_blocks => { 0 => [] },
        label            => "$label, after write",
    );

    remove '*.piece';
    remove '*.delete*';
}

ONE_PIECE_WITH_TWO_BLOCKS: {
    my $label     = 'one piece with two blocks';
    my $file_name = random_string('ccccc') . '.delete';
    my $file_size = 10;

    my $data      = random_string( '.' x ( $file_size - 1 ) );
    my $more_data = random_string('.');

    my %mocks = (
        'get_torrent_file_name'          => sub { $file_name . '.torrent' },
        'multiple_files_exist'           => sub { 0 },
        'get_suggested_file_name'        => sub { $file_name },
        'get_standard_piece_length'      => sub { 32768 },
        'get_total_piece_count'          => sub { 1 },
        'get_total_download_size'        => sub { $file_size },
        'get_whole_piece_count'          => sub { 0 },
        'final_partial_piece_exists'     => sub { 1 },
        'get_final_partial_piece_length' => sub { $file_size },
        'get_tracker' => sub { 'http://my.tracker:6969/announce' },
        'get_files'   =>
          sub { [ { 'length' => $file_size, 'path' => $file_name, }, ] },
        'get_pieces_array' => sub { [ sha1( $data . $more_data ) ] },
    );

    my $dl = setup_new_dl_object( \%mocks );

    check_status_of_pieces(
        $dl,
        remaining        => [0],
        completed        => [],
        remaining_blocks => { 0 => [ { offset => 0, size => 10 } ], },
        label            => "$label, pre-write",
    );

    ok( $dl->write_block( piece => 0, offset => 0, data_ref => \$data ),
        "$label, write a block" );

    check_status_of_pieces(
        $dl,
        remaining        => [0],
        completed        => [],
        remaining_blocks => { 0 => [ { offset => 9, size => 1 } ], },
        label            => "$label, after first write",
    );

    ok(
        $dl->write_block(
            piece    => 0,
            offset   => $file_size - 2,
            data_ref => \$more_data,
        ),
        "$label, write another block"
    );

    check_status_of_pieces(
        $dl,
        remaining        => [],
        completed        => [0],
        remaining_blocks => { 0 => [], },
        label            => "$label, after the second write",
    );

    my $data_from_file = read_file($file_name);
    is(
        $data_from_file,
        $data . $more_data,
        "$label, everything wrote appropriately"
    );

    remove '*.piece';
    remove '*.delete*';
}

MORE_THAN_ONE_PIECE_AND_FILE: {
    my $label     = 'more than one piece and file';
    my $file_name = random_string('ccccc') . '.delete';

    my $data = random_string( '.' x 14 );

    my %mocks = (
        'get_torrent_file_name'     => sub { $file_name . '.torrent' },
        'multiple_files_exist'      => sub { 1 },
        'get_suggested_file_name'   => sub { $file_name },
        'get_standard_piece_length' => sub { 10 },
        'get_total_piece_count'     => sub { 2 },
        'get_total_download_size'   => sub {
            do { use bytes; length($data) }
        },
        'get_whole_piece_count'          => sub { 1 },
        'final_partial_piece_exists'     => sub { 1 },
        'get_final_partial_piece_length' => sub { 4 },
        'get_tracker' => sub { 'http://my.tracker:6969/announce' },
        'get_files'   => sub {
            [
                {
                    'length' => 8,
                    'path'   => File::Spec->join( $file_name, 'one.txt' ),
                },
                {
                    'length' => 6,
                    'path'   => File::Spec->join( $file_name, 'two.txt' ),
                },
            ];
        },
        'get_pieces_array' => sub {
            [ sha1( substr( $data, 0, 10 ) ), sha1( substr( $data, 10, 4 ) ) ];
        },
    );

    my $dl = setup_new_dl_object( \%mocks );

    check_status_of_pieces(
        $dl,
        remaining        => [ 0, 1 ],
        completed        => [],
        remaining_blocks => {
            0 => [ { offset => 0, size => 10 } ],
            1 => [ { offset => 0, size => 4 } ],
        },
        label => "$label, pre-write",
    );

    my $first_block = substr( $data, 0, 4 );
    ok(
        $dl->write_block( piece => 0, offset => 0, data_ref => \$first_block ),
        "$label, write the first block"
    );

    check_status_of_pieces(
        $dl,
        remaining        => [ 0, 1 ],
        completed        => [],
        remaining_blocks => {
            0 => [ { offset => 4, size => 6 } ],
            1 => [ { offset => 0, size => 4 } ],
        },
        label => "$label, first write",
    );

    my $second_block = substr( $data, 10, 4 );
    ok(
        $dl->write_block( piece => 1, offset => 0, data_ref => \$second_block ),
        "$label, write the second block"
    );

    check_status_of_pieces(
        $dl,
        remaining        => [0],
        completed        => [1],
        remaining_blocks => { 0 => [ { offset => 4, size => 6 } ], 1 => [], },
        label            => "$label, second write",
    );

    my $third_block = substr( $data, 4, 6 );
    ok(
        $dl->write_block( piece => 0, offset => 4, data_ref => \$third_block ),
        "$label, write the third block"
    );

    check_status_of_pieces(
        $dl,
        remaining        => [],
        completed        => [ 1, 0 ],
        remaining_blocks => { 0 => [], 1 => [], },
        label            => "$label, after third write",
    );

    {
        my $data_from_file =
          read_file( File::Spec->join( $file_name, 'one.txt' ) );
        is(
            $data_from_file,
            substr( $data, 0, 8 ),
            "$label, everything wrote appropriately"
        );
    }

    {
        my $data_from_file =
          read_file( File::Spec->join( $file_name, 'two.txt' ) );
        is(
            $data_from_file,
            substr( $data, 8, 6 ),
            "$label, everything wrote appropriately"
        );
    }

    remove \1, '*.piece';
    remove \1, '*.delete*';
}

PICK_UP_ON_A_PARTIAL_DOWNLOAD: {
    my $label     = 'pick up on a partial download';
    my $file_name = random_string('ccccc') . '.delete';

    my $data = random_string( '.' x 50 );

    my %mocks = (
        'get_torrent_file_name'     => sub { $file_name . '.torrent' },
        'multiple_files_exist'      => sub { 0 },
        'get_suggested_file_name'   => sub { $file_name },
        'get_standard_piece_length' => sub { 10 },
        'get_total_piece_count'     => sub { 5 },
        'get_total_download_size'   => sub {
            do { use bytes; length($data) }
        },
        'get_whole_piece_count'          => sub { 5 },
        'final_partial_piece_exists'     => sub { 0 },
        'get_final_partial_piece_length' => sub { undef },
        'get_tracker' => sub { 'http://my.tracker:6969/announce' },
        'get_files'   => sub {
            [
                {
                    'length' => 50,
                    'path'   => $file_name,
                },
            ];
        },
        'get_pieces_array' => sub {
            [
                sha1( substr( $data, 0,  10 ) ),
                sha1( substr( $data, 10, 10 ) ),
                sha1( substr( $data, 20, 10 ) ),
                sha1( substr( $data, 30, 10 ) ),
                sha1( substr( $data, 40, 10 ) ),
            ];
        },
    );

    # write out a few completed pieces and a partial piece
    for my $piece (
        (
            [ 0 => substr( $data, 0,  10 ) ],
            [ 2 => substr( $data, 20, 10 ) ],
            [ 4 => substr( $data, 40, 2 ) ],
        )
      )
    {
        my $file_name = $piece->[0] . '.piece';
        my $fh = IO::File->new( $file_name, O_WRONLY | O_CREAT ) or die $!;
        binmode $fh;
        print {$fh} $piece->[1];
        $fh->close();
    }

    my $dl = setup_new_dl_object( \%mocks );

    check_status_of_pieces(
        $dl,
        remaining        => [ 1, 3, 4 ],
        completed        => [ 0, 2 ],
        remaining_blocks => {
            1 => [ { offset => 0, size => 10 } ],
            3 => [ { offset => 0, size => 10 } ],
            4 => [ { offset => 0, size => 10 } ],
        },
        label => "$label, pre-write",
    );

    my $first_block = substr( $data, 10, 10 );
    ok(
        $dl->write_block( piece => 1, offset => 0, data_ref => \$first_block ),
        "$label, write the first block"
    );

    check_status_of_pieces(
        $dl,
        remaining => [ 3, 4 ],
        completed => [ 0, 1, 2 ],
        remaining_blocks => {
            3 => [ { offset => 0, size => 10 } ],
            4 => [ { offset => 0, size => 10 } ],
        },
        label => "$label, first write",
    );

    my $second_block = substr( $data, 40, 10 );
    ok(
        $dl->write_block( piece => 4, offset => 0, data_ref => \$second_block ),
        "$label, write the second block"
    );

    check_status_of_pieces(
        $dl,
        remaining        => [3],
        completed        => [ 0, 1, 2, 4 ],
        remaining_blocks => { 3 => [ { offset => 0, size => 10 } ], },
        label            => "$label, second write",
    );

    my $third_block = substr( $data, 30, 10 );
    ok(
        $dl->write_block( piece => 3, offset => 0, data_ref => \$third_block ),
        "$label, write the third block"
    );

    check_status_of_pieces(
        $dl,
        remaining        => [],
        completed        => [ 0, 1, 2, 3, 4 ],
        remaining_blocks => {},
        label            => "$label, after third write",
    );

    my $data_from_file = read_file($file_name);
    is( $data_from_file, $data, "$label, everything wrote appropriately" );

    remove \1, '*.piece';
    remove \1, '*.delete*';
}

