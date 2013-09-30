#!/usr/bin/env perl
#
# This script does the following:
#
# 1. Find the latest releng usnic build
# 2. Exit if a Bright softwareimage already exists for this build
# 3. Create a Bright softwareimage for this build, cloning from a
#    specified source softwareimage.  Set some reasonable defaults on
#    this softwareimage (e.g., copy root ssh keys around, etc.).
# 4. Install the USNIC RPMs on this softwareimage
# 5. Recreate the softwareimage ramdisk (so that it gets the right new
#    enic driver).
# 6. Create two categories:
# 6a. usnic-<build_number>: This will be in the SLURM
#     "mtt-usnic-<build_number>" partition.
# 6a. usnic-<build_number>-noslurm: This will not be in a SLURM partition.
# 7. Add a modulefile to the image for adding OMPI to the PATH/MANPATH/etc.
#

use strict;

use Cwd;
use File::Basename;
use Data::Dumper;

#########################################################################

my $vds_url_base = "http://savbu-swucs-bld3.cisco.com/palo_enic_linux_esx_main-builds/svn_latest/";
my $enic_vds_subdir = "Palo/drivers/linux/RHEL/RHEL_6.4/Ethernet";

my $usnic_builds = "/auto/savbu-releng/buildsa/builds/ucs-b-series/usNIC-builds";
my $usnic_subdir = "latest/linux/RHEL/RHEL_6.4";

#########################################################################

my $who = `whoami`;
chomp($who);
if ($who ne "root") {
    print "Must be run as root\n";
    exit(1);
}

#########################################################################

my $src_image = $ARGV[0];
if ($src_image eq "") {
    print "Must specify a source image as argv[1]\n";
    exit(1);
}

if (! -d "/cm/images/$src_image") {
    print "Source image $src_image does not exist\n";
    exit(1);
}

#########################################################################

my $enic_file;

sub abort {
    my $msg = shift;

    unlink($enic_file)
        if (defined($enic_file));

    print STDERR $msg;
    exit(1);
}

#########################################################################

# Find the latest enic build

sub find_latest_enic_build {
    my $name = shift;
    my $files = shift;

    chdir("/tmp");

    # Find the enic image directory number
    my $file = "enic-image-$$.html";
    my $ret = system("wget -q $vds_url_base -O $file");
    abort "Can't wget enic image number"
        if (0 != $ret);

    my $ver = 0;
    my $enic_image_dir;
    open(IN, $file) || abort "Can't open enic html file";
    while (<IN>) {
        if (m/<a href="(Images\.)(\d+)\/">/) {
            $ver = $2;
            $enic_image_dir = "$1$2";
        }
    }
    close(IN);
    unlink($file);

    abort "Did not find enic image number"
        if (!defined($enic_image_dir));

    # Now get the enic RPM filename
    $file = "enic-filename-$$.html";
    $ret = system("wget -q $vds_url_base/$enic_image_dir/$enic_vds_subdir/ -O $file");
    abort "Can't wget enic file name"
        if (0 != $ret);

    open(IN, $file) || abort "Can't open enic html file";
    my $enic_rpm_filename;
    while (<IN>) {
        if (m/<a href="(kmod-enic-.*\.rpm)">/) {
            $enic_rpm_filename = $1;
        }
    }
    close(IN);
    unlink($file);

    abort "Did not find enic RPM name"
        if (!defined($enic_rpm_filename));
    unlink($enic_rpm_filename);

    # Now download the enic RPM
    $ret = system("wget -q $vds_url_base/$enic_image_dir/$enic_vds_subdir/$enic_rpm_filename");
    abort "Can't wget enic file name"
        if (0 != $ret);

    print "Most recent enic RPM: $enic_rpm_filename\n";
    $enic_file = getcwd() . "/$enic_rpm_filename";
    push(@{$files}, $enic_file);
}

print "\n### Finding latest enic build...\n";

my @rpms_to_install;
find_latest_enic_build("kmod-enic", \@rpms_to_install);

#########################################################################

# Find the latest usnic build
print "\n### Finding latest USNIC releng build...\n";
abort("Could not find USNIC builds directory\n($usnic_builds)\n")
    if (! -d $usnic_builds);

chdir("$usnic_builds/latest");
my $p = cwd();
my $build_id = basename($p);
print "    Found $build_id\n";

my $usnic_pkg_dir = "$usnic_builds/$usnic_subdir";
chdir($usnic_pkg_dir);

my @dirlist;
sub find_latest_usnic_build {
    my $name = shift;
    my $files = shift;

    # Read the directory once
    if (!defined(@dirlist)) {
        opendir(DIR, $usnic_pkg_dir) || abort "can't opendir $usnic_pkg_dir: $!";
        @dirlist = grep { /x86_64.rpm$/ && -f "$usnic_pkg_dir/$_" } readdir(DIR);
        closedir(DIR);
    }

    # Find the latest for this file
    my ($winner, $a, $b, $c, $d, $r);
    foreach my $f (@dirlist) {
        if ($f =~ m/$name-\d/) {
            # Parse out the RPM versions
            my $out = `rpm -qip $usnic_pkg_dir/$f`;
            $out =~ m/Version\s+: ([\d\.]+)\s/;
            my $version = $1;
            my ($aa, $bb, $cc, $dd) = split(/\./, $version);
            $out =~ m/Release\s+: (\d+)/;
            my $rr = $1;

            if ($aa > $a ||
                ($aa == $a && $bb > $b) ||
                ($aa == $a && $bb == $b && $cc > $c) ||
                ($aa == $a && $bb == $b && $cc == $c && $dd > $d) ||
                ($aa == $a && $bb == $b && $cc == $c && $dd == $d && $rr > $r)) {
                $winner = $f;
                $a = $aa;
                $b = $bb;
                $c = $cc;
                $d = $dd;
                $r = $rr;
            }
        }
    }

    if (length($winner) > 0) {
        print "Most recent $name: $winner\n";
        push(@{$files}, "$usnic_pkg_dir/$winner");
    } else {
        print "No winner found for $name!\n";
    }
}

