#!/usr/bin/perl

=head1 NAME

 Servers::mta::postfix - i-MSCP Postfix MTA server implementation

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2014 by internet Multi Server Control Panel
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# @category    i-MSCP
# @copyright   2010-2014 by i-MSCP | http://i-mscp.net
# @author      Daniel Andreca <sci2tech@gmail.com>
# @author      Laurent Declercq <l.declercq@nuxwin.com>
# @link        http://i-mscp.net i-MSCP Home Site
# @license     http://www.gnu.org/licenses/gpl-2.0.html GPL v2

package Servers::mta::postfix;

use strict;
use warnings;

use iMSCP::Debug;
use iMSCP::HooksManager;
use iMSCP::Config;
use iMSCP::Execute;
use iMSCP::File;
use iMSCP::Dir;
use File::Basename;
use parent 'Common::SingletonClass';

=head1 DESCRIPTION

 i-MSCP Postfix MTA server implementation.

=head1 PUBLIC METHODS

=over 4

=item registerSetupHooks(\%hooksManager)

 Register setup hooks

 Return int 0 on success, other on failure

=cut

sub registerSetupHooks
{
	my ($self, $hooksManager) = @_;

	my $rs = $hooksManager->trigger('beforeMtaRegisterSetupHooks', $hooksManager, 'postfix');
	return $rs if $rs;

	$hooksManager->trigger('afterMtaRegisterSetupHooks', $hooksManager, 'postfix');
}

=item preinstall()

 Process preinstall tasks

 Return int 0 on success, other on failure

=cut

sub preinstall
{
	require Servers::mta::postfix::installer;
	Servers::mta::postfix::installer->getInstance()->preinstall();
}

=item install()

 Process install tasks

 Return int 0 on success, other on failure

=cut

sub install
{
	require Servers::mta::postfix::installer;
	Servers::mta::postfix::installer->getInstance()->install();
}

=item uninstall()

 Process uninstall tasks

 Return int 0 on success, other on failure

=cut

sub uninstall
{
	my $self = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaUninstall', 'postfix');
	return $rs if $rs;

	require Servers::mta::postfix::uninstaller;
	$rs = Servers::mta::postfix::uninstaller->getInstance()->uninstall();
	return $rs if $rs;

	$rs = $self->restart();
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaUninstall', 'postfix');
}

=item postinstall()

 Process postintall tasks

 Return int 0 on success, other on failure

=cut

sub postinstall
{
	my $self = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaPostinstall', 'postfix');
	return $rs if $rs;

	$self->{'restart'} = 'yes';

	$self->{'hooksManager'}->trigger('afterMtaPostinstall', 'postfix');
}

=item setEnginePermissions()

 Set engine permissions

 Return int 0 on success, other on failure

=cut

sub setEnginePermissions
{
	require Servers::mta::postfix::installer;
	Servers::mta::postfix::installer->getInstance()->setEnginePermissions();
}

=item restart()

 Restart server

 Return int 0 on success, other on failure

=cut

sub restart
{
	my $self = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaRestart');
	return $rs if $rs;

	my $stdout;
	$rs = execute("$main::imscpConfig{'SERVICE_MNGR'} $self->{'config'}->{'MTA_SNAME'} restart 2>/dev/null", \$stdout);
	debug($stdout) if $stdout;
	error('Unable to restart Postfix') if $rs > 1;
	return $rs if $rs > 1;

	$self->{'hooksManager'}->trigger('afterMtaRestart');
}

=item postmap($filename, [$filetype = hash])

 Postmap the file

 Return int 0 on success, other on failure

=cut

sub postmap($$;$)
{
	my ($self, $filename, $filetype) = @_;

	$filetype ||= 'hash';

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaPostmap', \$filename, \$filetype);
	return $rs if $rs;

	my ($stdout, $stderr);
	$rs = execute("$self->{'config'}->{'CMD_POSTMAP'} $filetype:$filename", \$stdout, \$stderr);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaPostmap', $filename, $filetype);
}

=item addDmn(\%data)

 Process addDmn tasks

 Return int 0 on success, other on failure

=cut

