#!/usr/bin/perl

=head1 NAME

 autoinstaller::Common - Common functions for the i-MSCP autoinstaller

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright 2010-2014 by internet Multi Server Control Panel
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
# @category		i-MSCP
# @copyright	2010-2014 by i-MSCP | http://i-mscp.net
# @author		Daniel Andreca <sci2tech@gmail.com>
# @author		Laurent Declercq <l.declercq@nuxwin.com>
# @link			http://i-mscp.net i-MSCP Home Site
# @license		http://www.gnu.org/licenses/gpl-2.0.html GPL v2

package autoinstaller::Common;

use strict;
use warnings;

use iMSCP::Debug;
use iMSCP::Dialog;
use iMSCP::Config;
use iMSCP::LsbRelease;
use iMSCP::HooksManager;
use iMSCP::Execute;
use iMSCP::Dir;
use iMSCP::File;
use File::Find;
use Cwd;

use parent 'Exporter';
our @EXPORT = qw(
	loadConfig installPreRequiredPackages checkDistribution preBuild uninstallPackages installPackages
	testRequirements processDistroLayoutFile processDistroInstallFiles buildImscpDaemon installEngine installGui
	postBuild doImscpBackup savePersistentData installTmp removeTmp checkCommandAvailability
);

=head1 DESCRIPTION

 Common functions for autoinstaller.

=head1 EXPORTED FUNCTIONS

=over 4

=item loadConfig()

 Load main i-MSCP configuration.

 Load both the new imscp.conf file (upstread conffile) and the current imscp.conf file (old conffile) and merge them
together in the %main::imscpConfig variable. The old imscp.conf file is tied to the %main::imscpOldConfig variable
and set as readonly.

 Return int - 0

=cut

sub loadConfig
{
	# Load news imscp.conf conffile from i-MSCP upstream source
	tie
		my %imscpNewConfig,
		'iMSCP::Config',
		'fileName' => "$FindBin::Bin/configs/" . lc(iMSCP::LsbRelease->getInstance()->getId(1)) . '/imscp.conf';

	%main::imscpConfig = %imscpNewConfig;

	# Load current i-MSCP conffile as readonly if it exists
	if (-f "$imscpNewConfig{'CONF_DIR'}/imscp.conf") {
		tie
			%main::imscpOldConfig,
			'iMSCP::Config',
			'fileName' => "$imscpNewConfig{'CONF_DIR'}/imscp.conf",
			'readonly' => 1;

		# Merge current config with the new but do not write anything yet. This is done at postBuild step
		for(keys %main::imscpOldConfig) {
			if(exists $main::imscpConfig{$_}) {
				$main::imscpConfig{$_} = $main::imscpOldConfig{$_};
			}
		}

		# Revert back needed variables with newest values
		$main::imscpConfig{'BuildDate'} = $imscpNewConfig{'BuildDate'};
		$main::imscpConfig{'Version'} = $imscpNewConfig{'Version'};
		$main::imscpConfig{'CodeName'} = $imscpNewConfig{'CodeName'};
		$main::imscpConfig{'DistName'} = $imscpNewConfig{'DistName'};
		$main::imscpConfig{'THEME_ASSETS_VERSION'} = $imscpNewConfig{'THEME_ASSETS_VERSION'};
	} else { # No conffile found, assumption is made that it's a new install
		%main::imscpOldConfig = ();
	}

	0;
}

=item installPreRequiredPackages

 Trigger pre-required package installation from distro autoinstaller adapter.

 Return int - 0 on success, other otherwise

=cut

sub installPreRequiredPackages
{
	_getDistroAdapter()->installPreRequiredPackages();
}

=item checkDistribution()

 Check distribution.

 Return int - 0 on success, 1 on failure

=cut

