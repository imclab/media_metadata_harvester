#!/usr/bin/perl -w

use Feed::Find;
use Data::Dumper;
use Encode;
use LWP::UserAgent;
use XML::LibXML;
use Carp;
#use XML::LibXML::Enhanced;

use DBIx::Simple;

use List::MoreUtils qw{
  any all none notall true false
  firstidx first_index lastidx last_index
  insert_after insert_after_string
  apply indexes
  after after_incl before before_incl
  firstval first_value lastval last_value
  each_array each_arrayref
  pairwise natatime
  mesh zip uniq  minmax part
};

use 5.10.0;

use strict;
use warnings;
use warnings::unused;

my $channel_author_counts = {};

sub _get_text_value_of_xpath_query
{
    my ( $xc, $query ) = @_;

    my @nodes = $xc->findnodes( $query );

    #say Dumper( [ @nodes ] );
    my $node = pop @nodes;

    return $node->textContent();
}

sub _get_attribute_value_of_xpath_query
{
    my ( $xc, $query, $attribute ) = @_;

    my @nodes = $xc->findnodes( $query );

    #say Dumper( [ @nodes ] );
    my $node = pop @nodes;

    #say STDERR '_get_attribute_value_of_xpath_query';
    #say STDERR $attribute;
    #say STDERR $node->toStringC14N();

    return $node->getAttribute( $attribute );
}

sub _get_attribute_value_of_xpath_query_if_exists
{
    my ( $xc, $query, $attribute ) = @_;

    my @nodes = $xc->findnodes( $query );

    #say Dumper( [ @nodes ] );
    my $node = pop @nodes;

    if ( ! defined( $node ) )
    {
       return;
    }

    return _get_attribute_value_of_xpath_query ( $xc, $query, $attribute );
}

sub _get_data_hash_from_youtube_video_entry
{
    my ( $entry ) = @_;

    #say "starting: _get_data_hash_from_youtube_video_entry";

    #say Dumper( $entry );

    my $xc = XML::LibXML::XPathContext->new( $entry );

    $xc->setContextNode( $entry );
    $xc->registerNs( 'a', 'http://www.w3.org/2005/Atom' );

    #say Dumper($entry->toHash( 1) );

    my $id =  $entry->getAttribute( 'id' );

    my $full_string = $entry->toStringC14N();

    my $ret = {
        id          => $id,
        full_xml_string => $full_string,
    };

    #say Dumper( $ret );

    #say "ending:_get_data_hash_from_youtube_video_entry";

    return $ret;
}

sub _get_db
{
    my $dbargs = {
        AutoCommit => 1,
        RaiseError => 1,
        PrintError => 1,
    };

    my $dbh = DBIx::Simple->connect( DBI->connect( "dbi:SQLite:dbname=yt.db", "", "", $dbargs ) );

    return $dbh;
}

sub _store_item_in_db
{
    my ( $hash ) = @_;

    #say "storing video in the db";
    my $dbh = _get_db();

    $dbh->insert( 'npr_items_raw', $hash );
}

sub _get_item_db_record
{
    my ( $hash ) = @_;

    my $dbh = _get_db();

    #say "_get_item_db_record: id: " . $hash->{ id };

    my $ret = $dbh->query( 'select * from npr_items_raw where id = ? ', $hash->{ id } )->hash;

    if ( !$ret )
    {
        _store_item_in_db( $hash );
	$ret = $dbh->query( 'select * from npr_items_raw where id = ? ', $hash->{ id } )->hash;
	die unless $ret;
    }

    #say "done _get_item_db_record: id: " . $hash->{ id };
    return $ret;
}

sub npr_api_url
{
    my ( $base_url ) = @_;

    say "npr_api_url '$base_url'";

    confess unless $base_url;

    my $uri = URI->new( $base_url );

    # Create a request
    my $req = HTTP::Request->new( GET => $uri );

    # max size

    my $start_index = 1;

    my $max_results = 50;

    my $num_results;

    {
        say "Requesting'$base_url' : start_index: $start_index max-results: $max_results";

        # Create a request
        my $req = HTTP::Request->new( GET => $uri );

        my $ua = LWP::UserAgent->new;

        # Pass request to the user agent and get a response back
        my $res = $ua->request( $req );

        die unless $res->is_success;

        #say 'URL final = ' . $res->request->uri;
        my $content = $res->content;

        my $dom = XML::LibXML->load_xml( string => $content );

        my $xc = XML::LibXML::XPathContext->new( $dom );

        #'http://a9.com/-/spec/opensearchrss/1.0/

        my @entries = $xc->findnodes( '//list/story' );

	say Dumper([@entries]);

        foreach my $entry ( @entries )
        {

            my $hash = _get_data_hash_from_youtube_video_entry( $entry );

            #say Dumper ( $hash );

            _get_item_db_record( $hash );
        }

    }

    return;
}

sub main
{
    my $key = $ARGV[ 0 ];

    npr_api_url('http://api.npr.org/query?id=1034,1033&apiKey=MDAzNzI2MDAxMDEyNDczMjQ5OTUwODhmZA001');
    npr_api_url('http://api.npr.org/query?id=13&apiKey=MDAzNzI2MDAxMDEyNDczMjQ5OTUwODhmZA001');
}

main();