sub addDmn($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddDmn', $data);
	return $rs if $rs;

	if($data->{'EXTERNAL_MAIL'} eq 'domain') { # Mail for both domain and subdomains is managed by external server
		# Remove entry from the Postfix virtual_mailbox_domains map
		$rs = $self->disableDmn($data);
		return $rs if $rs;

		if($data->{'DOMAIN_TYPE'} eq 'Dmn') {
			# Remove any previous entry of this domain from the Postfix relay_domains map
			$rs = $self->_deleteFromRelayHash($data);
			return $rs if $rs;

			# Add the domain entry to the Postfix relay_domain map
			$rs = $self->_addToRelayHash($data);
			return $rs if $rs;
		}
	} elsif($data->{'EXTERNAL_MAIL'} eq 'wildcard') { # Only mail for in-existent subdomains is managed by external server
		if($data->{'MAIL_ENABLED'}) {
			# Add the domain or subdomain entry to the Postfix virtual_mailbox_domains map
			$rs = $self->_addToDomainsHash($data);
			return $rs if $rs;
		}

		if($data->{'DOMAIN_TYPE'} eq 'Dmn') {
			# Remove any previous entry of this domain from the Postfix relay_domains map
			$rs = $self->_deleteFromRelayHash($data);
			return $rs if $rs;

			# Add the wildcard entry for in-existent subdomains to the Postfix relay_domain map
			$rs = $self->_addToRelayHash($data);
			return $rs if $rs;
		}
	} elsif($data->{'MAIL_ENABLED'}) { # Mail for domain and subdomains is managed by i-MSCP mail host
		# Add domain or subdomain entry to the Postfix virtual_mailbox_domains map
		$rs = $self->_addToDomainsHash($data);
		return $rs if $rs;

		if($data->{'DOMAIN_TYPE'} eq 'Dmn') {
			# Remove any previous entry of this domain from the Postfix relay_domains map
			$rs = $self->_deleteFromRelayHash($data);
			return $rs if $rs;
		}
	} else {
		# Remove entry from the Postfix virtual_mailbox_domains map
		$rs = $self->disableDmn($data);
		return $rs if $rs;

		# Remove any previous entry of this domain from the Postfix relay_domains map
		$rs = $self->_deleteFromRelayHash($data);
		return $rs if $rs;
	}

	$self->{'hooksManager'}->trigger('afterMtaAddDmn', $data);
}

=item disableDmn(\%data)

 Process disableDmn tasks

 Return int 0 on success, other on failure

=cut

sub disableDmn($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDisableDmn', $data);
	return $rs if $rs;

	my $domainsHashFile = fileparse($self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'});
	my $wrkDomainsHashFile = "$self->{'wrkDir'}/$domainsHashFile";
	my $bkpDomainsHashFile = "$self->{'bkpDir'}/$domainsHashFile." . time;
	my $prodDomainsHashFile = $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'};

	$rs = iMSCP::File->new('filename' => $wrkDomainsHashFile)->copyFile($bkpDomainsHashFile);
	return $rs if $rs;

	my $file = iMSCP::File->new('filename' => "$self->{'wrkDir'}/domains");
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkDomainsHashFile");
		return 1;
	}

	my $entry = "$data->{'DOMAIN_NAME'}\t\t\t$data->{'TYPE'}\n";

	$content =~ s/^$entry//gim;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodDomainsHashFile);
	return $rs if $rs;

	$self->{'postmap'}->{$prodDomainsHashFile} = $data->{'DOMAIN_NAME'};

	if($data->{'DOMAIN_TYPE'} eq 'Dmn') {
		$rs = $self->_deleteFromRelayHash($data);
		return $rs if $rs;
	}

	$self->{'hooksManager'}->trigger('afterMtaDisableDmn', $data);
}

=item deleteDmn(\%data)

 Process deleteDmn tasks

 Return int 0 on success, other on failure

=cut

sub deleteDmn($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelDmn', $data);
	return $rs if $rs;

	$rs = $self->disableDmn($data);
	return $rs if $rs;

	$rs = iMSCP::Dir->new('dirname' => "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$data->{'DOMAIN_NAME'}")->remove();
	return $rs if $rs;

	$rs = $self->{'hooksManager'}->trigger('afterMtaDelDmn', $data);
}

=item addSub(\%data)

 Process addSub tasks

 Return int 0 on success, other on failure

=cut

sub addSub($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddSub', $data);
	return $rs if $rs;

	$rs = $self->addDmn($data);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaAddSub', $data);
}

=item disableSub(\%data)

 Process disableSub tasks

 Return int 0 on success, other on failure

=cut

sub disableSub($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDisableSub', $data);
	return $rs if $rs;

	$rs = $self->disableDmn($data);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaDisableSub', $data);
}

=item deleteSub(\%data)

 Process deleteSub tasks

 Return int 0 on success, other on failure

=cut

sub deleteSub($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelSub', $data);
	return $rs if $rs;

	$rs = $self->deleteDmn($data);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaDelSub', $data);
}

=item addMail(\%data)

 Process addMail tasks

 Return int 0 on success, other on failure

=cut