sub checkDistribution()
{
	my $self = shift;

	iMSCP::Dialog->factory()->infobox("\nDetecting target distribution...");

	my $lsbRelease = iMSCP::LsbRelease->getInstance();
	my $distribution = $lsbRelease->getId(1);
	my $codename = lc($lsbRelease->getCodename(1));
	my $release = $lsbRelease->getRelease(1);
	my $description = $lsbRelease->getDescription(1);
	my $packagesFile = "$FindBin::Bin/docs/$distribution/packages-$codename.xml";

	if($distribution ne "n/a" && (lc($distribution) eq 'debian' || lc($distribution) eq 'ubuntu') && $codename ne "n/a") {
		if(! -f $packagesFile) {
			iMSCP::Dialog->factory()->msgbox(
"
\\Z1$distribution $release ($codename) not supported yet\\Zn

We are sorry but the version of your distribution is not supported yet.

You can try to provide your own packages file by putting it into the
\\Z4docs/$distribution\\Zn directory and try again, or ask the i-MSCP team to add it for you.

Thanks for using i-MSCP.
"
			);

			return 1;
		}

		my $rs = iMSCP::Dialog->factory()->yesno("\n$distribution $release ($codename) has been detected. Is this ok?");

		iMSCP::Dialog->factory()->msgbox(
"
\\Z1Distribution not supported\\Zn

We are sorry but the installer has failed to detect your distribution, or
process has been aborted by user.

Only \\ZuDebian-like\\Zn operating systems are supported.

Thanks for using i-MSCP.
"
		) if $rs;

		return 1 if $rs;
	} else {
		iMSCP::Dialog->factory()->msgbox(
"
\\Z1Distribution not supported\\Zn

We are sorry but your distribution is not supported yet.

Only \\ZuDebian-like\\Zn operating systems are supported.

Thanks for using i-MSCP.
"
		);

		return 1;
	}

	0;
}

=item preBuild()

 Trigger pre-build tasks from distro autoinstaller adapter.

 Return int - 0 on success, other on failure

=cut

sub preBuild
{
	_getDistroAdapter()->preBuild();
}

=item uninstallPackages()

 Trigger packages uninstallation from distro autoinstaller adapter.

 Return int - 0 on success, other on failure

=cut

sub uninstallPackages
{
	_getDistroAdapter()->uninstallPackages();
}

=item installPackages()

 Trigger packages installation from distro autoinstaller adapter.

 Return int - 0 on success, other on failure

=cut

sub installPackages
{
	_getDistroAdapter()->installPackages();
}

=item testRequirements()

 Test for i-MSCP requirements.

 Return int 0 - On error, a fatal error is raised

=cut

sub testRequirements
{
	iMSCP::Requirements->new()->test('all');
}

=item processDistroLayoutFile()

 Process distribution layout.xml file

 Return int 0 on success, other on failure

=cut

sub processDistroLayoutFile()
{
	_processXmlFile(
		"$FindBin::Bin/autoinstaller/Adapter/" . iMSCP::LsbRelease->getInstance()->getId(1) . '/layout.xml'
	);
}

=item processDistroInstallFiles()

 Process distribution install.xml files.

 Return int - 0 on success, other on failure

=cut

sub processDistroInstallFiles
{
	my $specificPath = "$FindBin::Bin/configs/" . lc(iMSCP::LsbRelease->getInstance()->getId(1));
	my $commonPath = "$FindBin::Bin/configs/debian";
	my $path = -d $specificPath ? $specificPath : $commonPath;

	unless(chdir($path)) {
		error("Unable to change path to $path: $!");
		return 1;
	}

	my $file = -f "$specificPath/install.xml" ? "$specificPath/install.xml" : "$commonPath/install.xml";

	my $rs = _processXmlFile($file);
	return $rs if $rs;

	# eg. /configs/debian
	my $dir = iMSCP::Dir->new('dirname' => $commonPath);
	my @configs = $dir->getDirs();

	for(@configs) {
		$path = -d "$specificPath/$_" ? "$specificPath/$_" : "$commonPath/$_";

		unless(chdir($path)) {
			error("Cannot change path to $path: $!");
			return 1;
		}

		$file = -f "$specificPath/$_/install.xml" ? "$specificPath/$_/install.xml" : "$commonPath/$_/install.xml";

		$rs = _processXmlFile($file);
		return $rs if $rs;
	}

	0;
}

