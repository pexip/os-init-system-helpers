#!perl
# vim:ts=4:sw=4:et

use strict;
use warnings;
use Test::More;
use Test::Deep qw(:preload cmp_bag);
use File::Temp qw(tempfile tempdir); # in core since perl 5.6.1
use File::Path qw(make_path); # in core since Perl 5.001
use File::Basename; # in core since Perl 5
use FindBin; # in core since Perl 5.00307

use lib "$FindBin::Bin/.";
use helpers;

test_setup();

my $dpkg_root = $ENV{DPKG_ROOT} // '';

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Create two unit files with random names; they refer to each other (Also=).┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

my ($fh1, $random_unit1) = tempfile('unitXXXXX',
    SUFFIX => '.service',
    TMPDIR => 1,
    UNLINK => 1);
close($fh1);
$random_unit1 = basename($random_unit1);

my ($fh2, $random_unit2) = tempfile('unitXXXXX',
    SUFFIX => '.service',
    TMPDIR => 1,
    UNLINK => 1);
close($fh2);
$random_unit2 = basename($random_unit2);

my $servicefile_path1 = "$dpkg_root/lib/systemd/system/$random_unit1";
my $servicefile_path2 = "$dpkg_root/lib/systemd/system/$random_unit2";
make_path("$dpkg_root/lib/systemd/system");
open($fh1, '>', $servicefile_path1);
print $fh1 <<EOT;
[Unit]
Description=test unit

[Service]
ExecStart=/bin/sleep 1

[Install]
WantedBy=multi-user.target
Also=$random_unit2
EOT
close($fh1);

open($fh2, '>', $servicefile_path2);
print $fh2 <<EOT;
[Unit]
Description=test unit

[Service]
ExecStart=/bin/sleep 1

[Install]
WantedBy=multi-user.target
Alias=alias2.service
Also=$random_unit1
EOT
close($fh2);

isnt_enabled($random_unit1);
isnt_enabled($random_unit2);
isnt_debian_installed($random_unit1);
isnt_debian_installed($random_unit2);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “enable” creates all symlinks.                                     ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

unless ($ENV{'TEST_ON_REAL_SYSTEM'}) {
    # This might already exist if we don't start from a fresh directory
    ok(! -d "$dpkg_root/etc/systemd/system/multi-user.target.wants",
       'multi-user.target.wants does not exist yet');
}

my $retval = dsh('enable', $random_unit1);
my %links = map { (basename($_), $dpkg_root . readlink($_)) }
    ("$dpkg_root/etc/systemd/system/multi-user.target.wants/$random_unit1",
     "$dpkg_root/etc/systemd/system/multi-user.target.wants/$random_unit2");
is_deeply(
    \%links,
    {
        $random_unit1 => $servicefile_path1,
        $random_unit2 => $servicefile_path2,
    },
    'All expected links present');

my $alias_path = "$dpkg_root/etc/systemd/system/alias2.service";
ok(-l $alias_path, 'alias created');
is($dpkg_root . readlink($alias_path), $servicefile_path2,
    'alias points to the correct service file');

cmp_bag(
    [ state_file_entries("$dpkg_root/var/lib/systemd/deb-systemd-helper-enabled/$random_unit1.dsh-also") ],
    [ "$dpkg_root/etc/systemd/system/multi-user.target.wants/$random_unit1",
      "$dpkg_root/etc/systemd/system/multi-user.target.wants/$random_unit2",
      "$dpkg_root/etc/systemd/system/alias2.service" ],
    'state file updated');

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “is-enabled” now returns true.                                     ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

is_enabled($random_unit1);
is_enabled($random_unit2);
is_debian_installed($random_unit1);

# $random_unit2 was only enabled _because of_ $random_unit1’s Also= statement
# and thus does not have its own state file.
isnt_debian_installed($random_unit2);

# TODO: cleanup tests?

done_testing;