sub addMail($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddMail', $data);
	return $rs if $rs;

	for(
		$self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'}, $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'},
		$self->{'config'}->{'MTA_TRANSPORT_HASH'}
	) {
		my $hashFile = fileparse($_);
		my $wrkHashFile = "$self->{'wrkDir'}/$hashFile";
		my $bkpHashFile = "$self->{'bkpDir'}/$hashFile." . time;

		if(-f $wrkHashFile) {
			$rs = iMSCP::File->new('filename' => $wrkHashFile)->copyFile($bkpHashFile);
			return $rs if $rs;
		}
	}

	if($data->{'MAIL_TYPE'} =~ /_mail/) {
		$rs = $self->_addSaslData($data);
		return $rs if $rs;

		$rs = $self->_addMailBox($data);
		return $rs if $rs;
	} else {
		$rs = $self->_deleteSaslData($data);
		return $rs if $rs;

		$rs = $self->_deleteMailBox($data);
		return $rs if $rs;
	}

	if($data->{'MAIL_HAS_AUTO_RSPND'} eq 'yes') {
		$rs = $self->_addAutoRspnd($data);
		return $rs if $rs;
	} else {
		$rs = $self->_deleteAutoRspnd($data);
		return $rs if $rs;
	}

	if($data->{'MAIL_TYPE'} =~ /_forward/) {
		$rs = $self->_addMailForward($data);
    	return $rs if $rs;
	} else {
		$rs = $self->_deleteMailForward($data);
		return $rs if $rs;
	}

	if($data->{'MAIL_HAS_CATCH_ALL'} eq 'yes') {
		$rs = $self->_addCatchAll($data);
		return $rs if $rs;
	} else {
		$rs = $self->_deleteCatchAll($data);
		return $rs if $rs;
	}

	$self->{'hooksManager'}->trigger('afterMtaAddMail', $data);
}

=item deleteMail(\%data)

 Process deleteMail tasks

 Return int 0 on success, other on failure

=cut

sub deleteMail($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelMail', $data);
	return $rs if $rs;

	for(
		$self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'}, $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'},
		$self->{'config'}->{'MTA_TRANSPORT_HASH'}
	) {
		my $hashFile = fileparse($_);
		my $wrkHashFile = "$self->{'wrkDir'}/$hashFile";
		my $bkpHashFile = "$self->{'bkpDir'}/$hashFile." . time;

		if(-f $wrkHashFile) {
			$rs = iMSCP::File->new('filename' => $wrkHashFile)->copyFile($bkpHashFile);
			return $rs if $rs;
		}
	}

	$rs = $self->_deleteSaslData($data);
	return $rs if $rs;

	$rs = $self->_deleteMailBox($data);
	return $rs if $rs;

	$rs = $self->_deleteMailForward($data);
	return $rs if $rs;

	$rs = $self->_deleteAutoRspnd($data);
	return $rs if $rs;

	$rs = $self->_deleteCatchAll($data);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaDelMail', $data);
}

=item disableMail(\%data)

 Process disableMail tasks

 Return int 0 on success, other on failure

=cut

sub disableMail($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDisableMail', $data);
	return $rs if $rs;

	for(
		$self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'}, $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'},
		$self->{'config'}->{'MTA_TRANSPORT_HASH'}
	) {
		my $hashFile = fileparse($_);
		my $wrkHashFile = "$self->{'wrkDir'}/$hashFile";
		my $bkpHashFile = "$self->{'bkpDir'}/$hashFile." . time;

		if(-f $wrkHashFile) {
			$rs = iMSCP::File->new('filename' => $wrkHashFile)->copyFile($bkpHashFile);
			return $rs if $rs;
		}
	}

	$rs = $self->_deleteSaslData($data);
	return $rs if $rs;

	$rs = $self->_disableMailBox($data);
	return $rs if $rs;

	$rs = $self->_deleteMailForward($data);
	return $rs if $rs;

	$rs = $self->_deleteAutoRspnd($data);
	return $rs if $rs;

	$rs = $self->_deleteCatchAll($data);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaDisableMail', $data);
}

=item getTraffic($domainName)

 Get traffic

 Return int traffic

=cut

