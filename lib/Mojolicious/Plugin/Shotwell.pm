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
L<Shotwell|http://www.yorba.org/projects/shotwell> database:

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
use constant DEBUG => $ENV{MOJO_SHOTWELL_DEBUG} ? 1 : 0;

our $VERSION = 0.01;
our %SST;

{
  my($sst, $k);
  while(<DATA>) {
    if(/^---\s(\w+)/) {
      $SST{$k} = $sst if $k and $sst;
      $k = $1;
      $sst = '';
    }
    elsif($k and /\w/) {
      $sst .= $_;
    }
  }
}

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

=head2 paths

Holds a hash ref with route mappings. Default is:

  events => '/'
  event  => '/event/:id/:name'
  tags   => '/tags'
  tag    => '/tag/:name'
  raw    => '/raw/:id/*basename'
  show   => '/show/:id/*basename'
  thumb  => '/thumb/:id/*basename'

Any of the above routes can be overridden by passing on paths to L</register>,
but remember that the placeholders are required in the L</ACTIONS>. Example:

  $self->register(
    $app,
    {
      paths => {
        events => '/events',
        ...
      },
    },
  );

=cut

has paths => sub {
  +{
    events => '/',
    event => '/event/:id/:name',
    tags => '/tags',
    tag => '/tag/:name',
    raw => '/raw/:id/*basename',
    show => '/show/:id/*basename',
    thumb => '/thumb/:id/*basename',
  };
};

=head1 ACTIONS

=head2 events

Render data from EventTable. Data is rendered as JSON or defaults to a
template by the name "templates/shotwell/events.html.ep".

JSON data:

  [
    {
      id => $int,
      name => $str,
      time_created => $epoch,
      url => $shotwell_event_url,
    },
    ...
  ]

The JSON data is also available in the template as C<$events>.

=cut

sub events {
  my($self, $c) = @_;
  my $sth = $self->_sth($c, 'events');
  my @events;

  while(my $event = $sth->fetchrow_hashref('NAME_lc')) {
    push @events, {
      id => int $event->{id},
      name => Mojo::Util::decode('UTF-8', $event->{name}),
      time_created => $event->{time_created},
      url => $c->url_for(
              'shotwell/event' => (
                id => $event->{id},
                format => $c->stash('format'),
                name => $event->{name} =~ s/\W//gr, # /
              )
             ),
    };
  }

  $c->respond_to(
    json => sub { shift->render(json => \@events) },
    any => sub { shift->render(events => \@events); }
  );
}

=head2 event

Render photos from PhotoTable, by a given event id. Data is rendered as JSON
or defaults to a template by the name "templates/shotwell/event.html.ep".

JSON data:

  [
    {
      id => $int,
      size => $int,
      title => $str,
      raw => $shotwell_raw_url,
      thumb => $shotwell_thumb_url,
      url => $shotwell_show_url,
    },
    ...
  ]

The JSON data is also available in the template as C<$photos>.
 
=cut

sub event {
  my($self, $c) = @_;
  my $sth = $self->_sth($c, event => $c->stash('id'));
  my $row = $sth->fetchrow_hashref or return $c->render_not_found;

  $c->stash(name => Mojo::Util::decode('UTF-8', $row->{name}));
  $self->_photos($c, photos_by_event_id => $c->stash('id'));
}

=head2 tags

Render data from TagTable. Data is rendered as JSON or defaults to a template
by the name "templates/shotwell/tags.html.ep".

JSON data:

  [
    {
      name => $str,
      url => $shotwell_tag_url,
    },
    ...
  ]

The JSON data is also available in the template as C<$tags>.

=cut

sub tags {
  my($self, $c) = @_;
  my $sth = $self->_sth($c, 'tags');
  my @tags;

  while(my $tag = $sth->fetchrow_hashref) {
    my $name = Mojo::Util::decode('UTF-8', $tag->{name});
    push @tags, {
      name => $name,
      url => $c->url_for('shotwell/tag' => name => $name, format => $c->stash('format')),
    };
  }

  $c->respond_to(
    json => sub { shift->render(json => \@tags) },
    any => sub { shift->render(tags => \@tags) },
  );
}

=head2 tag

Render photos from PhotoTable, by a given tag name. Data is rendered as JSON
or defaults to a template by the name "templates/shotwell/tag.html.ep".

The JSON data is the same as for L</event>.

=cut