# Find the latest usnic software
find_latest_usnic_build("kmod-usnic_verbs", \@rpms_to_install);
find_latest_usnic_build("libusnic_verbs", \@rpms_to_install);
find_latest_usnic_build("openmpi-cisco", \@rpms_to_install);
find_latest_usnic_build("openmpi-cisco-debuginfo", \@rpms_to_install);
find_latest_usnic_build("usnic_tools", \@rpms_to_install);

#########################################################################

#my $dest_image = "usnic-$build_id";
my $dest_image = "usnic-$build_id";
if (-d "/cm/images/$dest_image") {
    print "Bright image $dest_image already exists
Exiting without doing anything\n";
    # Not an error
    unlink($enic_file);
    exit(0);
}

print "\n### Making new Bright software image for latest USNIC build:
    Source image:      $src_image
    Destination image: $dest_image\n";

# Put cmsh in the path
$ENV{PATH} .= ":/cm/local/apps/cmd/bin";

# Clone the image
print "\n### Cloning Bright image...\n";
my @cmd = qw/cmsh -x -c/;
push(@cmd, "softwareimage; clone $src_image $dest_image; set kernelparameters \"rdblacklist=nouveau intel_iommu=on\"; commit");
my $ret = system(@cmd);
abort("cmsh failed to clone image: $?\n")
    if ($ret != 0);

sleep(600);

# Setup root/slurm privs
print "\n### Setting root, SLURM, and USNIC cluster defaults...\n";
chdir("/cm/images");
system("rm -f $dest_image/root/.ssh/*");
system("cp -f default-image/root/.ssh/* $dest_image/root/.ssh");
system("cp -f default-image/etc/ssh/* $dest_image/etc/ssh");
system("cp -f default-image/etc/munge/* $dest_image/etc/munge");
system("cp -f default-image/etc/profile.d/*savbu-usnic* $dest_image/etc/profile.d");
system("chroot /cm/images/$dest_image chkconfig rdma on");

# Install latest enic USNIC software
print "\n### Installing RPMs into image...\n";
my $str = "yum install -y --installroot=/cm/images/$dest_image " . join(" ", @rpms_to_install);
$ret = system($str);
abort("failed to yum install RPMs\n")
    if ($ret != 0);

# Delete the enic RPM we downloaded
unlink($enic_file);

# Ensure the "rdma" service is enabled
$ret = system("/usr/sbin/chroot /cm/images/$dest_image /sbin/chkconfig rdma on");
abort("failed to enable rdma service in image\n")
    if ($ret != 0);

# (Re)Create the ramdisk (with the new enic.ko)
print "\n### (Re)Creating ramdisk...\n";
@cmd = qw/cmsh -x -c/;
push(@cmd, "softwareimage; use $dest_image; createramdisk");
$ret = system(@cmd);
abort("cmsh failed to recreate ramdisk\n")
    if ($ret != 0);

# Create a category with this softwareimage
print "\n### Creating Bright category with this image...\n";
@cmd = qw/cmsh -x -c/;
push(@cmd, "category; clone default $dest_image; set softwareimage $dest_image; roles; use slurmclient; set sockets 2; set corespersocket 8; set threadspercore 1; set queues mtt-$dest_image; exit; exit; fsmounts; add /opt/intel; set device \$localnfsserver:/opt/intel; set filesystem nfs; commit; add /opt/repos; set device \$localnfsserver:/opt/repos; set filesystem nfs; commit; jobqueue; add mtt-$dest_image; commit");
$ret = system(@cmd);
abort("cmsh failed to create category\n")
    if ($ret != 0);

# Create a category with this softwareimage that won't be in slurm
print "\n### Creating Bright noslurm category with this image...\n";
@cmd = qw/cmsh -x -c/;
push(@cmd, "category; clone $dest_image $dest_image-noslurm; roles; unassign slurmclient; exit; commit");
$ret = system(@cmd);
abort("cmsh failed to create noslurm category\n")
    if ($ret != 0);

# Make a modulefile in the software image for the Open MPI that is on
# this image
chdir("/cm/images/$dest_image");
my $dir = "/cm/images/$dest_image/cm/local/modulefiles/cisco/openmpi";
system("mkdir -p $dir");
open(M, ">$dir/usnic") || abort "Can't open $dir/usnic";
print M "#%Module -*- tcl -*-
#
# Cisco Open MPI RPM modulefile
#

proc ModulesHelp { } {
   puts stderr \"\\tThis module adds Cisco's USNIC Open MPI to the environment.\"
}

module-whatis   \"Sets up the Cisco USNIC Open MPI environment\"

set ompi_root /opt/cisco/openmpi

append-path MANPATH \$ompi_root/man
append-path LD_LIBRARY_PATH \$ompi_root/lib
append-path PATH \$ompi_root/bin";
close(M);

print "\n### Done!

----------------------------------------------------------------------------
You can go into cmsh and assign category '$dest_image' to nodes.

module load cmsh
cmsh
device

# Set the category on a bunch of devices
foreach -n nodeXXX..nodeYYY (set category $dest_image; commit)

# Reboot the nodes to get the new category/image to take effect
reboot -n nodeXXX..nodeYYY
# Or you might need to power them on, either by allocing them in SLURM, or
power -n nodeXXX..nodeYYY on

And you can \"module load cisco/openmpi/usnic\" on the target machine
to load Open MPI into your PATH/etc.

quit
----------------------------------------------------------------------------
";
exit(0);
