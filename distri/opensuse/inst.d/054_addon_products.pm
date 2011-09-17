#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub is_applicable()
{
  	my $self=shift;
	return $self->SUPER::is_applicable && !$ENV{LIVECD} && $ENV{ADDONURL};
}

sub run()
{
	my $self=shift;
	if(!$ENV{NET}) {
		sendkeyw $cmd{"next"}; # use network
		sendkeyw "alt-o"; # OK DHCP network
	}
	my $repo=0;
	foreach my $url (split(/\+/, $ENV{ADDONURL})) {
		if($repo++) {sendkeyw "alt-a"; } # Add another
		sendkeyw $cmd{"next"}; # Specify URL (default)
		sendautotype($url);
		sendkeyw $cmd{"next"};
		sendkey "alt-i";sendkeyw "alt-t"; # confirm import (trust) key
	}
	$self->take_screenshot;
	sendkeyw $cmd{"next"}; # done
}

1;