sub getTraffic($$)
{
	my ($self, $domainName) = @_;

	my $dbName = "$self->{'wrkDir'}/log.db";
	my $logFile = "$main::imscpConfig{'TRAFF_LOG_DIR'}/mail.log";
	my $wrkLogFile = "$main::imscpConfig{'LOG_DIR'}/mail.smtp.log";
	my ($rs, $rv, $stdout, $stderr);

	$self->{'hooksManager'}->trigger('beforeMtaGetTraffic', $domainName) and return 0;

	# We process only if the file has not been aleady parsed during this session
	unless($self->{'logDb'}) {
		# We are using a small file to memorize the number of the last line that has been read and his content
		tie %{$self->{'logDb'}}, 'iMSCP::Config', 'fileName' => $dbName, 'noerrors' => 1;

		$self->{'logDb'}->{'line'} = 0 unless $self->{'logDb'}->{'line'};
		$self->{'logDb'}->{'content'} = '' unless $self->{'logDb'}->{'content'};

		my $lastLineNo = $self->{'logDb'}->{'line'};
		my $lastLine = $self->{'logDb'}->{'content'};

		$rs = iMSCP::File->new('filename' => $logFile)->copyFile($wrkLogFile) if -f $logFile;
		return 0 if $rs;

		require Tie::File;
		tie my @content, 'Tie::File', $wrkLogFile or return 0;

		# Saving last line number and content from the current working file
		$self->{'logDb'}->{'line'} = $#content;
		$self->{'logDb'}->{'content'} = $content[$#content];

		# Test for logrotation
		if($content[$lastLineNo] && $content[$lastLineNo] eq $lastLine) {
			# No logrotation occured. We want parse only new lines so we skip those already processed
			(tied @content)->defer;
			@content = @content[$lastLineNo + 1 .. $#content];
			(tied @content)->flush;
		}

		# Create working log file using the maillogconvert.pl utility script
		$rs = execute(
			"$main::imscpConfig{'CMD_GREP'} 'postfix' $wrkLogFile | $self->{'config'}->{'CMD_PFLOGSUM'} standard",
			\$stdout,
			\$stderr
		);
		error($stderr) if $stderr && $rs;
		return 0 if $rs;

		# Getting SMTP traffic from working log file
		#
		# SMTP traffic line sample (as provided by the maillogconvert.pl utility script)
		#
		# 2013-09-14 13:23:35 from_user@domain.tld to_user@domain.tld host_from.domain.tld host_to.domain.tld SMTP - 1 626
		#
		while($stdout =~ /^[^\s]+\s[^\s]+\s[^\s\@]+\@([^\s]+)\s[^\s\@]+\@([^\s]+)\s([^\s]+)\s([^\s]+)\s[^\s]+\s[^\s]+\s[^\s]+\s(\d+)$/gim) {
			if($4 !~ /virtual/ && !($3 =~ /localhost|127.0.0.1/ && $4 =~ /localhost|127.0.0.1/)) {
				$self->{'traffic'}->{$1} += $5;
				$self->{'traffic'}->{$2} += $5;
			}
		}
	}

	$self->{'hooksManager'}->trigger('afterMtaGetTraffic', $domainName) and return 0;

	(exists $self->{'traffic'}->{$domainName}) ? $self->{'traffic'}->{$domainName} : 0;
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init()

 Called by getInstance(). Initialize instance of this class.

 Return Servers::mta::postfix

=cut

sub _init
{
	my $self = shift;

	$self->{'hooksManager'} = iMSCP::HooksManager->getInstance();

	$self->{'hooksManager'}->trigger(
		'beforeMtaInit', $self, 'postfix'
	) and fatal('postfix - beforeMtaInit hook has failed');

	$self->{'cfgDir'} = "$main::imscpConfig{'CONF_DIR'}/postfix";
	$self->{'bkpDir'} = "$self->{'cfgDir'}/backup";
	$self->{'wrkDir'} = "$self->{'cfgDir'}/working";

	$self->{'commentChar'} = '#';

	tie %{$self->{'config'}}, 'iMSCP::Config', 'fileName' => "$self->{'cfgDir'}/postfix.data";

	$self->{'hooksManager'}->trigger(
		'afterMtaInit', $self, 'postfix'
	) and fatal('postfix - afterMtaInit hook has failed');

	$self;
}

=item _addToRelayHash(\%data)

 Add entry to relay hash file

 Return int 0 on success, other on failure

=cut

sub _addToRelayHash($$)
{
	my ($self, $data) = @_;;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddToRelayHash', $data);
	return $rs if $rs;

	my $relayHashFile = fileparse($self->{'config'}->{'MTA_RELAY_HASH'});
	my $wrkRelayHashFile = "$self->{'wrkDir'}/$relayHashFile";
	my $bkpRelayHashFile = "$self->{'bkpDir'}/$relayHashFile." . time;
	my $prodRelayHashFile = $self->{'config'}->{'MTA_RELAY_HASH'};

	$rs = iMSCP::File->new('filename' => $wrkRelayHashFile)->copyFile($bkpRelayHashFile);
	return $rs if $rs;

	my $file = iMSCP::File->new('filename' => $wrkRelayHashFile);
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkRelayHashFile");
		return 1;
	}

	my $entry = "$data->{'DOMAIN_NAME'}\t\t\tOK\n";

	if($data->{'EXTERNAL_MAIL'} eq 'wildcard') { # For wildcard MX, we add entry such as ".domain.tld"
		$entry = '.' . $entry;
	}

	$content .= $entry unless $content =~ /^$entry/gim;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodRelayHashFile);
	return $rs if $rs;

	$self->{'postmap'}->{$prodRelayHashFile} = $data->{'DOMAIN_NAME'};

	$self->{'hooksManager'}->trigger('afterMtaAddToRelayHash', $data);
}

=item _deleteFromRelayHash(\%data)

 Delete entry from relay hash file

 Return int 0 on success, other on failure

=cut

sub _deleteFromRelayHash($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelFromRelayHash', $data);
	return $rs if $rs;

	my $relayHashFile = fileparse($self->{'config'}->{'MTA_RELAY_HASH'});
	my $wrkRelayHashFile = "$self->{'wrkDir'}/$relayHashFile";
	my $bkpRelayHashFile = "$self->{'bkpDir'}/$relayHashFile." . time;
	my $prodRelayHashFile = $self->{'config'}->{'MTA_RELAY_HASH'};

	$rs = iMSCP::File->new('filename' => $wrkRelayHashFile)->copyFile($bkpRelayHashFile);
	return $rs if $rs;

	my $file= iMSCP::File->new('filename' => $wrkRelayHashFile);
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkRelayHashFile");
		return 1;
	}

	my $entry = "\\.?$data->{'DOMAIN_NAME'}\t\t\tOK\n"; # Match both "domain.tld" and ".domain.tld" entries

	$content =~ s/^$entry//gim;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodRelayHashFile);
	return $rs if $rs;

	$self->{'postmap'}->{$prodRelayHashFile} = $data->{'DOMAIN_NAME'};

	$self->{'hooksManager'}->trigger('afterMtaDelFromRelayHash', $data);
}

