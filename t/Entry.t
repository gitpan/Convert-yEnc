# -*- Perl -*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 27;
BEGIN { use_ok('Convert::yEnc::Entry') };

#########################

use strict;
use warnings;

my $undef = new Convert::yEnc::Entry;
is($undef, undef, "new w/bad args");

my $entryS = new Convert::yEnc::Entry { size => 10000 };
isa_ok($entryS, "Convert::yEnc::EntryS", "EntryS creation");
isa_ok($entryS, "Convert::yEnc::Entry" , "EntryS subclasses Entry");

my $entryM = new Convert::yEnc::Entry { size => 10000, part => 1 };
isa_ok($entryM, "Convert::yEnc::EntryM", "EntryM creation");
isa_ok($entryM, "Convert::yEnc::Entry" , "EntryM subclasses Entry");


$entryS = load Convert::yEnc::Entry "10000\t10000";
isa_ok($entryS, "Convert::yEnc::EntryS", "EntryS loading");
isa_ok($entryS, "Convert::yEnc::Entry" , "EntryS subclasses Entry");

$entryM = load Convert::yEnc::Entry "10000\t5000\t1-5" ;
isa_ok($entryM, "Convert::yEnc::EntryM", "EntryM loading");
isa_ok($entryM, "Convert::yEnc::Entry" , "EntryM subclasses Entry");


my($ok, $complete);

$entryS = new Convert::yEnc::Entry { size => 10000 };
$ok = $entryS->yend( { size=>10000 } );
ok($ok, "entryS->yend");

$complete = $entryS->complete;
ok($complete, "entryS complete");

ok(! $entryS->yend  , "entryS->yend out of order");
ok(! $entryS->ybegin, "entryS->ybegin");
ok(! $entryS->ypart , "entryS->ypart" );  

my $save = "$entryS";
is($save, "10000\t10000", "entryS to_string");


$entryM = new Convert::yEnc::Entry { size => 10000, part => 1 };

$ok = $entryM->ybegin;
ok(!$ok, "entryM begin out of order");

$ok = $entryM->ypart({ begin=>1, end=>5000 } );
ok($ok, "entryM->ypart");

$ok = $entryM->yend({ size=>5000, part=>1 } );
ok($ok, "entryM->ypart");

$complete = $entryM->complete;
ok(!$complete, "entryM not complete");


$ok = $entryM->ybegin({ size => 10000, part => 2 } );
ok($ok, "entryM->ybegin");

$ok = $entryM->ypart({ begin=>5001, end=>10000 } );
ok($ok, "entryM->ypart");

$ok = $entryM->yend({ size=>5000, part=>2 } );
ok($ok, "entryM->ypart");

$complete = $entryM->complete;
ok($complete, "entryM complete");

$save = "$entryM";
is($save, "10000\t1-10000\t1-2", "entryM to_string");

ok(! $entryS->ypart , "entryM->ypart out of order");  
ok(! $entryS->yend  , "entryM->yend  out of order");


__END__
