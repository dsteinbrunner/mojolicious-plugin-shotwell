use warnings;
use strict;
use Test::More;
use Test::Mojo;

use Mojolicious::Lite;

$ENV{HOME} = 't';
plan skip_all => 'Shotwell database is missing' unless -r "$ENV{HOME}/.local/share/shotwell/data/photo.db";

{
  get '/register' => sub {
    my $c = shift;
    $c->session(username => 'doe')->render(text => 'yay!');
  };

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
$t->get_ok('/register')->status_is(200);
$t->get_ok('/shotwell')->status_is(200);

done_testing;
