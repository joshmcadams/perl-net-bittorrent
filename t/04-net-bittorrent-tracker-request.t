package TestWebServer;

use warnings;
use strict;
use base qw(HTTP::Server::Simple::CGI);

sub respond_with {
    my ($self) = shift;

    push @{ $self->{responses} }, @_;

    return $self;
}

sub set_port {
    my $self = shift;
    $self->port(@_);
    return $self;
}

sub set_host {
    my ($self) = shift;
    $self->host(@_);
    return $self;
}

sub handle_request {
    my ( $self, $cgi ) = @_;

    my $response = shift @{ $self->{responses} };

    die('out of responses') unless defined $response;

    print $response;

    return;
}

package main;

use warnings;
use strict;
use POSIX;
use Test::More qw(no_plan);
use Socket;
use Sys::Hostname;
use Convert::Bencode qw(bencode);

use_ok('Net::BitTorrent::Tracker');

TEST_ONE: {
    my $host = 'localhost';
    my $port = 23456;

    my $tracker = Net::BitTorrent::Tracker->new(
        tracker   => "http://${host}:${port}/track",
        port      => $port,
        info_hash => 'A' x 20,
        peer_id   => 'B' x 20,
        ip => inet_ntoa( scalar gethostbyname( hostname() || 'localhost' ) ),
    );

    isa_ok( $tracker, 'Net::BitTorrent::Tracker' );

    my $peer_list =
      [ { "peer id" => "X" x 20, ip => "192.168.0.1", port => 6681 } ];

    my $pid =
      TestWebServer->new()->set_host($host)->set_port($port)
      ->respond_with( bencode( { interval => 360, peers => $peer_list } ) )
      ->background();

    is_deeply( $tracker->get_more_peers(), $peer_list, 'get a round of peers' );

    kill SIGTERM, $pid;
}

