#!/bin/bash
# Run an intermediate Slurm version to convert the accounting DB or the
# slurmctld state, then shut everything down cleanly.
# Installed in the image as /usr/local/bin/slurm-convert.
#
# Usage: slurm-convert dbd|ctld
#   dbd   Start slurmdbd (converts the DB during startup), wait until it is
#         ready, stop it, check the conversion was logged.
#   ctld  Start slurmdbd (DB already converted, so quick), start slurmctld
#         (loads old state), stop slurmctld (saves state in new format),
#         stop slurmdbd, check the state was saved and rewritten.
#
# Environment:
#   DBD_TIMEOUT  seconds to wait for slurmdbd to become ready in dbd mode
#                (default 3600)
#   CTLD_STATE_DIR path to StateSaveLocation for slurm control daemon state
#
# Exit codes:
#   0   success
#   1   usage error
#   2   a daemon exited during startup
#   3   slurmctld did not shut down cleanly
#   4   no DB conversion logged by slurmdbd
#   5   no state save logged by slurmctld
#   6   a slurmctld state file was not rewritten
#   7   slurmdbd did not shut down cleanly
#   124 timed out waiting for a daemon to start
set -u

mode=${1:-}
slurmctld_state_dir="${CTLD_STATE_DIR:?CTLD_STATE_DIR must be set}"
state_files="job_state node_state resv_state assoc_usage"
dbd_log=/tmp/slurmdbd.log
ctld_log=/tmp/slurmctld.log
ctld_start=/tmp/ctld-start

# Wait until something is listening on a port.
# Args: port pid timeout. Returns 0 ready, 2 daemon exited, 124 timeout.
wait_port() {
  timeout "$3" bash -c "
    until ss -Hltn 'sport = :$1' | grep -q .; do
      kill -0 $2 2>/dev/null || exit 2
      sleep 2
    done"
}

# Send SIGINT and wait for the process to exit. Returns its exit status.
stop() { kill -INT "$1" 2>/dev/null; wait "$1"; }

# Start slurmdbd in the background and wait for it to be ready.
# Args: timeout. Sets dbd (pid). Returns as wait_port.
start_dbd() {
  echo "=== starting slurmdbd ==="
  /usr/sbin/slurmdbd -D -v >"$dbd_log" 2>&1 &
  dbd=$!
  wait_port 6819 "$dbd" "$1"
}

# Stop slurmdbd. Sets rc=7 if everything else succeeded but it exited uncleanly.
stop_dbd() {
  echo "=== stopping slurmdbd ==="
  stop "$dbd"; dbd_rc=$?
  if [ "$rc" -eq 0 ] && [ "$dbd_rc" -ne 0 ]; then rc=7; fi
}

case "$mode" in
  dbd)
    start_dbd "${DBD_TIMEOUT:-3600}"
    rc=$?
    stop_dbd
    if [ "$rc" -eq 0 ]; then
      grep -q 'Conversion done: success' "$dbd_log" || rc=4
    fi
    ;;

  ctld)
    start_dbd 300
    rc=$?
    if [ "$rc" -eq 0 ]; then
      echo "=== starting slurmctld ==="
      touch "$ctld_start"
      /usr/sbin/slurmctld -D -v >"$ctld_log" 2>&1 &
      ctld=$!
      wait_port 6817 "$ctld" 300
      rc=$?
      echo "=== stopping slurmctld ==="
      stop "$ctld"; ctld_rc=$?
      if [ "$rc" -eq 0 ] && [ "$ctld_rc" -ne 0 ]; then rc=3; fi
    fi
    # Stop slurmdbd after slurmctld, so slurmctld can talk to it while shutting down
    stop_dbd
    if [ "$rc" -eq 0 ]; then
      grep -q 'Saving all slurm state' "$ctld_log" || rc=5
    fi
    if [ "$rc" -eq 0 ]; then
      for f in $state_files; do
        if [ ! "$slurmctld_state_dir/$f" -nt "$ctld_start" ]; then
          echo "not rewritten: $slurmctld_state_dir/$f"
          rc=6
        fi
      done
    fi
    ;;

  *)
    echo "usage: $0 dbd|ctld" >&2
    exit 1
    ;;
esac

echo "=== slurmdbd log ==="
cat "$dbd_log"
if [ "$mode" = ctld ]; then
  echo "=== slurmctld log ==="
  cat "$ctld_log" 2>/dev/null
fi
echo "=== exit code: $rc ==="
exit "$rc"
