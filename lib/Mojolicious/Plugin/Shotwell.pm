package Mojolicious::Plugin::Shotwell;

=head1 NAME

Mojolicious::Plugin::Shotwell - View photos from Shotwell database

=head1 VERSION

0.02

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

This module can also be tested from command line if you have the defaults set
up:

  $ perl -Mojo -e'plugin "shotwell"; app->start' daemon

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
use Mojo::Util qw/ decode md5_sum /;
use File::Basename qw/ basename dirname /;
use File::Spec::Functions qw/ catdir /;
use DBI;
use Image::EXIF;
use Image::Imlib2;
use constant DEBUG => $ENV{MOJO_SHOTWELL_DEBUG} ? 1 : 0;
use constant DEFAULT_DBI_ATTRS => { RaiseError => 1, PrintError => 0, AutoCommit => 1 };

our $VERSION = '0.02';
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

sub _DUMP {
  my($format, $arg) = @_;
  require Data::Dumper;
  printf "$format\n", Data::Dumper::Dumper($arg);
}

=head1 ATTRIBUTES

=head2 cache_dir

Path to where all the scaled/rotated images gets stored. Defaults to
"/tmp/shotwell". This can be overridden in L</register>:

  $self->register($app, { cache_dir => '/some/path' });

=cut

has cache_dir => sub {
  my $dir = '/tmp/shotwell';
  mkdir $dir;
  return $dir;
};

=head2 dsn

Returns argument for L<DBI/connect>. Default is

  dbi:SQLite:dbname=$HOME/.local/share/shotwell/data/photo.db

C<$HOME> is the C<HOME> environment variable. The default dsn can be
overridden by either giving "dsn" or "dbname" to L</register>. Example:

  $self->register($app, { dbname => $path_to_db_file });

=cut

has dsn => sub {
  my $home = $ENV{HOME} || '';
  "dbi:SQLite:dbname=$home/.local/share/shotwell/data/photo.db";
};

=head2 sizes

The size of the photos generated by L</raw> and L</thumb>. Default is:

  {
    inline => [ 1024, 0 ], # 0 = scale
    thumb => [ 100, 100 ],
  }

This can be overridden in L</register>:

  $self->register($app, { sizes => { thumb => [200, 200], ... } });

=cut

has sizes => sub {
  +{
    inline => [ 1024, 0 ],
    thumb => [ 100, 100 ],
  };
};

has _types => sub { Mojolicious::Types->new };
has _log => sub { Mojo::Log->new };

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
      name => decode('UTF-8', $event->{name}),
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

  $c->stash(name => decode('UTF-8', $row->{name}));
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
    my $name = decode('UTF-8', $tag->{name});
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
  my @ids = map { s/thumb0*//; hex } grep { /^thumb/ } split /,/, $row->{photo_id_list} || '';

  $self->_photos($c, sprintf($SST{photos_by_ids}, join ',', map { '?' } @ids), @ids);
}

=head2 raw

Render raw photo.

=cut

sub raw {
  my($self, $c) = @_;
  my $photo = $self->_photo($c) or return;
  my $file = $photo->{filename};
  my $static;

  if($c->param('download')) {
    my $basename = basename $file;
    $c->res->headers->content_disposition(qq(attachment; filename="$basename"));
  }
  if($c->param('inline')) {
    $file = $self->_scale_photo($photo, $self->sizes->{inline});
  }

  $static = Mojolicious::Static->new(paths => [dirname $file]);

  return $c->rendered if $static->serve($c, basename $file);
  return $c->render_exception("Unable to serve ($file)");
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
    title => decode('UTF-8', $photo->{title} || $c->stash('basename')),
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
  my $file = $self->_scale_photo($photo, $self->sizes->{thumb});
  my $static = Mojolicious::Static->new(paths => [dirname $file]);

  return $c->rendered if $static->serve($c, basename $file);
  return $c->render_exception("Unable to serve ($file)");
}

