#!perl
# vim:ts=4:sw=4:et

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile tempdir); # in core since perl 5.6.1
use File::Path qw(make_path); # in core since Perl 5.001
use File::Basename; # in core since Perl 5
use FindBin; # in core since Perl 5.00307

use lib "$FindBin::Bin/.";
use helpers;

test_setup();

my $dpkg_root = $ENV{DPKG_ROOT} // '';

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “is-enabled” is not true for a random, non-existing unit file.     ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

my ($fh, $random_unit) = tempfile('unit\x2dXXXXX',
    SUFFIX => '.service',
    TMPDIR => 1,
    UNLINK => 1);
close($fh);
$random_unit = basename($random_unit);

isnt_enabled($random_unit);
isnt_debian_installed($random_unit);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “is-enabled” is not true for a random, existing unit file.         ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

my $servicefile_path = "$dpkg_root/lib/systemd/system/$random_unit";
make_path("$dpkg_root/lib/systemd/system");
open($fh, '>', $servicefile_path);
print $fh <<'EOT';
[Unit]
Description=test unit

[Service]
ExecStart=/bin/sleep 1

[Install]
WantedBy=multi-user.target
EOT
close($fh);

isnt_enabled($random_unit);
isnt_debian_installed($random_unit);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “enable” creates the requested symlinks.                           ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

unless ($ENV{'TEST_ON_REAL_SYSTEM'}) {
    # This might exist if we don't start from a fresh directory
    ok(! -d "$dpkg_root/etc/systemd/system/multi-user.target.wants",
       'multi-user.target.wants does not exist yet');
}

my $retval = dsh('enable', $random_unit);
is($retval, 0, "enable command succeeded");
my $symlink_path = "$dpkg_root/etc/systemd/system/multi-user.target.wants/$random_unit";
ok(-l $symlink_path, "$random_unit was enabled");
is($dpkg_root . readlink($symlink_path), $servicefile_path,
    "symlink points to $servicefile_path");

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “is-enabled” now returns true.                                     ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

is_enabled($random_unit);
is_debian_installed($random_unit);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify deleting the symlinks and running “enable” again does not          ┃
# ┃ re-create the symlinks.                                                   ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

unlink($symlink_path);
ok(! -l $symlink_path, 'symlink deleted');
isnt_enabled($random_unit);
is_debian_installed($random_unit);

$retval = dsh('enable', $random_unit);
is($retval, 0, "enable command succeeded");

isnt_enabled($random_unit);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “disable” when purging deletes the statefile.                      ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

my $statefile = "$dpkg_root/var/lib/systemd/deb-systemd-helper-enabled/$random_unit.dsh-also";

ok(-f $statefile, 'state file exists');

$ENV{'_DEB_SYSTEMD_HELPER_PURGE'} = '1';
$retval = dsh('disable', $random_unit);
delete $ENV{'_DEB_SYSTEMD_HELPER_PURGE'};
is($retval, 0, "disable command succeeded");
ok(! -f $statefile, 'state file does not exist anymore after purging');
isnt_debian_installed($random_unit);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “enable” after purging does re-create the symlinks.                ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

ok(! -l $symlink_path, 'symlink does not exist yet');
isnt_enabled($random_unit);

$retval = dsh('enable', $random_unit);
is($retval, 0, "enable command succeeded");

is_enabled($random_unit);
is_debian_installed($random_unit);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “disable” removes the symlinks.                                    ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

$ENV{'_DEB_SYSTEMD_HELPER_PURGE'} = '1';
$retval = dsh('disable', $random_unit);
delete $ENV{'_DEB_SYSTEMD_HELPER_PURGE'};
is($retval, 0, "disable command succeeded");

isnt_enabled($random_unit);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “enable” after purging does re-create the symlinks.                ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

ok(! -l $symlink_path, 'symlink does not exist yet');
isnt_enabled($random_unit);

$retval = dsh('enable', $random_unit);
is($retval, 0, "enable command succeeded");

is_enabled($random_unit);
is_debian_installed($random_unit);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify the “purge” verb works.                                            ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

