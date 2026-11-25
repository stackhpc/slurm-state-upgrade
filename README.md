
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

The following variables should be set in your environment (e.g. in
`environments/site/inventory/group_vars/all/upgrade_slurm.yml`):

- `slurmupgrade_intermediate_ver`: str specifying the intermediate slurm version, e.g. "23.11.11". This is just used to disambiguate containers/paths etc, so the format does not need to match Slurm's own versioning.
- `ark_username`: str, username for StackHPC's Ark pulp server.
- `ark_password`: str, password for StackHPC's Ark pulp server. Typically, indirect this
  into an Ansible-vaulted file.
- `slurmupgrade_ohpc_repo_url`: str, the timestamp path for the OpenHPC base repository
  in Ark providing the required Slurm version at the right distribution, e.g. "2/EL_8/20241218T154614". See
  `environments/commmon/inventory/group_vars/all/dnf_repo_timestamps.yml`.
- `slurmupgrade_ohpc_update_url`: str, the timestamp path for the OpenHPC update repository
   in Ark providing the required Slurm version at the right distribution, e.g. "2/updates/EL_8/20250512T003315". See
   `environments/commmon/inventory/group_vars/all/dnf_repo_timestamps.yml`.

## Process

1. Ensure no jobs are running on the cluster, e.g. via a reservation etc.

2. Stop all slurm daemons

   ```shell
   ansible login,compute -ba "systemctl stop slurmd"
   ansible control -ba "systemctl stop slurmctld"
   ansible control -ba "systemctl stop slurmdbd"
   ```

3. Stop mysql:

   ```shell
   ansible control -ba "systemctl stop mysql"
   ```

4. Stop other services which use the state volume:

   ```shell
   ansible control -ba "systemctl stop mysql opensearch prometheus grafana-server"
   ansible control -m shell -ba "lsof /var/lib/state || echo nothing active"
   ```

5. Create a snapshot of the state volume:

   ```shell
   openstack volume snapshot create --volume <state-volume> --force <state-volume>.old
   ```

6. Wait until it shows available:

   ```shell
   openstack volume snapshot show <state-volume>.old
   ```

7. Restart mysql ONLY:

   ```shell
   ansible control -ba "systemctl start mysql"
   ansible control -ba "systemctl start slurmdbd"
   ```

8. From inside your normal ansible-slurm-appliance deploy checkout, run this tool e.g.:

   ```shell
   ANSIBLE_LOG_PATH=upgrade.log ansible-playbook ~/slurm-state-upgrade/upgrade.yml -vv
   ```
