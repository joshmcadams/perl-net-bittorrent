use warnings;
use strict;
use Test::More qw(no_plan);
use Test::MockObject;
use String::Random qw(random_string);
use File::Slurp;
use Digest::SHA1 qw(sha1);

use_ok('Net::BitTorrent::File::Downloaded');

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
    is_deeply( $dl->get_remaining_piece_list,
        $args{remaining}, 'remaining piece list' );
    is_deeply( $dl->get_completed_piece_list,
        $args{completed}, 'completed piece list' );
    for my $piece ( keys %{ $args{remaining_blocks} } ) {
        is_deeply(
            $dl->get_remaining_blocks_list_for_piece($piece),
            $args{remaining_blocks}{$piece},
            'remaining blocks for first piece'
        );
    }
}

ONE_PIECE_IN_ONE_BLOCK: {
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
        remaining_blocks => { 0 => [ { offset => 0, size => 10 } ], }
    );

    ok( $dl->write_block( piece => 0, offset => 0, data_ref => \$data ),
        'write a block' );

    my $data_from_file = read_file($file_name);
    is( $data_from_file, $data, 'everything wrote appropriately' );

    check_status_of_pieces(
        $dl,
        remaining        => [],
        completed        => [0],
        remaining_blocks => { 0 => [], }
    );

    unlink $file_name;
}

ONE_PIECE_WITH_TWO_BLOCKS: {
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

    my $d = setup_new_dl_object( \%mocks );

    check_status_of_pieces(
        $d,
        remaining        => [0],
        completed        => [],
        remaining_blocks => { 0 => [ { offset => 0, size => 10 } ], }
    );

    ok( $d->write_block( piece => 0, offset => 0, data_ref => \$data ),
        'write a block' );

    check_status_of_pieces(
        $d,
        remaining        => [0],
        completed        => [],
        remaining_blocks => { 0 => [ { offset => 9, size => 1 } ], }
    );

    ok(
        $d->write_block(
            piece    => 0,
            offset   => $file_size - 2,
            data_ref => \$more_data,
        ),
        'write another block'
    );

    check_status_of_pieces(
        $d,
        remaining        => [],
        completed        => [0],
        remaining_blocks => { 0 => [], }
    );

    my $data_from_file = read_file($file_name);
    is( $data_from_file, $data . $more_data, 'everything wrote appropriately' );

    unlink $file_name;
}