=item

 Build i-MSCP daemon

 Return int - 0 on success, other on failure.

=cut

# Build the i-MSCP daemon by running make.
#
# @return 0 on success
sub buildImscpDaemon
{
	unless(chdir "$FindBin::Bin/daemon") {
		error("Unable to change path to $FindBin::Bin/daemon");
		return 1;
	}

	my ($stdout, $stderr);

	my $rs = execute("$main::imscpConfig{'CMD_MAKE'} clean imscp_daemon", \$stdout, \$stderr);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	error('Unable to build i-MSCP daemon') if $rs;
	return $rs if $rs;


	my $dir = iMSCP::Dir->new('dirname' => "$main::{'SYSTEM_ROOT'}/daemon");
	$rs = $dir->make();
	return $rs if $rs;

	my $file = iMSCP::File->new('filename' => 'imscp_daemon');
	$rs = $file->copyFile("$main::{'SYSTEM_ROOT'}/daemon");
	return $rs if $rs;

	$rs = execute("$main::imscpConfig{'CMD_MAKE'} clean", \$stdout, \$stderr);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	error('Cannot clean i-MSCP daemon artifacts') if $rs;
	return $rs if $rs;

	0;
}

=item installEngine()

 Install engine files in build directory.

 Return int - 0 on success, other on failure

=cut

sub installEngine
{
	unless(chdir "$FindBin::Bin/engine") {
		error("Unable to change path to $FindBin::Bin/engine");
		return 1;
	}

	my $rs = _processXmlFile("$FindBin::Bin/engine/install.xml");
	return $rs if $rs;

	my $dir = iMSCP::Dir->new('dirname' => "$FindBin::Bin/engine");

	my @configs = $dir->getDirs();

	for(@configs) {
		if (-f "$FindBin::Bin/engine/$_/install.xml") {
			unless(chdir "$FindBin::Bin/engine/$_") {
				error("Unable to change path to $FindBin::Bin/engine/$_");
				return 1;
			}

			$rs = _processXmlFile("$FindBin::Bin/engine/$_/install.xml") ;
			return $rs if $rs;
		}
	}

	0;
}

=item installGui()

 Install GUI files in build directory.

 Return int - 0 on success, other on failure

=cut
sub installGui
{
	my ($stdout, $stderr);
	my $rs = execute("$main::imscpConfig{'CMD_CP'} -fR $FindBin::Bin/gui $main::{'SYSTEM_ROOT'}", \$stdout, \$stderr);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;

	$rs;
}

=item postBuild()

 Process post-build tasks.

 Trigger post-build tasks from distro autoinstaller adapter and save i-MSCP main configuration file.

 Return int - 0 on success, other on failure

=cut

sub postBuild
{
	my $rs = iMSCP::HooksManager->getInstance()->trigger('beforePostBuild');
	return $rs if $rs;

	$rs = _getDistroAdapter()->postBuild();
	return $rs if $rs;

	# Backup current config if any
	if(-f "$main::imscpConfig{'CONF_DIR'}/imscp.conf") {
		my $file = iMSCP::File->new('filename' => "$main::imscpConfig{'CONF_DIR'}/imscp.conf");

		my $cfg = $file->get();
		unless(defined $cfg) {
			error("Unable to read $main::imscpConfig{'CONF_DIR'}/imscp.conf");
			return 1;
		}

		$rs = $file->copyFile("$main::imscpConfig{'CONF_DIR'}/imscp.old.conf");
		return $rs if $rs;
	}

	# Write new config file into build directory

	my %imscpConf = %main::imscpConfig;
	tie %main::imscpConfig, 'iMSCP::Config', 'fileName' => "$main::{'SYSTEM_CONF'}/imscp.conf";

	for(keys %imscpConf) {
		$main::imscpConfig{$_} = $imscpConf{$_};
	}

	# Cleanup build tree directory (remove any .gitignore|empty-file)
    find(
    	sub {
    		unlink or fatal("Unable to remove $File::Find::name: $!") if  $_ eq '.gitignore' || $_ eq 'empty-file';
    	},
    	$main::{'INST_PREF'}
    );

	iMSCP::HooksManager->getInstance()->trigger('afterPostBuild');
}