=item _addToDomainsHash(\%data)

 Add entry to domains hash file

 Return int 0 on success, other on failure

=cut

sub _addToDomainsHash($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddToDomainsHash', $data);
	return $rs if $rs;

	my $domainsHashFile = fileparse($self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'});
	my $wrkDomainsHashFile = "$self->{'wrkDir'}/$domainsHashFile";
	my $bkpDomainsHashFile = "$self->{'bkpDir'}/$domainsHashFile." . time;
	my $prodDomainsHashFile = $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'};

	$rs = iMSCP::File->new('filename' => $wrkDomainsHashFile)->copyFile($bkpDomainsHashFile);
	return $rs if $rs;

	my $file = iMSCP::File->new('filename' => $wrkDomainsHashFile);
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkDomainsHashFile");
		return 1;
	}

	my $entry = "$data->{'DOMAIN_NAME'}\t\t\t$data->{'TYPE'}\n";

	$content .= $entry unless $content =~ /^$entry/gim;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodDomainsHashFile);
	return $rs if $rs;

	$self->{'postmap'}->{$prodDomainsHashFile} = $data->{'DOMAIN_NAME'};

	$rs = iMSCP::Dir->new(
		'dirname' => "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$data->{'DOMAIN_NAME'}"
	)->make(
		{
			'user' => $self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
			'group' => $self->{'config'}->{'MTA_MAILBOX_GID_NAME'},
			'mode' => 0750
		}
	);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaAddToDomainsHash', $data);
}

=item _addSaslData(\%data)

 Add SASL data

 Return int 0 on success, other on failure

=cut

