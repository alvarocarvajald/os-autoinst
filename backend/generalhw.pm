# Copyright © 2016 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

# this backend uses a KVM connector speaking VNC and external tools
# for serial line and power cycling

package backend::generalhw;

use strict;
use warnings;
use autodie ':all';

use base 'backend::baseclass';

use bmwqemu 'diag';
use testapi qw(get_required_var get_var);
use IPC::Run ();
require IPC::System::Simple;
use File::Basename 'basename';

sub new {
    my $class = shift;
    # required for the tests to access our HTTP port
    get_required_var('WORKER_HOSTNAME');
    return $class->SUPER::new;
}

sub get_cmd {
    my ($self, $cmd) = @_;

    my $dir = get_required_var('GENERAL_HW_CMD_DIR');
    if (!-d $dir) {
        die "GENERAL_HW_CMD_DIR is not pointing to a directory";
    }

    my $args = get_var('GENERAL_HW_FLASH_ARGS') if ($cmd eq 'GENERAL_HW_FLASH_CMD' and get_var('GENERAL_HW_FLASH_ARGS'));

    $cmd = get_required_var($cmd);
    $cmd = "$dir/" . basename($cmd);
    if (!-x $cmd) {
        die "CMD $cmd is not an executable";
    }
    $cmd .= " $args" if $args;

    return $cmd;
}

sub run_cmd {
    my ($self, $cmd) = @_;
    my @full_cmd = split / /, $self->get_cmd($cmd);

    my ($stdin, $stdout, $stderr, $ret);
    $ret = IPC::Run::run([@full_cmd], \$stdin, \$stdout, \$stderr);
    chomp $stdout;
    chomp $stderr;

    die $cmd . ": $stderr" unless ($ret);
    bmwqemu::diag("IPMI: $stdout");
    return $stdout;
}

sub poweroff_host {
    my ($self) = @_;
    $self->run_cmd('GENERAL_HW_POWEROFF_CMD');
    return;
}

sub restart_host {
    my ($self) = @_;

    $self->poweroff_host;
    sleep(3);
    $self->run_cmd('GENERAL_HW_POWERON_CMD');
    return;
}

sub relogin_vnc {
    my ($self) = @_;

    if ($self->{vnc}) {
        close($self->{vnc}->socket);
        sleep(1);
    }

    my $vnc = $testapi::distri->add_console(
        'sut',
        'vnc-base',
        {
            hostname        => get_required_var('GENERAL_HW_VNC_IP'),
            port            => 5900,
            depth           => 16,
            connect_timeout => 50
        });
    $vnc->backend($self);
    $self->select_console({testapi_console => 'sut'});

    return 1;
}

sub do_start_vm {
    my ($self) = @_;

    $self->truncate_serial_file;
    if (get_var('GENERAL_HW_FLASH_CMD')) {
        $self->poweroff_host;    # Ensure system is off, before flashing
        $self->run_cmd('GENERAL_HW_FLASH_CMD');
    }
    $self->restart_host;
    $self->relogin_vnc       if (get_var('GENERAL_HW_VNC_IP'));
    $self->start_serial_grab if (get_var('GENERAL_HW_VNC_IP') || get_var('GENERAL_HW_SOL_CMD'));
    return {};
}

sub do_stop_vm {
    my ($self) = @_;

    $self->poweroff_host;
    $self->stop_serial_grab() if (get_var('GENERAL_HW_VNC_IP') || get_var('GENERAL_HW_SOL_CMD'));
    return {};
}

sub check_socket {
    my ($self, $fh, $write) = @_;

    if ($self->check_ssh_serial($fh)) {
        return 1;
    }

    return $self->SUPER::check_socket($fh, $write);
}

# serial grab

sub start_serial_grab {
    my ($self) = @_;

    $self->{serialpid} = fork();
    if ($self->{serialpid} == 0) {
        setpgrp 0, 0;
        open(my $serial, '>',  $self->{serialfile});
        open(STDOUT,     ">&", $serial);
        open(STDERR,     ">&", $serial);
        exec($self->get_cmd('GENERAL_HW_SOL_CMD'));
        die "exec failed $!";
    }
    return;
}

sub stop_serial_grab {
    my ($self) = @_;
    return unless $self->{serialpid};
    kill("-TERM", $self->{serialpid});
    return waitpid($self->{serialpid}, 0);
}

# serial grab end

1;