=item doImscpBackup

 Backup current i-MSCP installation (database and conffiles) if any.

 Return int - 0 on success, other on failure

=cut

sub doImscpBackup
{
	my $rs = 0;

	if(-x "$main::imscpConfig{'ROOT_DIR'}/engine/backup/imscp-backup-imscp" && -f "$main::{'SYSTEM_CONF'}/imscp.conf") {
		my ($stdout, $stderr);
		$rs = execute("$main::imscpConfig{'ROOT_DIR'}/engine/backup/imscp-backup-imscp", \$stdout, \$stderr);
		debug($stdout) if $stdout;
		warning($stderr) if $stderr && $rs;
		warning('Unable to backup previous i-MSCP installation') if $rs;

		$rs = iMSCP::Dialog->factory()->yesno(
"
\\Z1Unable to create backups\\Zn

This is not a fatal error, setup may continue, but you will not have a backup (unless you have previously builded one).

Do you want to continue?
"
		) if $rs;
	}

	$rs;
}

=item savPersistentData()

 Save persistent data in build directory.

 Return int - 0 on success, other on failure

=cut

sub savePersistentData
{
	my $rs = 0;
	my ($stdout, $stderr);
	my $destdir = $main::{'INST_PREF'};

	#
	## i-MSCP version prior 1.0.4
	#

	# Save ISP logos
	if(-d "$main::imscpConfig{'ROOT_DIR'}/gui/themes/user_logos") {
		$rs = execute(
			"$main::imscpConfig{'CMD_CP'} -fRT $main::imscpConfig{'ROOT_DIR'}/gui/themes/user_logos " .
			"$destdir$main::imscpConfig{'ROOT_DIR'}/gui/data/persistent/ispLogos", \$stdout, \$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	#
	## i-MSCP version >= 1.0.4
	#

	# Save Web directories skeletons
	if(-d "$main::imscpConfig{'CONF_DIR'}/apache/skel") {
		$rs = execute(
			"$main::imscpConfig{'CMD_CP'} -fRT $main::imscpConfig{'CONF_DIR'}/apache/skel " .
			"$destdir$main::imscpConfig{'CONF_DIR'}/apache/skel", \$stdout, \$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	# Save GUI logs
	if(-d "$main::imscpConfig{'ROOT_DIR'}/gui/data/logs") {
		$rs = execute(
			"$main::imscpConfig{'CMD_CP'} -fRT $main::imscpConfig{'ROOT_DIR'}/gui/data/logs " .
			"$destdir$main::imscpConfig{'ROOT_DIR'}/gui/data/logs", \$stdout, \$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	# Save persistent data
	if(-d "$main::imscpConfig{'ROOT_DIR'}/gui/data/persistent") {
		$rs = execute(
			"$main::imscpConfig{'CMD_CP'} -fRT $main::imscpConfig{'ROOT_DIR'}/gui/data/persistent " .
			"$destdir$main::imscpConfig{'ROOT_DIR'}/gui/data/persistent", \$stdout, \$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	# save isp logos
	if(-d "$main::imscpConfig{'ROOT_DIR'}/gui/data/ispLogos") {
		$rs = execute(
			"$main::imscpConfig{'CMD_CP'} -fRT $main::imscpConfig{'ROOT_DIR'}/gui/data/ispLogos " .
			"$destdir$main::imscpConfig{'ROOT_DIR'}/gui/data/persistent/ispLogos", \$stdout, \$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	# Save software (older path ./gui/data/softwares) to new path (./gui/data/persistent/softwares)
	if(-d "$main::imscpConfig{'ROOT_DIR'}/gui/data/softwares") {
		$rs = execute(
			"$main::imscpConfig{'CMD_CP'} -fRT $main::imscpConfig{'ROOT_DIR'}/gui/data/softwares " .
			"$destdir$main::imscpConfig{'ROOT_DIR'}/gui/data/persistent/softwares", \$stdout, \$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	# Save GUI plugins
	if(-d "$main::imscpConfig{'ROOT_DIR'}/gui/plugins") {
		$rs = execute(
			"$main::imscpConfig{'CMD_CP'} -fRT $main::imscpConfig{'ROOT_DIR'}/gui/plugins " .
			"$destdir$main::imscpConfig{'ROOT_DIR'}/gui/plugins",
			\$stdout, \$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	# Save backend plugins
	if(-d "$main::imscpConfig{'ENGINE_ROOT_DIR'}/Plugins") {
		$rs = execute(
			"$main::imscpConfig{'CMD_CP'} -fRT $main::imscpConfig{'ENGINE_ROOT_DIR'}/Plugins " .
			"$destdir$main::imscpConfig{'ENGINE_ROOT_DIR'}/Plugins",
			\$stdout, \$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	0;
}

=item installTmp()

 Install files from build directory on file system.

 Return int - 0 on success, other on failure

=cut

sub installTmp
{
	my $rs = 0;
	my ($stdout, $stderr);
	my $tmpDir = $main::{'INST_PREF'};

	# i-MSCP daemon must be stopped before changing any file on the files system
	if(-x "$main::imscpConfig{'INIT_SCRIPTS_DIR'}/$main::imscpConfig{'IMSCP_DAEMON_SNAME'}") {
		$rs = execute(
			"$main::imscpConfig{'SERVICE_MNGR'} $main::imscpConfig{'IMSCP_DAEMON_SNAME'} stop 2>/dev/null", \$stdout
		);
		debug($stdout) if $stdout;
		error('Unable to stop i-MSCP Daemon') if $rs > 1;
		return $rs if $rs > 1;
	}

	# Process cleanup to avoid any security risks and conflicts
	$rs = execute(
		"$main::imscpConfig{'CMD_RM'} -fR " .
		"$main::imscpConfig{'ROOT_DIR'}/daemon " .
		"$main::imscpConfig{'ROOT_DIR'}/engine " .
		"$main::imscpConfig{'ROOT_DIR'}/gui ",
		\$stdout, \$stderr
	);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	# Install new i-MSCP files on the files system
	$rs = execute("$main::imscpConfig{'CMD_CP'} -fR $tmpDir/* /", \$stdout, \$stderr);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	0;
}

=item

 Delete build directory.

 Return int - 0 on success, other on failure

=cut

sub removeTmp
{
	my ($stdout, $stderr);

	if($main::{'INST_PREF'} && -d $main::{'INST_PREF'}) {
		my $rs = execute("$main::imscpConfig{'CMD_RM'} -fR $main::{'INST_PREF'}", \$stdout, \$stderr);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	0;
}

=item checkCommandAvailability()

 Check availability of the given command.

 Return int - 0 if the given command is available, 1 othewise

=cut

sub checkCommandAvailability($)
{
	my $command = shift;
	my ($stdout, $stderr);

	my $rs = execute("$main::imscpConfig{'CMD_WHICH'} $command", \$stdout, \$stderr);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;

	$rs;
}

=back

=head1 PRIVATES FUNCTIONS

=over 4

=item _processXmlFile()

 Process an install.xml file or distribution layout.xml file.

 Return int - 0 on success, other on failure ; A fatal error is raised in case a variable cannot be exported

=cut

sub _processXmlFile($)
{
	my $file = shift;

	unless(-f $file) {
		error("$file doesn't exist");
		return 1;
	}

	# Loading XML::Simple package
	eval "use XML::Simple; 1";
	fatal('Unable to load the XML::Simple perl module') if $@;

	# Creating XML object
	my $xml = XML::Simple->new('ForceArray' => 1, 'ForceContent' => 1);

	# Reading XML file
	my $data = eval { $xml->XMLin($file, 'VarAttr' => 'export') };

	if ($@) {
		error($@);
		return 1;
	}

	my $rs = 0;

	# Process xml 'folders' nodes if any
	for(@{$data->{'folders'}}) {
		$_->{'content'} = _expandVars($_->{'content'}) if exists $_->{'content'};
		$main::{$_->{'export'}} = $_->{'content'} if $_->{'export'};
		$rs = _processFolder($_) if exists $_->{'content'};
		return $rs if $rs;
	}

	# Process xml 'copy_config' nodes if any
	for(@{$data->{'copy_config'}}) {
		$_->{'content'} = _expandVars($_->{'content'}) if exists $_->{'content'};
		$rs = _copyConfig($_) if exists $_->{'content'};
		return $rs if $rs;
	}

	# Process xml 'copy' nodes if any
	for(@{$data->{'copy'}}) {
		$_->{'content'} = _expandVars($_->{'content'}) if exists $_->{'content'};
		$rs = _copy($_) if exists $_->{'content'};
		return $rs if $rs;
	}

	# Process xml 'create_file' nodes if any
	for(@{$data->{'create_file'}}) {
		$_->{'content'} = _expandVars($_->{'content'}) if exists $_->{'content'};
		$rs = _createFile($_) if exists $_->{'content'};
		return $rs if $rs;
	}

	# Process xml 'chmod_file' nodes if any
	for(@{$data->{'chmod_file'}}) {
		$_->{'content'} = _expandVars($_->{'content'}) if exists $_->{'content'};
		$rs = _chmodFile($_) if $_->{'content'};
		return $rs if $rs;
	}

	# Process xml 'chmod_file' nodes if any
	for(@{$data->{'chown_file'}}) {
		$_->{'content'} = _expandVars($_->{'content'}) if exists $_->{'content'};
		$rs = _chownFile($_) if exists $_->{'content'};
		return $rs if $rs;
	}

	0;
}

=item _expandVars()

 Expand variables in the given string.

 Return string

=cut

sub _expandVars
{
	my $string = shift || '';

	debug("Input: $string");

	for($string =~ /\$\{([^\}]+)\}/g) {
		if(exists $main::{$_}) {
			$string =~ s/\$\{$_\}/$main::{$_}/g;
		} elsif(exists $main::imscpConfig{$_}) {
			$string =~ s/\$\{$_\}/$main::imscpConfig{$_}/g;
		} else {
			fatal("Unable to expand variable \${$_}. Variable not found.");
		}
	}

	debug("Output: $string");

	$string;
}

=item _processFolder()

 Process a 'folder' node from an install.xml file.

 Process the xml 'folder' node by creating the described directory.

 Return int - 0 on success, other on failure

=cut


sub _processFolder
{
	my $data = shift;

	my $dir = iMSCP::Dir->new('dirname' => $data->{'content'});

	# Needed to be sure to not keep any file from a previous build that has failed
	if(defined $main::{'INST_PREF'} && $main::{'INST_PREF'} eq $data->{'content'} && -d $data->{'content'}) {
		my $rs = $dir->remove();
		return $rs if $rs;
	}

	debug("Creating $dir->{'dirname'} directory");

	my $options = {};

	$options->{'mode'} = oct($data->{'mode'}) if exists $data->{'mode'};
	$options->{'user'} = _expandVars($data->{'owner'}) if exists $data->{'owner'};
	$options->{'group'} = _expandVars($data->{'group'}) if exists $data->{'group'};

	$dir->make($options);
}

=item

 Process a 'copy_config' node from an install.xml file.

 Return int - 0 on success, other on failure

=cut

sub _copyConfig
{
	my $data = shift;

	my @parts = split '/', $data->{'content'};
	my $name = pop(@parts);
	my $path = join '/', @parts;
	my $distribution = lc(iMSCP::LsbRelease->getInstance()->getId(1));

	my $alternativeFolder = getcwd();
	$alternativeFolder =~ s/$distribution/debian/;

	my $source = -f $name ? $name : "$alternativeFolder/$name";

	my ($rs, $stdout, $stderr);

	if(-d $source) {
		debug("Copying $source directory in $path");
		$rs = execute("$main::imscpConfig{'CMD_CP'} -fR $source $path", \$stdout, \$stderr);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	} else {
		debug("Copying $source file in $path");
		$rs = execute("$main::imscpConfig{'CMD_CP'} -f $source $path", \$stdout, \$stderr);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	if($data->{'user'} || $data->{'group'} || $data->{'mode'}) {
		my $filename = -e "$path/$name" ? "$path/$name" : $path;

		my $file = iMSCP::File->new('filename' => $filename);
		$rs = $file->mode(oct($data->{'mode'})) if $data->{'mode'};
		return $rs if $rs;

		$rs = $file->owner(
			$data->{'user'} ? _expandVars($data->{'user'}) : -1,
			$data->{'group'} ? _expandVars($data->{'group'}) : -1
		) if $data->{'user'} || $data->{'group'};
		return $rs if $rs;
	}

	0;
}

=item

 Process the 'copy' node from an install.xml file.

 Return int - 0 on success, other on failure

=cut

sub _copy
{
	my $data = shift;
	my @parts = split '/', $data->{'content'};
	my $name = pop(@parts);
	my $path = join '/', @parts;

	debug("Copy recursive $name in $path");

	my ($stdout, $stderr);
	my $rs = execute("$main::imscpConfig{'CMD_CP'} -fR $name $path", \$stdout, \$stderr);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	if($data->{'user'} || $data->{'group'} || $data->{'mode'}) {
		my $filename = -e "$path/$name" ? "$path/$name" : $path;

		my $file = iMSCP::File->new('filename' => $filename);
		$rs = $file->mode(oct($data->{'mode'})) if $data->{'mode'};
		return $rs if $rs;

		$rs = $file->owner(
			$data->{'user'} ? _expandVars($data->{'user'}) : -1,
			$data->{'group'} ? _expandVars($data->{'group'}) : -1
		) if $data->{'user'} || $data->{'group'};
		return $rs if $rs;
	}

	0;
}

=item _createFile()

 Create a file.

 Return int - 0 on success, other on failure

=cut

sub _createFile
{
	my $data = shift;

	iMSCP::File->new('filename' => $data->{'content'})->save();
}

=item _chownFile()

 Change file/directory owner and/or group recursively.

 Return int - 0 on success, other on failure

=cut

sub _chownFile
{
	my $data = shift;

	if($data->{'owner'} && $data->{'group'}) {
		my ($stdout, $stderr);
		my $rs = execute(
			"$main::imscpConfig{'CMD_CHOWN'} $data->{'owner'}:$data->{'group'} $data->{'content'}",
			\$stdout, \$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	0;
}

=item _chmodFile()

 Process chmod_file from an install.xml file.

 Return int - 0 on success, other on failure

=cut

sub _chmodFile
{
	debug('Starting...');

	my $data = shift;

	if(exists $data->{'mode'}) {
		my ($stdout, $stderr);
		my $rs = execute("$main::imscpConfig{'CMD_CHMOD'} $data->{'mode'} $data->{'content'}", \$stdout, \$stderr);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	debug('Ending...');

	0;
}

=item _getDistroAdapter()

 Return distro autoinstaller adapter instance.

 Return autoinstaller::Adapter::Abstract
 TODO check that adapter is an instance of autoinstaller::Adapter::Abstract

=cut

sub _getDistroAdapter
{
	if(! defined $main::autoinstallerAdapter) {
		my $distribution = iMSCP::LsbRelease->getInstance()->getId(1);
		my $file = "$FindBin::Bin/autoinstaller/Adapter/$distribution.pm";
		my $adapterClass = "autoinstaller::Adapter::$distribution";

		if(-f $file) {
			require $file;
			$main::autoinstallerAdapter = $adapterClass->getInstance();
		} else {
			fatal('Distro autoinstaller adapter not found');
		}
	}

	$main::autoinstallerAdapter;
}

=back

=head1 AUTHORS

 Daniel Andreca <sci2tech@gmail.com>
 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