$retval = dsh('purge', $random_unit);
is($retval, 0, "purge command succeeded");

isnt_enabled($random_unit);
isnt_debian_installed($random_unit);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “enable” after purging does re-create the symlinks.                ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

ok(! -l $symlink_path, 'symlink does not exist yet');
isnt_enabled($random_unit);

$retval = dsh('enable', $random_unit);
is($retval, 0, "enable command succeeded");

is_enabled($random_unit);
is_debian_installed($random_unit);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “mask” (when enabled) results in the symlink pointing to /dev/null ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

my $mask_path = "$dpkg_root/etc/systemd/system/$random_unit";
ok(! -l $mask_path, 'mask link does not exist yet');

$retval = dsh('mask', $random_unit);
is($retval, 0, "mask command succeeded");
ok(-l $mask_path, 'mask link exists');
is(readlink($mask_path), '/dev/null', 'service masked');

$retval = dsh('unmask', $random_unit);
is($retval, 0, "unmask command succeeded");
ok(! -e $mask_path, 'mask link does not exist anymore');

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “mask” (when disabled) works the same way                          ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

$retval = dsh('disable', $random_unit);
is($retval, 0, "disable command succeeded");
ok(! -e $symlink_path, 'symlink no longer exists');

$retval = dsh('mask', $random_unit);
is($retval, 0, "mask command succeeded");
ok(-l $mask_path, 'mask link exists');
is(readlink($mask_path), '/dev/null', 'service masked');

$retval = dsh('unmask', $random_unit);
is($retval, 0, "unmask command succeeded");
ok(! -e $mask_path, 'symlink no longer exists');

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “mask”/unmask don’t do anything when the user already masked.      ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

ok(! -l $mask_path, 'mask link does not exist yet');
symlink('/dev/null', $mask_path);
ok(-l $mask_path, 'mask link exists');
is(readlink($mask_path), '/dev/null', 'service masked');

$retval = dsh('mask', $random_unit);
is($retval, 0, "mask command succeeded");
ok(-l $mask_path, 'mask link exists');
is(readlink($mask_path), '/dev/null', 'service still masked');

$retval = dsh('unmask', $random_unit);
is($retval, 0, "unmask command succeeded");
ok(-l $mask_path, 'mask link exists');
is(readlink($mask_path), '/dev/null', 'service still masked');

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify “mask”/unmask don’t do anything when the user copied the .service. ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

unlink($mask_path);

open($fh, '>', $mask_path);
print $fh <<'EOT';
[Unit]
Description=test unit

[Service]
ExecStart=/bin/sleep 1

[Install]
WantedBy=multi-user.target
EOT
close($fh);

ok(-e $mask_path, 'local service file exists');
ok(! -l $mask_path, 'local service file is not a symlink');

$retval = dsh('mask', $random_unit);
isnt($retval, -1, 'deb-systemd-helper could be executed');
ok(!($retval & 127), 'deb-systemd-helper did not exit due to a signal');
is($retval >> 8, 0, 'deb-systemd-helper exited with exit code 0');
ok(-e $mask_path, 'local service file still exists');
ok(! -l $mask_path, 'local service file is still not a symlink');

$retval = dsh('unmask', $random_unit);
isnt($retval, -1, 'deb-systemd-helper could be executed');
ok(!($retval & 127), 'deb-systemd-helper did not exit due to a signal');
is($retval >> 8, 0, 'deb-systemd-helper exited with exit code 0');
ok(-e $mask_path, 'local service file still exists');
ok(! -l $mask_path, 'local service file is still not a symlink');

unlink($mask_path);

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify Alias= handling.                                                   ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

$retval = dsh('purge', $random_unit);
is($retval, 0, "purge command succeeded");

open($fh, '>', $servicefile_path);
print $fh <<'EOT';
[Unit]
Description=test unit

[Service]
ExecStart=/bin/sleep 1

[Install]
WantedBy=multi-user.target
Alias=foo\x2dtest.service
EOT
close($fh);