sub tag {
  my($self, $c) = @_;
  my $sth = $self->_sth($c, photo_id_list_by_tag_name => $c->stash('name'));
  my $row = $sth->fetchrow_hashref or return $c->render_not_found;
  my @ids = map { s/thumb0*//; hex } split /,/, $row->{photo_id_list} || '';

  $self->_photos(
    $c,
    sprintf($SST{photos_by_ids}, join ',', map { '?' } @ids),
    @ids,
  );
}

=head2 raw

Render raw photo.

=cut

sub raw {
  my($self, $c) = @_;
  my $photo = $self->_photo($c) or return;
  my $static = Mojolicious::Static->new(paths => [dirname $photo->{filename}]);

  # TODO: Render a resized photo and not original photo

  return $c->rendered if $static->serve($c, basename $photo->{filename});
  return $c->render_exception('Unable to serve file');
}

=head2 show

Render a template with an photo inside. The name of the template is
"templates/shotwell/show.html.ep".

The stash data is the same as one element described for L</event> JSON data.

=cut

sub show {
  my($self, $c) = @_;
  my $photo = $self->_photo($c) or return;

  $c->render(
    size => $photo->{filesize} || 0,
    title => Mojo::Util::decode('UTF-8', $photo->{title} || $c->stash('basename')),
    raw => $c->url_for('shotwell/raw'),
    thumb => $c->url_for('shotwell/thumb'),
    url => $c->url_for('shotwell/show'),
  );
}

=head2 thumb

Render photo as a thumbnail.

=cut

sub thumb {
  my($self, $c) = @_;
  my $photo = $self->_photo($c) or return;
  my $static = Mojolicious::Static->new(paths => [dirname $photo->{filename}]);

  # TODO: Render the actual thumb and not original photo

  return $c->rendered if $static->serve($c, basename $photo->{filename});
  return $c->render_exception('Unable to serve file');
}

sub _photo {
  my($self, $c) = @_;
  my $sth = $self->_sth($c, photo_by_id => $c->stash('id'));
  my $photo = $sth->fetchrow_hashref;
  my $basename;

  if(!$photo) {
    $c->render_not_found;
    return;
  }

  $photo->{filename} ||= '';
  $basename = basename $photo->{filename};

  if($c->stash('basename') ne $basename) {
    $c->render_exception("Invalid basename: $basename");
    return;
  }

  return $photo;
}

sub _photos {
  my($self, $c, @sth) = @_;
  my $sth = $self->_sth($c, @sth);
  my @photos;

  while(my $photo = $sth->fetchrow_hashref('NAME_lc')) {
    my $basename = basename $photo->{filename};
    push @photos, {
      id => int $photo->{id},
      size => int $photo->{filesize} || 0,
      title => Mojo::Util::decode('UTF-8', $photo->{title} || $basename),
      raw => $c->url_for('shotwell/raw' => id => $photo->{id}, basename => $basename),
      thumb => $c->url_for('shotwell/thumb' => id => $photo->{id}, basename => $basename),
      url => $c->url_for('shotwell/show' => id => $photo->{id}, basename => $basename),
    };
  }

  $c->respond_to(
    json => sub { shift->render(json => \@photos) },
    any => sub { shift->render(photos => \@photos) },
  );
}

sub _sth {
  my($self, $c, $key, @bind) = @_;
  my $dbh = $c->stash->{'shotwell.dbh'} ||= DBI->connect($self->dsn);
  my $sth;

  warn "[SHOTWELL:DBI] @{[$SST{$key} || $key]}(@bind)\n---\n" if DEBUG;

  $sth = $dbh->prepare($SST{$key} || $key) or die $dbh->errstr;
  $sth->execute(@bind) or die $sth->errstr;
  $sth;
}

=head1 METHODS

=head2 register

  $self->register($app, \%config);

Set L</ATTRIBUTES> and register L</ACTIONS> in the L<Mojolicious> application.

=cut

sub register {
  my($self, $app, $config) = @_;
  my $paths = $self->paths;
  my $route = $config->{route} || $app->routes;

  if($config->{dbname}) {
    $self->dsn("dbi:SQLite:dbname=$config->{dbname}");
  }
  elsif($config->{dsn}) {
    $self->dsn($config->{dsn});
  }

  for my $k (keys %$paths) {
    $paths->{$k} = $config->{paths}{$k} if $config->{paths}{$k};
  }

  for my $k (sort { length $paths->{$b} <=> length $paths->{$a} } keys %$paths) {
    $route->get($paths->{$k})->to(cb => sub { $self->$k(@_); })->name("shotwell/$k");
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

__DATA__
--- event
SELECT name FROM EventTable WHERE id = ?

--- events
SELECT id, name, time_created
FROM EventTable
WHERE name <> ''
ORDER BY time_created DESC

--- photos_by_event_id
SELECT id, filename, filesize, title
FROM PhotoTable
WHERE event_id = ?
ORDER BY timestamp

--- tags
SELECT name
FROM TagTable
ORDER BY name

--- photo_id_list_by_tag_name
SELECT photo_id_list
FROM TagTable
WHERE name = ?

--- photos_by_ids
SELECT id, filename, filesize, title
FROM PhotoTable
WHERE id IN (%s)
ORDER BY timestamp

--- photo_by_id
SELECT filename, filesize, title
FROM PhotoTable
WHERE id = ?

--- END
