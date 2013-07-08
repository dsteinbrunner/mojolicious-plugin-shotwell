use ExtUtils::MakeMaker;
WriteMakefile(
  NAME => 'Mojolicious-Plugin-Shotwell',
  VERSION_FROM => 'lib/Mojolicious/Plugin/Shotwell.pm',
  AUTHOR => 'Jan Henning Thorsen <jhthorsen@cpan.org>',
  PREREQ_PM => {
    'DBD::SQLite' => 1.37,
    'Image::EXIF' => 2.01,
    'Image::Imlib2' => 2.03,
    'Mojolicious' => '4.00',
  },
  test => {
    TESTS => 't/*.t',
  },
);