isnt_enabled($random_unit);
isnt_enabled('foo\x2dtest.service');
my $alias_path = $dpkg_root . '/etc/systemd/system/foo\x2dtest.service';
ok(! -l $alias_path, 'alias link does not exist yet');
$retval = dsh('enable', $random_unit);
is($retval, 0, "enable command succeeded");
is($dpkg_root . readlink($alias_path), $servicefile_path, 'correct alias link');
is_enabled($random_unit);
ok(! -l $mask_path, 'mask link does not exist yet');

$retval = dsh('mask', $random_unit);
is($retval, 0, "mask command succeeded");
is($dpkg_root . readlink($alias_path), $servicefile_path, 'correct alias link');
is(readlink($mask_path), '/dev/null', 'service masked');

$retval = dsh('unmask', $random_unit);
is($retval, 0, "unmask command succeeded");
is($dpkg_root . readlink($alias_path), $servicefile_path, 'correct alias link');
ok(! -l $mask_path, 'mask link does not exist any more');

$retval = dsh('disable', $random_unit);
isnt_enabled($random_unit);
ok(! -l $alias_path, 'alias link does not exist any more');

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify Alias/mask with removed package (as in postrm)                     ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

$retval = dsh('purge', $random_unit);
is($retval, 0, "purge command succeeded");
$retval = dsh('enable', $random_unit);
is($retval, 0, "enable command succeeded");
is($dpkg_root . readlink($alias_path), $servicefile_path, 'correct alias link');

unlink($servicefile_path);

$retval = dsh('mask', $random_unit);
is($retval, 0, "mask command succeeded with uninstalled unit");
is($dpkg_root . readlink($alias_path), $servicefile_path, 'correct alias link');
is(readlink($mask_path), '/dev/null', 'service masked');

$retval = dsh('purge', $random_unit);
is($retval, 0, "purge command succeeded with uninstalled unit");
ok(! -l $alias_path, 'alias link does not exist any more');
is(readlink($mask_path), '/dev/null', 'service masked');

$retval = dsh('unmask', $random_unit);
is($retval, 0, "unmask command succeeded with uninstalled unit");
ok(! -l $mask_path, 'mask link does not exist any more');

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify Alias= to the same unit name                                       ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

open($fh, '>', $servicefile_path);
print $fh <<"EOT";
[Unit]
Description=test unit

[Service]
ExecStart=/bin/sleep 1

[Install]
WantedBy=multi-user.target
Alias=$random_unit
EOT
close($fh);

isnt_enabled($random_unit);
isnt_enabled('foo\x2dtest.service');
# note that in this case $alias_path and $mask_path are identical
$retval = dsh('enable', $random_unit);
is($retval, 0, "enable command succeeded");
is_enabled($random_unit);
# systemctl enable does create the alias link even if it's not needed
#ok(! -l $mask_path, 'mask link does not exist yet');

unlink($servicefile_path);

$retval = dsh('mask', $random_unit);
is($retval, 0, "mask command succeeded");
is(readlink($mask_path), '/dev/null', 'service masked');

$retval = dsh('unmask', $random_unit);
is($retval, 0, "unmask command succeeded");
ok(! -l $mask_path, 'mask link does not exist any more');

$retval = dsh('purge', $random_unit);
isnt_enabled($random_unit);
ok(! -l $mask_path, 'mask link does not exist any more');

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify WantedBy and Alias with template unit with DefaultInstance.        ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

($fh, $servicefile_path) = tempfile('unit\x2dXXXXX',
    DIR    => "$dpkg_root/lib/systemd/system",
    SUFFIX => '@.service',
    UNLINK => 1);
print $fh <<'EOT';
[Unit]
Description=template test unit

[Service]
ExecStart=/bin/sleep 1

[Install]
Alias=foo\x2dtest@.service
Alias=foo\x2dbar@baz.service
WantedBy=multi-user.target
DefaultInstance=instance\x2d
EOT
close($fh);

$random_unit = basename($servicefile_path);
my $random_instance = $random_unit;
$random_instance =~ s/^(.*\@)(\.\w+)$/$1instance\\x2d$2/;

