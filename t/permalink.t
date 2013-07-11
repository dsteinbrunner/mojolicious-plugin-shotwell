use warnings;
use strict;
use Test::More;
use Test::Mojo;

my $dbname = 't/data/photo.db';
plan skip_all => 'Cannot read t/data/photo.db' unless -r 't/data/photo.db';

{
  use Mojolicious::Lite;
  my $protected = app->routes->get('/')->under(sub {
    my $c = shift;
    app->log->debug('Inside under() !!!!');
    return 1 if $c->param('allow_access') or $c->shotwell_access_granted;
    $c->render(text => 'Not allowed!', status => 401);
    return 0;
  });

  plugin shotwell => {
    dbname => $dbname,
    routes => {
      default => $protected,
      permalink => app->routes->get('/:permalink'),
    },
  };
}

my $t = Test::Mojo->new;
my $url;

{
  $t->get_ok('/tags')->status_is(401);
  $t->get_ok('/tags?allow_access=1')->status_is(200, 'allow_access=1 allow access');
  $t->get_ok('/raw/3/IMG_01.jpg')->status_is(401);
  $t->get_ok('/show/3/IMG_01.jpg')->status_is(401);
  $t->get_ok('/thumb/3/IMG_01.jpg')->status_is(401);
}

{
  $t->get_ok('/some-single-permalink')->status_is(200);
  $t->get_ok('/raw/3/IMG_01.jpg')->status_is(200);
  $t->get_ok('/show/3/IMG_01.jpg')->status_is(200);
  $t->get_ok('/thumb/3/IMG_01.jpg')->status_is(200);
  $t->get_ok('/raw/4/IMG_02.jpg')->status_is(401);
  $t->get_ok('/show/4/IMG_02.jpg')->status_is(401);
  $t->get_ok('/thumb/4/IMG_02.jpg')->status_is(401);
}

{
  $t->get_ok('/some-collection-permalink')->status_is(200);
  $t->get_ok('/raw/3/IMG_01.jpg')->status_is(200);
  $t->get_ok('/show/3/IMG_01.jpg')->status_is(200);
  $t->get_ok('/thumb/3/IMG_01.jpg')->status_is(200);
  $t->get_ok('/raw/4/IMG_02.jpg')->status_is(200);
  $t->get_ok('/show/4/IMG_02.jpg')->status_is(200);
  $t->get_ok('/thumb/4/IMG_02.jpg')->status_is(200);
}

{
  my($url, $permalink);
  $t->get_ok('/event/24/WHATEVER?allow_access=1&permalink=1')->status_is(302);
  $url = $t->tx->res->headers->location || '';
  $permalink = $url =~ /(\w+)$/ ? $1 : 'UNKNOWN';
  diag $url;

  $t->get_ok("/$permalink")->status_is(200);
  $t->get_ok('/raw/3/IMG_01.jpg')->status_is(200);
  $t->get_ok('/raw/4/IMG_02.jpg')->status_is(401);

  $t->get_ok("/$permalink/delete.json")->status_is(200);
  $t->get_ok('/raw/3/IMG_01.jpg')->status_is(401);
  $t->get_ok('/raw/4/IMG_02.jpg')->status_is(401);

  $t->get_ok("/$permalink/delete.json?allow_access=1")->status_is(404);
}

{
  my($url, $permalink);
  $t->get_ok('/tag/Some-Tag?allow_access=1&permalink=1')->status_is(302);
  $url = $t->tx->res->headers->location || '';
  $permalink = $url =~ /(\w+)$/ ? $1 : 'UNKNOWN';
  diag $url;

  $t->get_ok("/$permalink")->status_is(200);
  $t->get_ok('/raw/3/IMG_01.jpg')->status_is(200);
  $t->get_ok('/raw/4/IMG_02.jpg')->status_is(401);

  $t->get_ok("/$permalink/delete.json")->status_is(200);
  $t->get_ok('/raw/3/IMG_01.jpg')->status_is(401);
  $t->get_ok('/raw/4/IMG_02.jpg')->status_is(401);

  $t->get_ok("/$permalink/delete.json?allow_access=1")->status_is(404);
}

{
  my($url, $permalink);
  $t->get_ok('/show/4/IMG_02.jpg?allow_access=1&permalink=1')->status_is(302);
  $url = $t->tx->res->headers->location || '';
  $permalink = $url =~ /(\w+)$/ ? $1 : 'UNKNOWN';
  diag $url;

  $t->get_ok("/$permalink")->status_is(200);
  $t->get_ok('/raw/3/IMG_01.jpg')->status_is(401);
  $t->get_ok('/raw/4/IMG_02.jpg')->status_is(200);

  $t->get_ok("/$permalink/delete.json")->status_is(200);
  $t->get_ok('/raw/3/IMG_01.jpg')->status_is(401);
  $t->get_ok('/raw/4/IMG_02.jpg')->status_is(401);

  $t->get_ok("/$permalink/delete.json?allow_access=1")->status_is(404);
}

done_testing;
