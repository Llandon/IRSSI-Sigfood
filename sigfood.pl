use vars qw($VERSION %IRSSI);
use strict;
use warnings;
use utf8;

use Irssi;
use Time::Local;
use LWP::Simple;
use XML::Simple;
use Data::Dumper;
use HTML::Entities;

# Copyright (c) 2012-2017, Andreas Schwarz

# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.

# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

$VERSION = '0.2.3';
%IRSSI = (
	authors     => 'Andreas (llandon) Schwarz',
	license     => 'ISC License',
	name        => 'sigfood',
	description => 'sigfood frontend'
);

Irssi::signal_add("message public", \&sigfood);
my $count = 0;

sub sigfood {
	my ($server, $data, $hunter, $mask, $chan) = @_;
	my @l_arr = split(/ /,$data);
	my $url   = 'https://www.sigfood.de/?do=api.gettagesplan';
	my $help  = '!sf [YYYY-MM-DD|(+|-)[0..7]] # powered by sigfood.de';

	if( lc($l_arr[0]) eq '!sigfood' || lc($l_arr[0]) eq '!sf' ) {
		if( defined($l_arr[1]) ) {
 			if( $l_arr[1] =~ /^(\d{4})\D?(0[1-9]|1[0-2])\D?([12]\d|0[1-9]|3[01])$/ ) { # date
				my @date = split(/-/, $l_arr[1]);
				my $year = $date[0]; my $month = $date[1]; my $day = $date[2];
				my $timestamp = eval {
					timelocal(0, 0, 0, $day, $month - 1, $year - 1900);
				};

				if($@) {
					sendmsg($server, $chan, "ungueltiges Datum");
					return 1;
				}

				$url .= "&datum=$l_arr[1]";
			} elsif ( $l_arr[1] =~ /(\+|\-)[0-7]{1}/ ) {
				my $delta = substr($l_arr[1],1,1)*86400; # [s]
				my $ts = time();

				if( substr($l_arr[1],0,1) eq '+') {
					$ts += $delta;
				} else {
					$ts -= $delta;
				}

				my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ts);
				$url .= sprintf("&datum=%d-%02d-%02d", $year+1900, $mon+1, $mday);
			} else {
				sendmsg($server, $chan, $help);
				return 1;
			}
		}

		my $page; my $xml; my $data;

		eval {
			$page = get($url);
			$xml  = new XML::Simple;
			$data = $xml->XMLin($page, NoAttr => 1, ForceArray => [ 'beilage' ]);
		};

		if ($@){
			sendmsg($server, $chan, "EPROCFAIL");
			return 1;
		}

		my ($hg, $bl, $hg_bew, $bl_bew);
		my ($hg_bew_count, $bl_bew_count, $cost_bed, $cost_stud);

		my $day = $data->{Tagesmenue}->{tag} if(defined $data->{Tagesmenue}->{Mensaessen});
		sendmsg($server, $chan, "Speiseplan für den $day") if defined $day;

		my $outstr;
		my @gerichte;

		if (ref($data->{Tagesmenue}->{Mensaessen}) ne 'ARRAY') {
			@gerichte = $data->{Tagesmenue}->{Mensaessen};
		}else{
			@gerichte = @{$data->{Tagesmenue}->{Mensaessen}};
		}

		foreach my $gericht (@gerichte) { # hauptgericht + beilagen
			my $hgref = $gericht->{hauptgericht};
			my $blout = " && (";
			my $i=0;

			foreach my $beilage (@{$gericht->{beilage}}) {
				my $blref = $beilage;

				$bl           = $blref->{bezeichnung};
				$bl_bew       = $blref->{bewertung}->{schnitt};
				$bl_bew_count = $blref->{bewertung}->{anzahl};

				$blout .= " ||" if 0 < $i; # Trennung bei mehreren Beilagen
				$blout .= " " . $bl . " [$bl_bew★/#$bl_bew_count]";
				decode_entities($blout);
				++$i;
			}

			$hg           = $hgref->{bezeichnung};
			$hg_bew       = $hgref->{bewertung}->{schnitt};
			$hg_bew_count = $hgref->{bewertung}->{anzahl};
			$cost_stud    = $gericht->{preisstud};
			$cost_bed     = $gericht->{preisbed};

			if(defined $hg) {
				decode_entities($hg);
			}

			$outstr  = "$hg"                        if defined $hg;
			$outstr .= " [$hg_bew★/#$hg_bew_count]" if defined $hg_bew;
			$outstr .= $blout . " )" if $blout ne " && (";
			$outstr .= " (" . $cost_stud/100 . "€/" .
			           $cost_bed/100 . "€)"         if (defined $cost_stud && defined $cost_bed);
			sendmsg($server, $chan, $outstr);
		}
		sendmsg($server, $chan, "ENODATA") if !defined $outstr;
	}
	return;
}

sub sendmsg {
	my $server = shift;
	my $chan   = shift;
	my $msg    = shift;
	$server->command("msg $chan $msg");
	return;
}

