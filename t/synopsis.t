use warnings;
use strict;
use Test::More;
use Test::Mojo;

use Mojolicious::Lite;

plan skip_all => 'HOME is not set' unless $ENV{HOME};
plan skip_all => 'Shotwell database is missing' unless -r "$ENV{HOME}/.local/share/shotwell/data/photo.db";

{
  # allow /shotwell/... resources to be protected by login
  my $route = under '/shotwell' => sub {
    my $c = shift;
    return 1 if $c->session('username');
    $c->render('login');
    return 0;
  };

  plugin shotwell => {
    route => $route,
  };
}

my $t = Test::Mojo->new;

$t->get_ok('/shotwell')->status_is(404);

done_testing;
