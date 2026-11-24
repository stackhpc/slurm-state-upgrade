
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
