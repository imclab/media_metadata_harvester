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

sub look_up_youtube_author_talk
{
    my ( $author, $channel ) = @_;

    my $base_url = "http://gdata.youtube.com/feeds/api/users/$channel/uploads";

    return _youtube_lookup( $base_url );
}

sub look_up_youtube_global
{
    my ( $author ) = @_;

    my $youtube_global_search_api = 'https://gdata.youtube.com/feeds/api/videos';
    return _youtube_lookup( $author, $youtube_global_search_api );
}

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

    my $id = _get_text_value_of_xpath_query( $xc, './/a:id' );

    my $full_string = $entry->toStringC14N();

    #say $full_string;

    my $title = _get_text_value_of_xpath_query( $xc, './a:title' );

    my $description = _get_text_value_of_xpath_query( $xc, './a:content' );

    my $channel = _get_text_value_of_xpath_query( $xc, './a:author/a:name' );

    my $duration_seconds  =  _get_attribute_value_of_xpath_query( $xc, './media:group/yt:duration', 'seconds' );
    my $media_keywords  =  _get_text_value_of_xpath_query( $xc, './media:group/media:keywords' );

    #say $media_keywords;
    #exit;

    my $rating_average = _get_attribute_value_of_xpath_query_if_exists( $xc, './gd:rating', 'average' );
    my $rating_max     = _get_attribute_value_of_xpath_query_if_exists( $xc, './gd:rating', 'max' );
    my $rating_min     = _get_attribute_value_of_xpath_query_if_exists( $xc, './gd:rating', 'min' );

    my $rating_numRaters     = _get_attribute_value_of_xpath_query_if_exists( $xc, './gd:rating', 'numRaters' );

    #say "id------------------------";

    #say $id;

    my $ret = {
        id          => $id,
        full_string => $full_string,
        title       => $title,
        description => $description,
	channel     => $channel,
	duration_seconds   => $duration_seconds,
        keywords        => $media_keywords,
	rating_average => $rating_average,
	rating_max => $rating_max,
	rating_min => $rating_min,
	rating_numRaters => $rating_numRaters,
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

sub _store_video_in_db
{
    my ( $hash ) = @_;

    #say "storing video in the db";
    my $dbh = _get_db();

    $dbh->insert( 'youtube_videos', $hash );
}

sub _get_video_record
{
    my ( $hash ) = @_;

    my $dbh = _get_db();

    #say "_get_video_record: id: " . $hash->{ id };

    my $ret = $dbh->query( 'select * from youtube_videos where id = ? ', $hash->{ id } )->hash;

    if ( !$ret )
    {
        _store_video_in_db( $hash );
	$ret = $dbh->query( 'select * from youtube_videos where id = ? ', $hash->{ id } )->hash;
	die unless $ret;
    }

    #say "done _get_video_record: id: " . $hash->{ id };
    return $ret;
}

sub _youtube_lookup
{
    my ( $base_url ) = @_;

    say "_youtube_lookup '$base_url'";

    confess unless $base_url;

    my $uri = URI->new( $base_url );

    # max size

    my $start_index = 1;

    my $max_results = 50;

    my $num_results;

    do
    {

        say "Requesting'$base_url' : start_index: $start_index max-results: $max_results";

        $uri->query_form( { 'start-index' => $start_index, 'max-results' => $max_results, prettyprint => 'true' } );

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

        my @nodes = $xc->findnodes( '//openSearch:totalResults' );

        $xc->registerNs( 'a', 'http://www.w3.org/2005/Atom' );
        my $totalResults_node = $nodes[ 0 ];

        die unless $totalResults_node;

        $num_results = $totalResults_node->textContent();

        #say "$num_results nodes for author: $author in $channel";

        die unless $num_results;

        my @entries = $xc->findnodes( '//a:entry' );

        foreach my $entry ( @entries )
        {


	    {
	      my  $full_xml_string = $entry->toStringC14N();

	      $xc->setContextNode( $entry );
	      $xc->registerNs( 'a', 'http://www.w3.org/2005/Atom' );

	      #say Dumper($entry->toHash( 1) );

	      my $id = _get_text_value_of_xpath_query( $xc, './/a:id' );

	      my $db = _get_db();

	      my $raw_xml_hash = { id => $id, full_xml_string => $full_xml_string };

	      $db->query(" DELETE FROM youtube_videos_raw_xml where id = ? ", $id);
	      $db->insert( 'youtube_videos_raw_xml', $raw_xml_hash );
	      next; 
	    }

            my $hash = _get_data_hash_from_youtube_video_entry( $entry );

            #say Dumper ( $hash );

            _get_video_record( $hash );
        }

        $start_index += $max_results;
    } while ( $start_index <= $num_results );

    return;
}

sub look_up_ted_talk_author
{
    my ( $author ) = @_;

    return look_up_youtube_author_talk( $author, 'TEDtalksDirector' );
}

sub look_up_berkman
{
    my ( $author ) = @_;

    return look_up_youtube_author_talk( $author, 'BerkmanCenter' );
}

sub look_up_BookTV
{
    my ( $author ) = @_;

    return look_up_youtube_author_talk( $author, 'BookTV' );
}

sub look_up_at_google_talks
{
    my ( $author ) = @_;

    return look_up_youtube_author_talk( $author, 'AtGoogleTalks' );
}

sub get_book_db_record
{
    my ( $title, $author ) = @_;

    my $dbh = _get_db();

    my $results = $dbh->query( " SELECT * from books where author = ? and title = ?  limit 1", $author, $title );

    #say Dumper ( $results );

    my $ret = $results->hashes;

    #say Dumper( $ret );

    #say Dumper( scalar( @$ret ) );

    if ( !scalar( @$ret ) )
    {
        $dbh->query( "INSERT INTO books (author, title) VALUES (?, ? ) ", $author, $title );
        $results = $dbh->query( " SELECT * from books where author = ? and title = ?  limit 1", $author, $title );
    }

    return $results->hash;
}

sub main
{
    my $author = $ARGV[ 0 ];

    my $lines = 0;

    my $authors_found     = 0;
    my $authors_not_found = 0;

    my $dead_authors = 0;
    my $living_authors;


    look_up_at_google_talks(' ' );
    look_up_ted_talk_author();
    look_up_berkman();

    look_up_BookTV();
}

main();
