
Convert Slurm accounting DB and slurmctld state to an intermediate
version BEFORE reimaging, using a container with the intermediate Slurm
packages.

Uses a locally-built container image copied to the control node to
avoid any network issues.

Conversion runs in two steps, each with its own marker file:
  1. dbd:  convert the accounting DB.
           On failure: restore the DB snapshot before retrying, so the
           retry starts from the original schema.
  2. ctld: convert the slurmctld state (needs the DB from step 1).
           On failure: just rerun. The state is restored from the
           pre-conversion backup automatically before each attempt.

Once both steps are done, the old host daemons can no longer start.
Take the volume snapshot BEFORE running this.

The following variables should be set in your environment:

- TODO:


## Process

1. Ensure no jobs are running on the cluster, e.g. via a reservation etc.

2. Stop all slurm daemons

      ansible login,compute -ba "systemctl stop slurmd"
      ansible control -ba "systemctl stop slurmctld"
      ansible control -ba "systemctl stop slurmdbd"

3. Stop mysql:

      ansible control -ba "systemctl stop mysql"

4. Stop other services which use the state volume:

      ansible control -ba "systemctl stop mysql opensearch prometheus grafana-server"
      ansible control -m shell -ba "lsof /var/lib/state || echo nothing active"

5. Create a snapshot of the state volume:

      openstack volume snapshot create --volume <state-volume> --force <state-volume>.old

6. Wait until it shows available:

      openstack volume snapshot show <state-volume>.old

7. Restart mysql ONLY:

      ansible control -ba "systemctl start mysql"
      ansible control -ba "systemctl start slurmdbd"