sub _addSaslData($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddSaslData', $data);
	return $rs if $rs;

	my $file = iMSCP::File->new('filename' => $self->{'config'}->{'ETC_SASLDB_FILE'});

	$rs = $file->save() unless -f $self->{'config'}->{'ETC_SASLDB_FILE'};
	return $rs if $rs;

	$rs = $file->mode(0660);
	return $rs if $rs;

	$rs = $file->owner($self->{'config'}->{'SASLDB_USER'}, $self->{'config'}->{'SASLDB_GROUP'});
	return $rs if $rs;

	my ($stdout, $stderr);
	$rs = execute(
		"$self->{'config'}->{'CMD_SASLDB_LISTUSERS2'} -f $self->{'config'}->{'ETC_SASLDB_FILE'}", \$stdout, \$stderr
	);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	my $mailboxEntry = quotemeta($data->{'MAIL_ADDR'});

	if($stdout =~ /^$mailboxEntry:/gim) {
		$rs = execute(
			"$self->{'config'}->{'CMD_SASLDB_PASSWD2'} -d -f $self->{'config'}->{'ETC_SASLDB_FILE'} " .
			"-u $data->{'DOMAIN_NAME'} $data->{'MAIL_ACC'}",
			\$stdout,
			\$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	my $password = escapeShell($data->{'MAIL_PASS'});

	$rs = execute(
		"$main::imscpConfig{'CMD_ECHO'} $password | $self->{'config'}->{'CMD_SASLDB_PASSWD2'} -p -c " .
		"-f $self->{'config'}->{'ETC_SASLDB_FILE'} -u $data->{'DOMAIN_NAME'} $data->{'MAIL_ACC'}",
		\$stdout,
		\$stderr
	);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	if($self->{'config'}->{'ETC_SASLDB_FILE'} ne $self->{'config'}->{'MTA_SASLDB_FILE'}) {
		$rs = execute(
			"$main::imscpConfig{'CMD_CP'} -fp $self->{'config'}->{'ETC_SASLDB_FILE'} " .
			"$self->{'config'}->{'MTA_SASLDB_FILE'}",
			\$stdout,
			\$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	$self->{'hooksManager'}->trigger('afterMtaAddSaslData', $data);
}

=item _deleteSaslData(\%data)

 Delete SASL data

 Return int 0 on success, other on failure

=cut

sub _deleteSaslData($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelSaslData', $data);
	return $rs if $rs;

	my ($stdout, $stderr);

	my $mailboxEntry = quotemeta($data->{'MAIL_ADDR'});

	my $file = iMSCP::File->new('filename' => $self->{'config'}->{'ETC_SASLDB_FILE'});

	$rs = $file->save() unless -f $self->{'config'}->{'ETC_SASLDB_FILE'};
	return $rs if $rs;

	$rs = $file->mode(0660);
	return $rs if $rs;

	$rs = $file->owner($self->{'config'}->{'SASLDB_USER'}, $self->{'config'}->{'SASLDB_GROUP'});
	return $rs if $rs;

	$rs = execute(
		"$self->{'config'}->{'CMD_SASLDB_LISTUSERS2'} -f $self->{'config'}->{'ETC_SASLDB_FILE'}", \$stdout, \$stderr
	);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	if($stdout =~ /^$mailboxEntry:/gim) {
		$rs = execute(
			"$self->{'config'}->{'CMD_SASLDB_PASSWD2'} -d -f $self->{'config'}->{'ETC_SASLDB_FILE'} " .
			"-u $data->{'DOMAIN_NAME'} $data->{'MAIL_ACC'}",
			\$stdout,
			\$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;

		if($self->{'config'}->{'ETC_SASLDB_FILE'} ne $self->{'config'}->{'MTA_SASLDB_FILE'}) {
			$rs = execute(
				"$main::imscpConfig{'CMD_CP'} -fp $self->{'config'}->{'ETC_SASLDB_FILE'} " .
				"$self->{'config'}->{'MTA_SASLDB_FILE'}",
				\$stdout,
				\$stderr
			);
			debug($stdout) if $stdout;
			error($stderr) if $stderr && $rs;
			return $rs if $rs;
		}
	}

	$self->{'hooksManager'}->trigger('afterMtaDelSaslData', $data);
}

=item _addMailBox(\%data)

 Add mailbox

 Return int 0 on success, other on failure

=cut

sub _addMailBox($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddMailbox', $data);
	return $rs if $rs;

	my $mailboxesFileHash = fileparse($self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'});
	my $wrkMailboxesFileHash = "$self->{'wrkDir'}/$mailboxesFileHash";
	my $prodMailboxesFileHash = $self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'};

	my $file = iMSCP::File->new('filename' => $wrkMailboxesFileHash);
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkMailboxesFileHash");
		return 1;
	}

	my $mailbox = quotemeta($data->{'MAIL_ADDR'});

	$content =~ s/^$mailbox\s+[^\n]*\n//gim;
	$content .= "$data->{'MAIL_ADDR'}\t$data->{'DOMAIN_NAME'}/$data->{'MAIL_ACC'}/\n";

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodMailboxesFileHash);
	return $rs if $rs;

	$self->{'postmap'}->{$prodMailboxesFileHash} = $data->{'MAIL_ADDR'};

	my $mailDir = "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$data->{'DOMAIN_NAME'}/$data->{'MAIL_ACC'}";
	my $mailUidName = $self->{'config'}->{'MTA_MAILBOX_UID_NAME'};
	my $mailGidName = $self->{'config'}->{'MTA_MAILBOX_GID_NAME'};

	# Creating maildir directory or only set its permissions if already exists
	$rs = iMSCP::Dir->new(
		'dirname' => $mailDir
	)->make(
		{
			'user' => $self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
			'group' => $self->{'config'}->{'MTA_MAILBOX_GID_NAME'},
			'mode' => 0750
		}
	);
	return $rs if $rs;

	# Creating maildir sub folders (cur, new, tmp) or only set there permissions if they already exists
	for('cur', 'new', 'tmp') {
		$rs = iMSCP::Dir->new(
			'dirname' => "$mailDir/$_"
		)->make(
			{ 'user' => $mailUidName, 'group' => $mailGidName, 'mode' => 0750 }
		);
		return $rs if $rs;
	}

	$self->{'hooksManager'}->trigger('afterMtaAddMailbox', $data);
}

=item _disableMailBox(\%data)

 Disable mailbox

 Return int 0 on success, other on failure

=cut

sub _disableMailBox($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDisableMailbox', $data);
	return $rs if $rs;

	my $mailboxesFileHash = fileparse($self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'});
	my $wrkMailboxesFileHash = "$self->{'wrkDir'}/$mailboxesFileHash";
	my $prodMailboxesFileHash = $self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'};

	my $file = iMSCP::File->new('filename' => $wrkMailboxesFileHash);
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkMailboxesFileHash");
		return 1;
	}

	my $mailbox = quotemeta($data->{'MAIL_ADDR'});

	$content =~ s/^$mailbox\s+[^\n]*\n//gim;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodMailboxesFileHash);
	return $rs if $rs;

	$self->{'postmap'}->{$prodMailboxesFileHash} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaDisableMailbox', $data);
}

=item _deleteMailBox(\%data)

 Delete mailbox

 Return int 0 on success, other on failure

=cut

sub _deleteMailBox($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelMailbox', $data);
	return $rs if $rs;

	$rs = $self->_disableMailBox($data);
	return $rs if $rs;

	return $rs if ! $data->{'MAIL_ACC'};

	my $mailDir = "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$data->{'DOMAIN_NAME'}/$data->{'MAIL_ACC'}";

	$rs = iMSCP::Dir->new('dirname' => $mailDir)->remove();
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaDelMailbox', $data);
}

=item _addMailForward(\%data)

 Add forward mail

 Return int 0 on success, other on failure

=cut

sub _addMailForward($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddMailForward', $data);
	return $rs if $rs;

	my $aliasesFileHash = fileparse($self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'});
	my $wrkAliasesFileHash = "$self->{'wrkDir'}/$aliasesFileHash";
	my $prodAliasesFileHash = $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'};

	my $file = iMSCP::File->new('filename' => $wrkAliasesFileHash);
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkAliasesFileHash");
		return 1;
	}

	my $forwardEntry = quotemeta($data->{'MAIL_ADDR'});

	$content =~ s/^$forwardEntry\s+[^\n]*\n//gim;

	my @line;

	# For a normal+foward mail account, we must add the recipient as address to keep local copy of any forwarded mail
	push(@line, $data->{'MAIL_ADDR'}) if $data->{'MAIL_TYPE'} =~ /_mail/;

	# Add address(s) to which mail will be forwarded
	push(@line, $data->{'MAIL_FORWARD'});

	# If the auto-responder is activated, we must add an address such as user@imscp-arpl.domain.tld
	push(@line, "$data->{'MAIL_ACC'}\@imscp-arpl.$data->{'DOMAIN_NAME'}") if $data->{'MAIL_AUTO_RSPND'};

	$content .= "$data->{'MAIL_ADDR'}\t" . join(',', @line) . "\n" if scalar @line;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodAliasesFileHash);
	return $rs if $rs;

	$self->{'postmap'}->{$prodAliasesFileHash} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaAddMailForward', $data);
}

=item _deleteMailForward(\%data)

 Delete forward mail

 Return int 0 on success, other on failure

=cut

sub _deleteMailForward($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelMailForward', $data);
	return $rs if $rs;

	my $aliasesFileHash = fileparse($self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'});
	my $wrkAliasesFileHash = "$self->{'wrkDir'}/$aliasesFileHash";
	my $prodAliasesFileHash = $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'};

	my $file = iMSCP::File->new('filename' => $wrkAliasesFileHash);
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkAliasesFileHash");
		return 1;
	}

	my $forwardEntry = quotemeta($data->{'MAIL_ADDR'});

	$content =~ s/^$forwardEntry\s+[^\n]+\n//gim;

	# Handle normal mail accounts entries for which auto-responder is active
	if($data->{'MAIL_STATUS'} ne 'todelete') {
		my @line;

		# If auto-responder is activated, we must add the recipient as address to keep local copy of any forwarded mail
		push(@line, $data->{'MAIL_ADDR'}) if $data->{'MAIL_AUTO_RSPND'} && $data->{'MAIL_TYPE'} =~ /_mail/;

		# If auto-responder is activated, we need an address such as user@imscp-arpl.domain.tld
		push(@line, "$data->{'MAIL_ACC'}\@imscp-arpl.$data->{'DOMAIN_NAME'}")
			if $data->{'MAIL_AUTO_RSPND'} && $data->{'MAIL_TYPE'} =~ /_mail/;

		$content .= "$data->{'MAIL_ADDR'}\t" . join(',', @line) . "\n" if scalar @line;
	}

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodAliasesFileHash);
	return $rs if $rs;

	$self->{'postmap'}->{$prodAliasesFileHash} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaDelMailForward', $data);
}

=item _addAutoRspnd(\%data)

 Add auto-responder

 Return int 0 on success, other on failure

=cut

sub _addAutoRspnd($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddAutoRspnd', $data);
	return $rs if $rs;

	my $transportFileHash = fileparse($self->{'config'}->{'MTA_TRANSPORT_HASH'});
	my $wrkTransportFileHash = "$self->{'wrkDir'}/$transportFileHash";
	my $prodTransportFileHash = $self->{'config'}->{'MTA_TRANSPORT_HASH'};

	my $file = iMSCP::File->new('filename' => $wrkTransportFileHash);
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkTransportFileHash");
		return 1;
	}

	my $transportEntry = quotemeta("imscp-arpl.$data->{'DOMAIN_NAME'}");

	$content =~ s/^$transportEntry\s+[^\n]*\n//gmi;
	$content .= "imscp-arpl.$data->{'DOMAIN_NAME'}\timscp-arpl:\n";

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodTransportFileHash);
	return $rs if $rs;

	$self->{'postmap'}->{$prodTransportFileHash} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaAddAutoRspnd', $data);
}

