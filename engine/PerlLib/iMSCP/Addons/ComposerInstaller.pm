#!/usr/bin/perl

=head1 NAME

 iMSCP::Addons::ComposerInstaller - i-MSCP Addons Composer installer

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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# @category    i-MSCP
# @copyright   2010-2014 by i-MSCP | http://i-mscp.net
# @author      Laurent Declercq <l.declercq@nuxwin.com>
# @link        http://i-mscp.net i-MSCP Home Site
# @license     http://www.gnu.org/licenses/gpl-2.0.html GPL v2

package iMSCP::Addons::ComposerInstaller;

use strict;
use warnings;

use iMSCP::Debug;
use iMSCP::File;
use iMSCP::Dir;
use iMSCP::Execute;
use iMSCP::TemplateParser;
use iMSCP::HooksManager;
use iMSCP::Getopt;
use iMSCP::Dialog;
use Cwd;
use parent 'Common::SingletonClass';

=head1 DESCRIPTION

 Composer installer for iMSCP. Allows to install composer packages from packagist.org.

=head1 PUBLIC METHODS

=over 4

=item registerPackage($package, [$packageVersion = 'dev-master'])

 Register the given composer package for installation.

 Return int - 0

=cut

sub registerPackage($$;$)
{
	my $self = shift;
	my $package = shift;
	my $packageVersion = shift || 'dev-master';

	push @{$self->{'toInstall'}}, "\t\t\"$package\":\"$packageVersion\"";

	0;
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init()

 Called by getInstance(). Initialize instance of this class.

 Return iMSCP::Addons::ComposerInstaller

=cut

sub _init
{
	my $self = shift;

	# Increase composer process timeout for slow connections
	$ENV{'COMPOSER_PROCESS_TIMEOUT'} = 2000;

	$self->{'toInstall'} = [];
	$self->{'cacheDir'} = $main::imscpConfig{'ADDON_PACKAGES_CACHE_DIR'};
	$self->{'phpCmd'} = $main::imscpConfig{'CMD_PHP'} .
		' -d memory_limit=512M -d allow_url_fopen=1' .
		' -d suhosin.executor.include.whitelist=phar';

	if(! iMSCP::Getopt->skipAddonsUpdate || ! -d $self->{'cacheDir'}) {
		iMSCP::Dir->new(
			'dirname' => $self->{'cacheDir'}
		)->make() and fatal('Unable to create addon cache directory');

		# Override default composer home directory
		$ENV{'COMPOSER_HOME'} = "$self->{'cacheDir'}/.composer";

		# Cleanup addon packages cache directory if asked by user - This will cause all addon packages to be fetched
		# again
		$self->_cleanCacheDir() if iMSCP::Getopt->cleanAddons;

		# Schedule package installation (done after addons preinstallation)
		iMSCP::HooksManager->getInstance()->register(
			'afterSetupPreInstallAddons', sub { iMSCP::Dialog->factory()->endGauge(); $self->_installPackages() }
		);
	}

	$self;
}

=item _installPackages()

 Install or update packages in addons cache repository.

 Return 0 on success, other on failure

=cut

sub _installPackages
{
	my $self = shift;

	my $rs = $self->_buildComposerFile();
	return $rs if $rs;

	$rs = $self->_getComposer();
	return $rs if $rs;

	iMSCP::Dialog->factory()->infobox(
'
Getting i-MSCP addon packages from GitHub.

Please wait, depending of your connection, this may take few minutes.
'
	);

	# The update option is used here but composer will automatically fallback to install mode when needed
	my ($stdout, $stderr);
	$rs = execute(
		"$self->{'phpCmd'} $self->{'cacheDir'}/composer.phar -d=$self->{'cacheDir'} update", \$stdout, \$stderr
	);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	error('Unable to get i-MSCP addon packages from GitHub') if $rs && ! $stderr;

	$rs;
}

=item _buildComposerFile()

 Build composer.json file.

 Return 0 on success, other on failure

=cut

sub _buildComposerFile
{
	my $self = shift;

	iMSCP::Dialog->factory()->infobox("\nBuilding composer.json file for addon packages...");

	my $composerJsonFile = process({ 'PACKAGES' => join ",\n", @{$self->{'toInstall'}} }, $self->_getComposerFileTpl());

	my $file = iMSCP::File->new('filename' => "$self->{'cacheDir'}/composer.json");

	my $rs = $file->set($composerJsonFile);
	return $rs if $rs;

	$file->save();
}

=item _getComposer()

 Get composer.phar.

 Return 0 on success, other on failure

=cut

sub _getComposer
{
	my $self = shift;

	my ($stdout, $stderr);
	my $curDir = getcwd();
	my $rs = 0;

	if (! -f "$self->{'cacheDir'}/composer.phar") {
		unless(chdir($self->{'cacheDir'})) {
			error("Unable to change working directory to $self->{'cacheDir'}: $!");
			return 1;
		}

		iMSCP::Dialog->factory()->infobox(
"
Getting composer installer from http://getcomposer.org.

Please wait, depending of your connection, this may take few seconds...
"
		);

		$rs = execute(
			"$main::imscpConfig{'CMD_CURL'} -s http://getcomposer.org/installer | $self->{'phpCmd'}",
			\$stdout,
			\$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		error($stdout) if ! $stderr && $stdout && $rs;
		error('Unable to get composer installer from http://getcomposer.org') if $rs && ! $stdout && ! $stderr;

		unless(chdir($curDir)) {
		error("Unable to change working directory to $curDir: $!");
		return 1;
		}
	} else {
		unless(chdir($self->{'cacheDir'})) {
			error("Unable to change working directory to $self->{'cacheDir'}: $!");
			return 1;
		}

		iMSCP::Dialog->factory()->infobox(
"
Updating composer installer from http://getcomposer.org.

Please wait, depending of your connection, this may take few seconds...
"
		);

		$rs = execute(
			"$self->{'phpCmd'} $self->{'cacheDir'}/composer.phar -d=$self->{'cacheDir'} self-update", \$stdout, \$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		error('Unable to update composer installer') if $rs && ! $stderr;

		unless(chdir($curDir)) {
			error("Unable to change working directory to $curDir: $!");
			return 1;
		}
	}

	$rs;
}

=item _getComposerFileTpl()

 Get composer.json template.

 Return string composer.json template file content

=cut

sub _getComposerFileTpl
{
	<<EOF;
{
	"name":"imscp/addons",
	"description":"i-MSCP addons composer file",
	"license":"GPL-2.0+",
	"require":{
{PACKAGES}
	},
	"minimum-stability":"dev"
}
EOF
}

=item _cleanCacheDir()

 Clean local addon packages repository repository.

 Return 0 on success, other on failure

=cut

sub _cleanCacheDir
{
	my $self = shift;

	my $rs = 0;

	if(-d $self->{'cacheDir'}) {
		my ($stdout, $stderr);
		$rs = execute("$main::imscpConfig{'CMD_RM'} -fR $self->{'cacheDir'}/*", \$stdout, \$stderr);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		error('Unable to clean addon cache directory') if $rs && ! $stderr;
	}

	$rs;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