sub _photo {
  my($self, $c) = @_;
  my $sth = $self->_sth($c, photo_by_id => $c->stash('id'));
  my $photo = $sth->fetchrow_hashref;
  my $basename;

  if(!$photo) {
    warn "[SHOTWELL] Could not find photo by id\n" if DEBUG;
    $c->render_not_found;
    return;
  }

  $photo->{filename} ||= '';
  $basename = basename $photo->{filename};

  if($c->stash('basename') ne $basename) {
    _DUMP 'photo=%s', $photo if DEBUG;
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
      title => decode('UTF-8', $photo->{title} || $basename),
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

sub _more_photo_info {
  my($self, $photo) = @_;

  $photo->{type} and return $photo;
  $photo->{type} = $self->_types->type(lc $1) if $photo->{filename} =~ /\.(\w+)$/;
  $photo->{type} ||= 'unknown';

  if($photo->{type} eq 'image/jpeg') {
    $photo->{info} = Image::EXIF->new($photo->{filename})->get_image_info || {};
    given($photo->{info}{'Image Orientation'} || 0) {
      when(/^.*left.*bottom/i)  { $photo->{orientation} = 3 }
      when(/^.*bottom.*right/i) { $photo->{orientation} = 2 }
      when(/^.*right.*top/i)    { $photo->{orientation} = 1 }
      default                   { $photo->{orientation} = 0 }
    }
  }

  $photo->{height} ||= $photo->{info}{'Image Height'} || 0;
  $photo->{width} ||= $photo->{info}{'Image Width'} || 0;
  _DUMP 'info=%s', $photo if DEBUG;
  $photo;
}

sub _scale_photo {
  my($self, $photo, $size) = @_;
  my $out = sprintf '%s/%s-%sx%s', $self->cache_dir, md5_sum($photo->{filename}), @$size;

  if(-e $out) {
    return $out;
  }

  eval {
    my $img = Image::Imlib2->load($photo->{filename});
    $self->_more_photo_info($photo);
    warn "[SHOTWELL] orientation=$photo->{orientation}\n" if DEBUG;
    $img->image_orientate($photo->{orientation}) if $photo->{orientation};
    warn "[SHOTWELL] create_scaled_image(@$size)\n" if DEBUG;
    $img = $img->create_scaled_image(@$size);
    $img->image_set_format('jpeg');
    $img->save($out);
    1;
  } or do {
    $self->_log->error("[Imlib2] $@");
    $out = $photo->{filename};
  };

  return $out;
}

sub _sth {
  my($self, $c, $key, @bind) = @_;
  my $dbh = $c->stash->{'shotwell.dbh'} ||= DBI->connect(@{ $self->dsn });
  my $sth;

  warn "[SHOTWELL:DBI] @{[$SST{$key} || $key]}(@bind)\n---\n" if DEBUG;

  $sth = $dbh->prepare($SST{$key} || $key);
  $sth->execute(@bind);
  $sth;
}

=head1 METHODS

=head2 register

  $self->register($app, \%config);

Set L</ATTRIBUTES> and register L</ACTIONS> in the L<Mojolicious> application.

=cut

sub register {
  my($self, $app, $config) = @_;
  my $sizes = $self->sizes;

  $self->_log($app->log);
  $self->_types($app->types);
  $self->dsn("dbi:SQLite:dbname=$config->{dbname}") if $config->{dbname};

  unless($config->{skip_bundled_templates}) {
    push @{ $app->renderer->paths }, catdir dirname(__FILE__), 'Shotwell', 'templates';
  }

  for my $k (qw/ dsn cache_dir /) {
    $self->$k($config->{$k}) if $config->{$k};
  }
  for my $k (keys %$sizes) {
    $sizes->{$k} = $config->{sizes}{$k} if $config->{sizes}{$k};
  }

  $self->dsn([ $self->dsn, '', '', DEFAULT_DBI_ATTRS ]) unless ref $self->dsn eq 'ARRAY';
  $self->_register_routes($config->{route} || $app->routes, %{ $config->{paths} || {} });
}

sub _register_routes {
  my($self, $route, %paths) = @_;

  $paths{events} ||= '/';
  $paths{event} ||= '/event/:id/:name';
  $paths{tags} ||= '/tags';
  $paths{tag} ||= '/tag/:name';
  $paths{raw} ||= '/raw/:id/*basename';
  $paths{show} ||= '/show/:id/*basename';
  $paths{thumb} ||= '/thumb/:id/*basename';

  for my $k (sort { length $paths{$b} <=> length $paths{$a} } keys %paths) {
    $route->get($paths{$k})->to(cb => sub { $self->$k(@_); })->name("shotwell/$k");
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
