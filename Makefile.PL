use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Convert::yEnc',
    'VERSION_FROM'	=> 'yEnc.pm', # finds $VERSION
    'PREREQ_PM'		=> { String::CRC32 => 1.2 }, # e.g., Module::Name => 1.1
);