=item _deleteAutoRspnd(\%data)

 Delete auto-responder

 Return int 0 on success, other on failure

=cut

sub _deleteAutoRspnd($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelAutoRspnd', $data);
	return $rs if $rs;

	my $transportFileHash = fileparse($self->{'config'}->{'MTA_TRANSPORT_HASH'});
	my $wrkTransportFileHash = "$self->{'wrkDir'}/$transportFileHash";
	my $prodTransportFileHash = $self->{'config'}->{'MTA_TRANSPORT_HASH'};

	my $file = iMSCP::File->new('filename' => $wrkTransportFileHash);
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkTransportFileHash");
		return 1;
	}

	my $transportEntry = quotemeta("imscp-arpl.$data->{'DOMAIN_NAME'}");

	$content =~ s/^$transportEntry\s+[^\n]*\n//gmi;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodTransportFileHash);
	return $rs if $rs;

	$self->{'postmap'}->{$prodTransportFileHash} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaDelAutoRspnd', $data);
}

=item _addCatchAll(\%data)

 Add catchall

 Return int 0 on success, other on failure

=cut

sub _addCatchAll($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddCatchAll', $data);
	return $rs if $rs;

	my $aliasesFileHash = fileparse($self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'});
	my $wrkAliasesFileHash = "$self->{'wrkDir'}/$aliasesFileHash";
	my $prodAliasesFileHash = $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'};

	my $file = iMSCP::File->new('filename' => $wrkAliasesFileHash);
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkAliasesFileHash");
		return 1;
	}

	for(@{$data->{'MAIL_ON_CATCHALL'}}) {
		my $mailbox = quotemeta($_);
		$content =~ s/^$mailbox\s+$mailbox\n//gim;
		$content .= "$_\t$_\n";
	}

	if($data->{'MAIL_TYPE'} =~ /_catchall/) {
		my $catchAll = quotemeta("\@$data->{'DOMAIN_NAME'}");
		$content =~ s/^$catchAll\s+[^\n]*\n//gim;
		$content .= "\@$data->{'DOMAIN_NAME'}\t$data->{'MAIL_CATCHALL'}\n";
	}

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodAliasesFileHash);
	return $rs if $rs;

	$self->{'postmap'}->{$prodAliasesFileHash} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaAddCatchAll', $data);
}

