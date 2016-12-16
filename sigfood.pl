use vars qw($VERSION %IRSSI);
use strict;
use warnings;

use Irssi;
use utf8;
use Time::Local;
use LWP::Simple;
use XML::Simple;
use Data::Dumper;
use HTML::Entities;

$VERSION = '0.1';
%IRSSI = (
	authors     => 'Andreas (llandon) Schwarz',
	name        => 'sigfood',
	description => 'sigfood frontend');

Irssi::signal_add("message public", \&sigfood);
my @timer = undef; # timer-tags
my $count = 0;

sub sigfood {
	my ($server, $data, $hunter, $mask, $chan) = @_;
	my @l_arr = split(/ /,$data);
	my $url   = 'http://www.sigfood.de/?do=api.gettagesplan';
	my $help  = '!sf [YYYY-MM-DD|(+|-)[0..7]] # powered by sigfood.de'; 

#	if(	($chan eq '#hawo') or 
#		($chan eq '#leatestroom') or
#		($chan eq '#hawo-dvb')
#	) { # only there
		if( lc($l_arr[0]) eq '!sigfood' || lc($l_arr[0]) eq '!sf' ) {
			if( defined($l_arr[1]) ) {
				if( $l_arr[1] =~ /^(\d{4})\D?(0[1-9]|1[0-2])\D?([12]\d|0[1-9]|3[01])$/ ) {   # date
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
				$xml = new XML::Simple;
				$data = $xml->XMLin($page);
			};
			if ($@){
				sendmsg($server, $chan, "EPROCFAIL");
				return 1;
			}

			my $hg; my $bl; 
			my $hg_bew; my $bl_bew; 
			my $hg_bew_count; my $bl_bew_count;
			my $cost_bed; my $cost_stud;

			my @array = $data->{Tagesmenue}->{Mensaessen};
			my $outstr;

			foreach my $gericht (@{$data->{Tagesmenue}->{Mensaessen}}) { 
				my $hgref = $gericht->{hauptgericht};
				my $blref = $gericht->{beilage};

				$hg           = $hgref->{bezeichnung};
				$hg_bew       = $hgref->{bewertung}->{schnitt};
				$hg_bew_count = $hgref->{bewertung}->{anzahl};

				$bl           = $blref->{bezeichnung};
				$bl_bew       = $blref->{bewertung}->{schnitt};
				$bl_bew_count = $blref->{bewertung}->{anzahl};

				$cost_stud    = $gericht->{preisstud};
				$cost_bed     = $gericht->{preisbed};

				if(defined $hg) {
					decode_entities($hg);
				}

				if(defined $bl) {
					decode_entities($bl);
				}

				$outstr  = "$hg"                        if defined $hg;
				$outstr .= " [$hg_bew★/#$hg_bew_count]" if defined $hg_bew;
				$outstr .= " mit $bl"                   if defined $bl_bew;
				$outstr .= " [$bl_bew★/#$bl_bew_count]" if defined $bl;
				$outstr .= " (" . $cost_stud/100 . "€/" .
				           $cost_bed/100 . "€)"         if (defined $cost_stud && defined $cost_bed);
				sendmsg($server, $chan, $outstr);
			}
			sendmsg($server, $chan, "ENODATA") if !defined $outstr;
		}
#	}
	return;
}
sub sendmsg {
	my $server = shift;
	my $chan = shift;
	my $msg = shift;
	$server->command("msg $chan $msg");
	return;
}
