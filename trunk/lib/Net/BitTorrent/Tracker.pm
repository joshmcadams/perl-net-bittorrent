package Net::BitTorrent::Tracker;

use warnings;
use strict;
use Carp qw(croak);
use Convert::Bencode qw(bdecode);
use LWP::Simple;

sub new {
    my ( $class, %self ) = @_;

    for (qw(tracker info_hash peer_id ip port)) {
        croak("$_ required") unless exists $self{$_};
    }

    bless \%self, $class;

    return \%self;
}

sub get_more_peers {
    my ($self) = @_;

    print STDERR "# [[TRACKER: $self->{tracker}]]\n";
    my $content = get( $self->{tracker} );
    print STDERR "# [[CONTENT: $content]]\n";

    my $response = bdecode($content);

    return $response->{peers};
}

1;
