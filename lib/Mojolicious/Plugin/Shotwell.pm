package Mojolicious::Plugin::Shotwell;

=head1 NAME

Mojolicious::Plugin::Shotwell - View photos from Shotwell database

=head1 VERSION

0.01

=head1 SYNOPSIS

  use Mojolicious::Lite;

  # allow /shotwell/... resources to be protected by login
  my $route = under '/shotwell' => sub {
    my $c = shift;
    return 1 if $c->session('username');
    $c->render('login');
    return 0;
  };

  plugin shotwell => {
    dbname => '/home/username/.local/share/shotwell/data/photo.db',
    route => $route,
  };

  app->start;

=head1 DESCRIPTION

This plugin provides actions which can render data from a 
L<Shotwell|http://www.yorba.org/projects/shotwell> database.

=over 4

=item * Events

See L</events> and L</event>.

=item * Tags

See L</tags> and L</tag>.

=item * Thumbnails

See L</thumb>.

=item * Photos

See L</show> and L</raw>.

=back

=cut

use Mojo::Base 'Mojolicious::Plugin';
use File::Basename;
use DBI;

our $VERSION = 0.01;

=head1 ATTRIBUTES

=head2 dsn

Returns argument for L<DBI/connect>. Default is

  dbi:SQLite:dbname=$HOME/.local/share/shotwell/data/photo.db

C<$HOME> is either the C<SHOTWELL_HOME> or C<HOME> environment variable. The
default attribute can be overridden by either giving "dsn" or "dbname" to
L</register>. Example:

  $self->register($app, { dbname => $path_to_db_file });

=cut

has dsn => sub {
  my $home = $ENV{SHOTWELL_HOME} || $ENV{HOME} || '';
  "dbi:SQLite:dbname=$home/.local/share/shotwell/data/photo.db";
};

=head1 ACTIONS

=head2 events

Render data from EventTable.

=head2 event

Render photos from PhotoTable, by a given event id.

=head2 tags

Render data from TagTable.

=head2 tag

Render photos from PhotoTable, by a given tag name.

=head2 raw

Render image data.

=head2 show

Render a template with an image inside.

=head2 thumb

Render image as a thumb.

=head1 METHODS

=head2 register

  $self->register($app, \%config);

Set L</ATTRIBUTES> and register L</ACTIONS> in the L<Mojolicious> application.

=cut

sub register {
  my($self, $app, $config) = @_;

  $self->_set_attributes($config);
  $self->_register_routes($config->{route} || $app->routes, $config->{paths} || {});
}

sub _dbh {
  $_[1]->stash->{'shotwell.dbh'} ||= DBI->connect($_[0]->dsn);
}

sub _register_routes {
  my($self, $route, $paths) = @_;

  $paths->{events} ||= '/';
  $paths->{event}  ||= '/event/:event_id/:event_name';
  $paths->{tags}   ||= '/tags';
  $paths->{tag}    ||= '/tag/:tag_name';
  $paths->{raw}    ||= '/raw/:id/:basename';
  $paths->{show}   ||= '/show/:id/:basename';
  $paths->{thumb}  ||= '/thumb/:id/:basename';

  for my $k (sort { length $paths->{$b} <=> length $paths->{$a} } keys %$paths) {
    $route->get($paths->{$k})->to(cb => sub { $self->$k(@_); })->name("shotwell_$k");
  }
}

sub _set_attributes {
  my($self, $config) = @_;

  if($config->{dbname}) {
    $self->dsn("dbi:SQLite:dbname=$config->{dbname}");
  }
  elsif($config->{dsn}) {
    $self->dsn($config->{dsn});
  }
}

=head1 DATABASE SCHEME

=head2 EventTable

  id INTEGER PRIMARY KEY,
  name TEXT,
  primary_photo_id INTEGER,
  time_created INTEGER,primary_source_id TEXT,
  comment TEXT

=head2 PhotoTable

  id INTEGER PRIMARY KEY,
  filename TEXT UNIQUE NOT NULL,
  width INTEGER,
  height INTEGER,
  filesize INTEGER,
  timestamp INTEGER,
  exposure_time INTEGER,
  orientation INTEGER,
  original_orientation INTEGER,
  import_id INTEGER,
  event_id INTEGER,
  transformations TEXT,
  md5 TEXT,
  thumbnail_md5 TEXT,
  exif_md5 TEXT,
  time_created INTEGER,
  flags INTEGER DEFAULT 0,
  rating INTEGER DEFAULT 0,
  file_format INTEGER DEFAULT 0,
  title TEXT,
  backlinks TEXT,
  time_reimported INTEGER,
  editable_id INTEGER DEFAULT -1,
  metadata_dirty INTEGER DEFAULT 0,
  developer TEXT,
  develop_shotwell_id INTEGER DEFAULT -1,
  develop_camera_id INTEGER DEFAULT -1,
  develop_embedded_id INTEGER DEFAULT -1,
  comment TEXT

=head2 TagTable

  id INTEGER PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  photo_id_list TEXT,
  time_created INTEGER

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
