package Convert::yEnc;

require 5.005;
use strict;
use warnings;
use vars qw(@ISA $VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS
            $DEBUG $Linelength $Blocksize);
use String::CRC32;
use Carp;

require Exporter;

@ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Convert::yEnc ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
%EXPORT_TAGS = ( 'all' => [ qw(
  yencode ydecode
) ] );

@EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

@EXPORT = qw(

);

$VERSION = '0.03';

$Linelength = 64;  # default, can be changed
$Blocksize  = 200; # input buffer size


# Preloaded methods go here.


my %esc = ( chr(0)  => chr( 0+64), chr(9) => chr(9+64), chr(10) => chr(10+64), chr(13) => chr(13+64),
            chr(27) => chr(27+64), '=' => chr(ord('=')+64), '.' => chr(ord('.')+64) );

my $esc = qr/([@{[join '', keys %esc]}])/;

sub yencode {
  my($dest, $filename, $src, $filelen,
     $part, $lastpart,
     $fulllen, $pend, $partcrc) = @_;

  if($part == 0) {
    # Single part
    print $dest "=ybegin line=$Linelength size=$filelen name=$filename\r\n";
  } else {
    # Multipart
    $pend = 0 unless defined $pend;
    my $pbegin = $pend + 1;
    $pend = $pend + $filelen;

    print $dest "=ybegin part=$part line=$Linelength size=$fulllen name=$filename\r\n";
    print $dest "=ypart begin=$pbegin end=$pend\r\n";
  }

  my $crc     = 0xFFFFFF;
  my $fullcrc = $partcrc || 0xFFFFFF;

  # This will break if '==' is a valid sequence -- Ctrl-ý?
  my $rex = qr/^(.{1,@{[$Linelength - 1]}}(?:[^=]|=.))/s;
  my $line;

  my $text = '';
  my $newtext;
  my $outtext = '';

  while(read($src, $newtext, $Blocksize)) {
    $crc     = crc32($newtext, $crc);
    $fullcrc = crc32($newtext, $fullcrc);

    $newtext =~ tr[\x00-\xd5\xd6-\xff]
                  [\x2a-\xff\x00-\x29];

    $newtext =~ s/$esc/=$esc{$1}/g;

    $text .= $newtext;

    while(length($text) >= $Linelength) {
      $text =~ s/$rex//s and print $dest "$1\r\n";
    }

  }

  print $dest "$text\r\n" if length $text;

  if($part == 0) {
    # single part
    printf $dest "=yend size=%d crc32=%08x \r\n",
                 $filelen, ($crc ^ 0xFFFFFFFF);
  } elsif($part == $lastpart) {
    printf $dest "=yend size=%d part=%d pcrc32=%08x crc32=%08x \r\n",
                 $filelen, $part, ($crc ^ 0xFFFFFFFF), ($fullcrc ^ 0xFFFFFFFF);
  } else {
    # multi-part
    printf $dest "=yend size=%d part=%d pcrc32=%08x \r\n",
                 $filelen, $part, ($crc ^ 0xFFFFFFFF);
  }

  return wantarray ? ($outtext, $pend, $crc) : ($outtext);
}