=item _deleteCatchAll(\%data)

 Delete catchall

 Return int 0 on success, other on failure

=cut

sub _deleteCatchAll($$)
{
	my ($self, $data) = @_;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelCatchAll', $data);
	return $rs if $rs;

	my $aliasesFileHash = fileparse($self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'});
	my $wrkAliasesFileHash = "$self->{'wrkDir'}/$aliasesFileHash";
	my $prodAliasesFileHash = $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'};

	my $file = iMSCP::File->new('filename' => $wrkAliasesFileHash);
	my $content = $file->get();

	unless(defined $content) {
		error("Unable to read $wrkAliasesFileHash");
		return 1;
	}

	for(@{$data->{'MAIL_ON_CATCHALL'}}) {
		my $mailbox = quotemeta($_);
		$content =~ s/^$mailbox\s+$mailbox\n//gim;
	}

	my $catchAll = quotemeta("\@$data->{'DOMAIN_NAME'}");

	$content =~ s/^$catchAll\s+[^\n]*\n//gim;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($prodAliasesFileHash);
	return $rs if $rs;

	$self->{'postmap'}->{$prodAliasesFileHash} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaDelCatchAll', $data);
}

=item END

 Process end tasks

=cut

END
{
	my $exitCode = $?;
	my $self = Servers::mta::postfix->getInstance();
	my $wrkLogFile = "$main::imscpConfig{'LOG_DIR'}/mail.smtp.log";
	my $rs = 0;

	# In any case we postmap if needed
	for(keys %{$self->{'postmap'}}) {
		$rs |= $self->postmap($_);
	}

	if($self->{'restart'} && $self->{'restart'} eq 'yes') {
		$rs |= $self->restart();
	}

	$rs |= iMSCP::File->new('filename' => $wrkLogFile)->delFile() if -f $wrkLogFile;

	$? = $exitCode || $rs;
}

=back

=head1 AUTHORS

 Daniel Andreca <sci2tech@gmail.com>
 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