isnt_enabled($random_unit);
isnt_enabled('foo\x2dtest@.service');
isnt_enabled('foo\x2dtest@instance\x2d.service');
isnt_enabled('foo\x2dbar@baz.service');
isnt_enabled('foo\x2dbar@instance\x2d.service');

my $template_alias_path = $dpkg_root . '/etc/systemd/system/foo\x2dtest@.service';
my $instance_alias_path = $dpkg_root . '/etc/systemd/system/foo\x2dbar@baz.service';
my $template_wanted_path = "$dpkg_root/etc/systemd/system/multi-user.target.wants/$random_unit";
my $instance_wanted_path = "$dpkg_root/etc/systemd/system/multi-user.target.wants/$random_instance";
ok(! -l $template_alias_path, 'template alias link does not exist yet');
ok(! -l $instance_alias_path, 'instance alias link does not exist yet');
ok(! -l $template_wanted_path, 'template wanted link does not exist yet');
ok(! -l $instance_wanted_path, 'instance wanted link does not exist yet');
$retval = dsh('enable', $random_unit);
is($retval, 0, "enable command succeeded");
is($dpkg_root . readlink($template_alias_path), $servicefile_path, 'correct template alias link');
is($dpkg_root . readlink($instance_alias_path), $servicefile_path, 'correct instance alias link');
ok(! -l $template_wanted_path, 'template wanted link does still not exist');
is($dpkg_root . readlink($instance_wanted_path), $servicefile_path, 'correct instance wanted link');
is_enabled($random_unit);

$retval = dsh('disable', $random_unit);
isnt_enabled($random_unit);
ok(! -l $template_alias_path, 'template alias link does not exist anymore');
ok(! -l $instance_alias_path, 'instance alias link does not exist anymore');
ok(! -l $template_wanted_path, 'template wanted link does still not exist');
ok(! -l $instance_wanted_path, 'instance wanted link does not exist anymore');

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Verify WantedBy and Alias with template unit without DefaultInstance.     ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

open($fh, '>', $servicefile_path);
print $fh <<'EOT';
[Unit]
Description=template test unit

[Service]
ExecStart=/bin/sleep 1

[Install]
Alias=foo\x2dtest@.service
Alias=foo\x2dbar@baz.service
RequiredBy=foo\x2ddepender@.service
EOT
close($fh);

isnt_enabled($random_unit);
isnt_enabled('foo\x2dtest@.service');
isnt_enabled('foo\x2dbar@baz.service');

$template_alias_path = $dpkg_root . '/etc/systemd/system/foo\x2dtest@.service';
$instance_alias_path = $dpkg_root . '/etc/systemd/system/foo\x2dbar@baz.service';
$template_wanted_path = $dpkg_root . '/etc/systemd/system/foo\x2ddepender@.service.requires/' . $random_unit;
$instance_wanted_path = $dpkg_root . '/etc/systemd/system/foo\x2ddepender@.service.requires/' . $random_instance;
ok(! -l $template_alias_path, 'template alias link does not exist yet');
ok(! -l $instance_alias_path, 'instance alias link does not exist yet');
ok(! -l $template_wanted_path, 'template wanted link does not exist yet');
ok(! -l $instance_wanted_path, 'instance wanted link does not exist yet');
$retval = dsh('enable', $random_unit);
is($retval, 0, "enable command succeeded");
is($dpkg_root . readlink($template_alias_path), $servicefile_path, 'correct template alias link');
is($dpkg_root . readlink($instance_alias_path), $servicefile_path, 'correct instance alias link');
is($dpkg_root . readlink($template_wanted_path), $servicefile_path, 'correct template wanted link');
ok(! -l $instance_wanted_path, 'instance wanted link does still not exist');
is_enabled($random_unit);

$retval = dsh('disable', $random_unit);
isnt_enabled($random_unit);
ok(! -l $template_alias_path, 'template alias link does not exist anymore');
ok(! -l $instance_alias_path, 'instance alias link does not exist anymore');
ok(! -l $template_wanted_path, 'template wanted link does still not exist');
ok(! -l $instance_wanted_path, 'instance wanted link does not exist anymore');

done_testing;
