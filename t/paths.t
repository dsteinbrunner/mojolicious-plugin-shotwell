use warnings;
use strict;
use Test::More;
use Test::Mojo;

use Mojolicious::Lite;

my $dbname = 't/data/photo.db';
plan skip_all => 'Cannot read t/data/photo.db' unless -r 't/data/photo.db';

{
  plugin shotwell => {
    dbname => $dbname,
    paths => {
      events => '/event-list',
      event => '/by-event/:id/:name',
      tags => '/tag-list',
      tag => '/by-tag/:name',
      raw => '/raw-photo/:id/*basename',
      show => '/show-photo/:id/*basename',
      thumb => '/render-thumb/:id/*basename',
    },
  };
}

my $t = Test::Mojo->new;

$t->get_ok('/event-list.json')
  ->status_is(200)
  ->json_is('/0/id', 24)
  ->json_is('/0/name', 'Some-Event')
  ->json_is('/0/time_created', 1373277232)
  ->json_is('/0/url', '/by-event/24/SomeEvent.json')
  ;

$t->get_ok('/event-list')
  ->status_is(200)
  ->element_exists('ul > li[id="24"]')
  ->element_exists('ul > li[id="24"] a[href="/by-event/24/SomeEvent"]')
  ->text_is('ul > li[id="24"] a[href="/by-event/24/SomeEvent"]', 'Some-Event')
  ->text_is('ul > li[id="24"] small', 'Mon Jul 8 11:53:52 2013')
  ;

$t->get_ok('/by-event/24/Some-event.json')
  ->status_is(200)
  ->json_is('/0/id', 3)
  ->json_is('/0/size', 123)
  ->json_is('/0/title', 'Yay!')
  ->json_is('/0/raw', '/raw-photo/3/IMG_01.jpg')
  ->json_is('/0/thumb', '/render-thumb/3/IMG_01.jpg')
  ->json_is('/0/url', '/show-photo/3/IMG_01.jpg')
  ;

$t->get_ok('/by-event/24/Some-event')
  ->status_is(200)
  ->element_exists('ul > li[id="3"]')
  ->element_exists('ul > li[id="3"] img[src="/render-thumb/3/IMG_01.jpg"]')
  ->element_exists('ul > li[id="3"] img[alt="Yay!"]')
  ->element_exists('ul > li[id="3"] img[title]')
  ->element_exists('ul > li[id="3"] a[href="/show-photo/3/IMG_01.jpg"]')
  ->element_exists('ul > li[id="3"] a[href="/raw-photo/3/IMG_01.jpg"]')
  ->element_exists('ul > li[id="3"] a[href="/raw-photo/3/IMG_01.jpg?download=1"]')
  ;

$t->get_ok('/tag-list.json')
  ->status_is(200)
  ->json_is('/0/name', 'Some-Tag')
  ->json_is('/0/url', '/by-tag/Some-Tag.json')
  ;

$t->get_ok('/tag-list')
  ->status_is(200)
  ->element_exists('ul > li[id="Some-Tag"]')
  ->element_exists('ul > li[id="Some-Tag"] a[href="/by-tag/Some-Tag"]')
  ;

$t->get_ok('/by-tag/Some-Tag.json')
  ->status_is(200)
  ->json_is('/0/id', 3)
  ->json_is('/0/size', 123)
  ->json_is('/0/title', 'Yay!')
  ->json_is('/0/raw', '/raw-photo/3/IMG_01.jpg')
  ->json_is('/0/thumb', '/render-thumb/3/IMG_01.jpg')
  ->json_is('/0/url', '/show-photo/3/IMG_01.jpg')
  ;

$t->get_ok('/by-tag/Some-Tag')
  ->status_is(200)
  ->element_exists('ul > li[id="3"]')
  ->element_exists('ul > li[id="3"] img[src="/render-thumb/3/IMG_01.jpg"]')
  ->element_exists('ul > li[id="3"] img[alt="Yay!"]')
  ->element_exists('ul > li[id="3"] img[title]')
  ->element_exists('ul > li[id="3"] a[href="/show-photo/3/IMG_01.jpg"]')
  ->element_exists('ul > li[id="3"] a[href="/raw-photo/3/IMG_01.jpg"]')
  ->element_exists('ul > li[id="3"] a[href="/raw-photo/3/IMG_01.jpg?download=1"]')
  ;

unlink '/tmp/shotwell/8ae91b49559136753575ca0c50b2126c-1024x0';
$t->get_ok('/raw-photo/2/IMG_11.jpg')->status_is(404);
$t->get_ok('/raw-photo/3/IMG_11.jpg')->status_is(500);
$t->get_ok('/raw-photo/3/IMG_01.jpg')->status_is(200);

ok !-e '/tmp/shotwell/8ae91b49559136753575ca0c50b2126c-1024x0', 'scaled image is not created';
$t->get_ok('/raw-photo/3/IMG_01.jpg?download=1')
  ->status_is(200)
  ->header_like('Content-Length', qr{^\d{3}$})
  ->header_is('Content-Disposition', 'attachment; filename="IMG_01.jpg"');

ok !-e '/tmp/shotwell/8ae91b49559136753575ca0c50b2126c-1024x0', 'scaled image is not created';
$t->get_ok('/raw-photo/3/IMG_01.jpg?download=1&inline=1')
  ->status_is(200)
  ->header_like('Content-Length', qr{^\d{5}$})
  ->header_is('Content-Disposition', 'attachment; filename="IMG_01.jpg"');

ok -e '/tmp/shotwell/8ae91b49559136753575ca0c50b2126c-1024x0', 'scaled image is created';

unlink '/tmp/shotwell/8ae91b49559136753575ca0c50b2126c-100x100';
$t->get_ok('/render-thumb/2/IMG_01.jpg')->status_is(404);
$t->get_ok('/render-thumb/3/IMG_11.jpg')->status_is(500);
$t->get_ok('/render-thumb/3/IMG_01.jpg')->status_is(200);
ok -s '/tmp/shotwell/8ae91b49559136753575ca0c50b2126c-100x100' > 1000, 'thumbnail was generated';

$t->get_ok('/show-photo/3/IMG_01.jpg')
  ->status_is(200)
  ->element_exists('a[href="/raw-photo/3/IMG_01.jpg"]')
  ->element_exists('img[src="/raw-photo/3/IMG_01.jpg?inline=1"]')
  ->text_like('b', qr{Yay!, \d+})
  ;

done_testing;