sub ydecode {
  my($src) = @_;

  my $in_msg = 0;
  my $eof = 0;

  my $numbytes = 0;

  my($part, $pbegin, $pend, $filesize, $filename, $linelen);
  my $crc     = 0xFFFFFFFF;
  my $fullcrc = 0xFFFFFFFF;

  # these are the values read from the =yend line
  my $filecrc;
  my $filefullcrc;
  my $filelen;

  local $/ = "\x0d\x0a";  # read in by CRLF-terminated lines

  while(<$src>) {
    chomp; # remove CRLF

    if(/^=ybegin/ && !$in_msg) {
      $in_msg = 1;

      # extract information from the start line
      if(/part=(\d+)/) {
        $part = $1;
      }

      if(/line=(\d+)/) {
        $linelen = $1;
      } else {
        croak "Line length not found in message";
      }

      if(/size=(\d+)/) {
        $filesize = $1;
      } else {
        croak "File size not found in message";
      }

      if(/name=(.*)/) {
        $filename = $1;

        open DEST, '>$filename' or croak "Can't open '$filename': $!";
      } else {
        croak "Filename not found in message";
      }


      # multipart message?
      if(defined $part) {
        local $_ = <$src>;
        chomp;

        if(!/^=ypart/) {
          croak "Error: part $part does not start with =ypart";
        } else {
          if(/begin=(\d+)/) {
            $pbegin = $1;
          } else {
            croak "missing begin= in part $part";
          }

          if(/end=(\d+)/) {
            $pend = $1;
          } else {
            croak "missing end= in part $part";
          }
        }
      } # multipart message?

      # skip to next line
      next;
    } # =ybegin seen

    # skip to the start of the message.
    next unless $in_msg;

    if(/^=yend/) {
      $eof = 1; # set eof marker

      if(defined $part) {
        # multipart
        my $thispart;

        if(/part=(\d+)/) {
          $thispart = $1;
        } else {
          croak "part= not found in yend line of part $part";
        }

        if($part != $thispart) {
          croak "part= in yend line ($thispart) disagrees with part in start line ($part)";
        }

        if(/pcrc32=([0-9a-fA-F]{8})/) {
          $filecrc = hex $1;

          if($filecrc ^ 0xFFFFFFFF != $crc) {
            croak sprintf "part CRC does not match: %08x calculated vs %08x in file",
                          ($crc ^ 0xFFFFFFFF), $filecrc;
          }
        }
      } # multipart?

      if(/\bcrc32=([0-9a-fA-F]{8})/) {
        $filefullcrc = hex $1;

        if($filefullcrc ^ 0xFFFFFFFF != $fullcrc) {
          croak sprintf "full CRC does not match: %08x calculated vs %08x in file",
                        ($fullcrc ^ 0xFFFFFFFF), $filefullcrc;
        }
      }

      if(/size=(\d+)/) {
        $filesize = $1;

        if($filesize != $numbytes) {
          # TODO!
          croak "filesize $filesize does not equal number of bytes in this part $numbytes";
        }

        # TODO: handle multipart size calculations; check
        # whole size at end of file;
        # search for multipart messages
      }

      last;
    } # =yend line seen?

    # process a normal line

    # de-escape
    s/=(.)/chr((ord($1)+256-64) % 256)/eg;

    # undo the skew
    tr[\x00-\x29\x2a-\xff]
      [\xd6-\xff\x00-\xd5];

    $crc     = crc32($_, $crc);
    $fullcrc = crc32($_, $fullcrc);

    $numbytes += length;

    print DEST;
  } # while <$src>

  # did we exit the loop normally?
  unless($eof) {
    croak "Error: unexpected EOF in message";
  }

  close DEST or die "Can't close '$filename': $!";

  1;
}


# for possible future use
sub ydecode_part {
  1;
}




1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Convert::yEnc - Encode and decode using the yEnc method

=head1 SYNOPSIS

  use Convert::yEnc qw(yencode ydecode);

  # yEncode data
  yencode();

  # yDecode data -- NOTE: not yet implemented!
  ydecode();

=head1 DESCRIPTION

yEnc is an encoding method devised by JE<uuml>rgen Helbing and intended
to be
suitable for sending data via NNTP, where the datapath is nearly
eight-bit-clean but some characters are special. It avoids the overhead
involved with "readable" encodings such as MIME Base64 or uuencoding by
only escaping a small number of bytes, thus resulting in an overhead of
about 1-2% for large files.

=head2 EXPORT

None by default.

The subroutines C<yencode> and C<ydecode> are exported if you ask for
them explicitly.

=head2 yencode

This subroutine enables you to yEncode data so that it is suitable for
sending via NNTP.

=head2 ydecode

This is not yet implemented. When it is, it will enable you to decode
yEncoded data.


=head1 AUTHOR

Philip Newton, E<lt>pne@cpan.orgE<gt>

=head1 BUGS

=over 4

=item *

Decoding is not implemented yet.

=item *

Multipart files are not yet supported

=back

=head1 CAUTION

Beware: this module is still alpha, and especially the interface. The
interface can, and most probably will, change, so check the documentation
when you upgrade.

For example, I'm not sure how best to do data passing into and out of the
function -- mandate passing filehandles? pass in a string and return a
string? use callbacks for reading and/or writing? accept multiple
possibilities?

Also, I'm not sure what the best way to handle multipart files is. Right
now, the caller has to do a fair amount of bookkeeping; I wonder whether
it might be a good idea to provide a subroutine which would keep track of
things like that itself, and perhaps be passed a number of parts to split
into, or a maximum length per part, and deduce the other parameter
automatically and call C<yencode> with the appropriate parameters.

Or maybe encapsulate the whole thing inside a stateful object which
remembers which parts were already written and at what byte offsets?

Decoding multipart messages where some are missing is also likely to be
"interesting".

At the moment, the interface is filehandle-oriented, like the sample C
code it is derived from. Suggestions for improvements are welcome.

=head1 TODO

=over 4

=item *

Implement multi-part files

=item *

Implement ydecoding

=item *

Support different ways of presenting data in and out -- filehandle,
string data, arrayrefs, ...

=item *

What if the string C<=yend> appears in the middle of data on decoding?
Probably need
to do checking on C<$filelen> and/or C<begin=> and C<end=> values.
Checking whether the length of the current line is less than the declared
line length gets us part of the way, but if the last line happens to be
the right length, it doesn't give us any warning. Counting bytes may
be safer.

=item *

Write tests!

=back

=head1 FEEDBACK

If you use this module, I'd appreciate it if you dropped me a note so
I can see whether anyone uses it at all. Also, if you have any suggestions
for improvements (especially if you wish to submit a code patch), feel free
to send me email.

=head1 SEE ALSO

perl(1), L<Convert::UU>.

=cut
