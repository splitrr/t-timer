# Notifications: Data + Assumptions (Parallels VM backup/restore)

This document describes the **data sources**, **state model**, and **complete alert catalog** for a macOS notification system that monitors:

- Local wrapper: `mac/vm-backups/vm-backup-wrapper.sh`
- Local backup: `mac/vm-backups/backup-vm.sh`
- Local restore: `mac/vm-backups/restore-vm-smb-fast.sh`
- NAS rotation: `nas/vm-backups-nas/vm-backup-rotate.sh`
- Optional VM stop helper: `mac/vm-backups/shutdown-miarm-if-suspended.sh`

It’s written to minimize false alerts when scripts are run **unattended** (LaunchAgent/SleepWatcher) and to support “manual runs” too.

---

## Data model (sources of truth)

### Local (macOS) files

- **Wrapper log**
  - Path: `~/Parallels/backup-logs/vm-backup-wrapper.log`
  - Producer: `vm-backup-wrapper.sh`
  - Key signals:
    - Daily skip: `Backup already completed today (...)`
    - Network gate skip: `Study LAN not connected — backup skipped`
    - VM gate skip: `VM miARM is running; skipping backup...`
    - Locking:
      - Success: `Acquired wrapper lock (pid=...)`
      - Stale lock recovered: `Stale wrapper lock detected ... removing and retrying`
      - Contended: `Another wrapper instance is already running ... exiting`
    - Backup outcome:
      - Success: `Backup script completed successfully`
      - Failure: `Backup script failed (exit X); leaving staging copy intact`

- **Local success marker (daily “done” stamp)**
  - Path: `~/Parallels/.backup-staging/.last-successful-run`
  - Producer:
    - Written by `vm-backup-wrapper.sh` **after** `backup-vm.sh` succeeds.
    - Also written by `backup-vm.sh` on success (best-effort).
  - Format: a single line date `YYYY-MM-DD`.
  - Semantics:
    - If present and equals “today”, wrapper skips (unless `--force`).
    - Cleared at backup start (in `backup-vm.sh`) and cleared pre-run for `--force` (in wrapper) to avoid stale “success” on failures.
  - Failure mode:
    - Can become root-owned if any script was run via `sudo` → later user-runs log a warning and cannot update it.

- **Backup logs (per-run)**
  - Directory: `~/Parallels/backup-logs/backup-vm/`
  - Pattern: `backup-vm-YYYY-MM-DD-HHMMSS.log`
  - Producer: `backup-vm.sh`
  - Key signals:
    - Start header includes script dir + configuration.
    - Mount success/failure lines.
    - rsync exit code & failure marker lines.
    - “Backup FAILED ...” on nonzero rsync exit.

- **Restore logs (per-run)**
  - Directory: `~/Parallels/restored/restore-log/`
  - Pattern: `restore-vm-smb-YYYY-MM-DD-HHMMSS.log`
  - Producer: `restore-vm-smb-fast.sh`
  - Key signals:
    - SMB mount detection + mount errors.
    - Source selected: `Restore source set: previous|miARMDir`
    - rsync exit code (success/failure)
    - Structural validation: `config.pvs not found — invalid Parallels VM bundle`

### NAS (Synology) files (on share `/volume1/ParallelsBackups`)

Paths below are relative to NAS base `BASE=/volume1/ParallelsBackups`.

- **Backup state markers (written by macOS backup script via NFS)**
  - Directory: `miARMDir/`
  - **In progress**: `miARMDir/.backup_in_progress`
    - Written at backup start, removed on success/failure.
    - Contents: timestamp-ish (best effort).
  - **Complete**: `miARMDir/.backup_complete`
    - Written on any successful rsync.
    - Cleared by rotation script *after* successful rotation.
  - **Failed**: `miARMDir/.backup_failed`
    - Written on rsync failure (includes timestamp + rsync_exit).
    - Cleared on next successful backup.
  - **Remote lock dir**: `miARMDir/.backup_lock/`
    - Created at backup start; removed on exit (trap).
    - Files:
      - `pid` (macOS backup script PID, not meaningful on NAS but useful context)
      - `host`
      - `start_time`

- **Rotation log (written by NAS task)**
  - File: `rotation.log` in `BASE/`
  - Producer: `vm-backup-rotate.sh`
  - Key signals:
    - Skip due to in-progress marker, lock dir, failed marker, or missing `.backup_complete`.
    - rsync rotation failures (exit code, output)
    - Success: “Rotation complete” + “Removed completion marker…”

---

## State machine (recommended)

You can model the system as a **single VM pipeline** with these states:

- **Idle**
  - No `.backup_in_progress` and no `.backup_lock`.
- **Running backup**
  - `.backup_lock/` exists (strongest signal) and/or `.backup_in_progress` exists.
- **Backup succeeded**
  - `.backup_complete` exists AND `.backup_failed` absent.
  - Local daily stamp equals today.
- **Backup failed**
  - `.backup_failed` exists OR backup log indicates failure OR wrapper reported nonzero exit.
- **Rotation eligible**
  - `.backup_complete` exists (and not in-progress/locked/failed).
- **Rotated**
  - Rotation succeeds and clears `.backup_complete`.

Important nuance: Rotation clears `.backup_complete` on success, so “absence of `.backup_complete`” does **not** necessarily mean “no backup happened”; it can mean “backup rotated already”.

---

## Assumptions (explicit)

### Environment assumptions

- Scripts run as **user** `AnthonyWest` (not root), except `mount-nfs-helper.sh` / `umount-nfs-helper.sh` which are invoked via `sudo -n` and must be NOPASSWD.
- macOS has:
  - Homebrew `rsync` at `/opt/homebrew/bin/rsync` (preferred), otherwise system rsync is used.
  - Parallels CLI `prlctl` accessible (wrapper currently uses `/usr/local/bin/prlctl`; shutdown script searches PATH).
- Network gating (wrapper):
  - Service name: `Direct Study Lan`
  - “Study LAN connected” means router is `192.168.0.1`.
- VM bundle name is stable:
  - Local VM: `~/Parallels/miARM.pvm`
  - NAS directories: `miARMDir/miARM.pvm` and `previous/miARM.pvm`

### Time assumptions

- Machine time is reasonably accurate (no huge clock jumps).
- Notifications should use local time zone for human readability; store raw epoch when possible.

### “Success” definition assumptions

- A “successful backup” is defined as:
  - `backup-vm.sh` exits 0 (rsync exit 0)
  - Wrapper logs `Backup script completed successfully`
  - Local daily stamp is written successfully **or** is at least logged as a warning if unwritable
  - NAS `.backup_complete` is written on success (rotation may later remove it)

### “Failure” definition assumptions

- A “failed backup attempt” is defined as:
  - `backup-vm.sh` exits nonzero **or**
  - NAS `.backup_failed` exists **or**
  - Wrapper logs `Backup script failed (exit X)`

### Encryption assumptions (Parallels)

- Encrypted VMs may cause `prlctl stop` to require an interactive unlock/password:
  - shutdown helper returns exit code **3** to signal “encrypted/locked”.
- The backup script itself does not depend on `prlctl stop`; it only checks `pgrep -f prl_vm_app` and refuses if running.

---

## Alert catalog (complete)

Below are all alerts the notification system should support. Each includes:
- **Trigger**
- **Severity**
- **Recommended payload**
- **Dedupe key**

### Backup flow: success & freshness

- **Backup succeeded**
  - **Trigger**: Wrapper logs `Backup script completed successfully` OR backup log ends with `Backup completed successfully!`
  - **Severity**: info
  - **Payload**:
    - date (today)
    - latest backup log path
    - rsync duration (if parsed)
    - destination (`miARMDir`)
  - **Dedupe**: `backup_success:<YYYY-MM-DD>`

- **Backup stale (no success within threshold)**
  - **Trigger**: Local success marker date < today - N days (e.g. N=1) AND no “successful backup” in logs within N days
  - **Severity**: warning (or critical for N≥2)
  - **Payload**:
    - last_success_date
    - threshold_days
    - last wrapper log lines (tail)
  - **Dedupe**: `backup_stale:<last_success_date>`

### Wrapper “skip” conditions (not failures)

- **Skipped: already done today**
  - **Trigger**: Wrapper logs `Backup already completed today (...)`
  - **Severity**: debug/info (usually suppress notifications)
  - **Payload**: today, success marker path
  - **Dedupe**: `wrapper_skip_done:<YYYY-MM-DD>`

- **Skipped: study LAN not connected**
  - **Trigger**: Wrapper logs `Study LAN not connected — backup skipped`
  - **Severity**: info (or warning if you expected it to run)
  - **Payload**:
    - service name, expected gateway
  - **Dedupe**: `wrapper_skip_network:<YYYY-MM-DD>`

- **Skipped: VM running**
  - **Trigger**: Wrapper logs `VM miARM is running; skipping backup...`
  - **Severity**: info (or warning if persistent)
  - **Payload**:
    - vm name
  - **Dedupe**: `wrapper_skip_vm_running:<YYYY-MM-DD>`

### Locking / concurrency (local + NAS)

- **Wrapper lock contended (another instance running)**
  - **Trigger**: Wrapper logs `Another wrapper instance is already running ...`
  - **Severity**: warning (usually means duplicate triggers)
  - **Payload**: locked_pid (if present), locked_since (if present)
  - **Dedupe**: `wrapper_lock_contended:<YYYY-MM-DD>`

- **Wrapper stale lock auto-cleared**
  - **Trigger**: Wrapper logs `Stale wrapper lock detected ... removing and retrying`
  - **Severity**: info
  - **Payload**: old pid/since
  - **Dedupe**: `wrapper_lock_stale_cleared:<YYYY-MM-DD>`

- **Remote NAS lock present (backup prevented)**
  - **Trigger**: Backup log contains `ERROR: Remote NAS lock already present`
  - **Severity**: warning (can be critical if it persists)
  - **Payload**:
    - lock_dir
    - pid/host/since values from NAS if readable
  - **Dedupe**: `nas_lock_present:<lock_host>:<lock_since>`

- **Remote NAS lock stale suspicion**
  - **Trigger**: `.backup_lock/` exists for > X hours (e.g. 6h) AND no backup currently running
  - **Severity**: warning
  - **Payload**: lock pid/host/start_time, age_hours
  - **Dedupe**: `nas_lock_stale:<lock_host>:<lock_since>`

### Backup hard failures (mount / rsync / permissions)

- **Backup failed: NFS mount failed**
  - **Trigger**: Backup log contains `ERROR: Failed to mount NFS share`
  - **Severity**: critical
  - **Payload**:
    - NAS host + export
    - mount point
    - mount output (captured)
  - **Dedupe**: `backup_mount_fail:<YYYY-MM-DD-HH>`

- **Backup failed: destination not writable**
  - **Trigger**: Backup log contains `ERROR: Failed to create backup directory`
  - **Severity**: critical
  - **Payload**:
    - BACKUP_DIR
  - **Dedupe**: `backup_dest_perm:<YYYY-MM-DD-HH>`

- **Backup failed: rsync nonzero**
  - **Trigger**:
    - Backup log contains `ERROR: rsync encountered an issue (exit code: X)` OR
    - NAS `.backup_failed` exists with details
  - **Severity**: critical
  - **Payload**:
    - rsync_exit
    - path to latest backup log
    - failure marker path and contents (if available)
  - **Dedupe**: `backup_rsync_fail:<YYYY-MM-DD-HH>:<rsync_exit>`

- **Backup warning: could not write local success marker**
  - **Trigger**: Wrapper or backup logs `WARNING: Could not write success marker (permission denied?)`
  - **Severity**: warning
  - **Payload**:
    - marker path
    - recommended fix: `sudo chown "$USER":staff <file>` (include only in doc/UI, not as auto-action)
  - **Dedupe**: `success_marker_perm:<marker_path>`

- **Backup warning: could not unmount NFS**
  - **Trigger**: Backup log contains `WARNING: Could not unmount NFS share`
  - **Severity**: warning (often harmless)
  - **Payload**: mount point
  - **Dedupe**: `nfs_unmount_warn:<YYYY-MM-DD>`

### Rotation (NAS) alerts

- **Rotation skipped: backup in progress**
  - **Trigger**: NAS log line `Backup still in progress — skipping rotation` OR `.backup_in_progress` exists at schedule time
  - **Severity**: info
  - **Payload**: marker path
  - **Dedupe**: `rotation_skip_inprogress:<YYYY-MM-DD>`

- **Rotation skipped: backup lock present**
  - **Trigger**: NAS log line `Backup lock present ... skipping rotation`
  - **Severity**: warning (if persists)
  - **Payload**: lock pid/host/since
  - **Dedupe**: `rotation_skip_lock:<lock_host>:<lock_since>`

- **Rotation skipped: backup failed**
  - **Trigger**: NAS log line `Backup FAILED — skipping rotation`
  - **Severity**: warning/critical (depending on recency)
  - **Payload**: `.backup_failed` contents
  - **Dedupe**: `rotation_skip_failed:<YYYY-MM-DD>`

- **Rotation skipped: no completion marker**
  - **Trigger**: NAS log line `No backup_complete marker — skipping rotation`
  - **Severity**: info
  - **Payload**: marker path
  - **Dedupe**: `rotation_skip_no_marker:<YYYY-MM-DD>`

- **Rotation failed**
  - **Trigger**: NAS log line `ERROR: rotation rsync failed (exit X)`
  - **Severity**: critical
  - **Payload**:
    - exit code
    - rsync output snippet
  - **Dedupe**: `rotation_fail:<YYYY-MM-DD-HH>:<exit>`

- **Rotation succeeded**
  - **Trigger**: NAS log lines include `Rotation complete` and `Removed completion marker...`
  - **Severity**: info
  - **Payload**: rsync transfer summary (bytes sent/received)
  - **Dedupe**: `rotation_success:<YYYY-MM-DD>`

### Restore (SMB) alerts

- **Restore succeeded**
  - **Trigger**: Restore log `rsync completed successfully` AND validates `config.pvs`
  - **Severity**: info
  - **Payload**:
    - source set (previous|miARMDir)
    - restored path
    - restore log path
  - **Dedupe**: `restore_success:<YYYY-MM-DD-HHMM>:<source_set>`

- **Restore failed: SMB mount failed**
  - **Trigger**: Restore log contains `ERROR: mount_smbfs failed` or `ERROR: SMB share not mounted`
  - **Severity**: critical
  - **Payload**:
    - SMB_SHARE
    - mount path used (including Finder mount detection)
    - mount error output
  - **Dedupe**: `restore_smb_mount_fail:<YYYY-MM-DD-HH>`

- **Restore failed: source missing**
  - **Trigger**: Restore log `ERROR: Backup source not found`
  - **Severity**: critical
  - **Payload**: `BACKUP_SOURCE`
  - **Dedupe**: `restore_source_missing:<YYYY-MM-DD>:<source_set>`

- **Restore failed: rsync nonzero**
  - **Trigger**: Restore script exit code nonzero OR log `ERROR: rsync failed with exit code X`
  - **Severity**: critical
  - **Payload**:
    - rsync exit code
    - restore log path
  - **Dedupe**: `restore_rsync_fail:<YYYY-MM-DD-HH>:<exit>`

- **Restore failed: invalid Parallels bundle**
  - **Trigger**: Restore log `config.pvs not found — invalid Parallels VM bundle`
  - **Severity**: critical
  - **Payload**: restored path
  - **Dedupe**: `restore_invalid_bundle:<YYYY-MM-DD-HH>`

- **Restore warning: nested bundle flattened**
  - **Trigger**: Restore log `WARNING: Nested .pvm detected — flattening bundle`
  - **Severity**: warning
  - **Payload**: restored path
  - **Dedupe**: `restore_nested_flattened:<YYYY-MM-DD-HH>`

### Optional: VM shutdown helper alerts

- **Shutdown helper refused: VM running**
  - **Trigger**: exit code 2 OR log `VM 'miARM' is RUNNING — refusing to stop it.`
  - **Severity**: info/warning
  - **Payload**: vm name
  - **Dedupe**: `shutdown_refused_running:<YYYY-MM-DD>`

- **Shutdown helper blocked: encrypted/locked**
  - **Trigger**: exit code 3 OR logs include `encryption/password requirement`
  - **Severity**: warning
  - **Payload**: vm name, instruction to unlock in Parallels GUI
  - **Dedupe**: `shutdown_blocked_encrypted:<YYYY-MM-DD>`

### Optional anomaly alerts (recommended)

- **Size anomaly: NAS backup much smaller/larger than local**
  - **Trigger**: |(local_du_bytes - remote_du_bytes)| > threshold (e.g. 10–20GB)
  - **Severity**: info→warning (depending on magnitude/consistency)
  - **Payload**:
    - local size (bytes + human)
    - remote size (bytes + human)
    - how measured (du flags, filesystem)
  - **Assumption**:
    - Differences can be legitimate due to APFS cloning/sparse files/xattrs/encryption layout; treat as anomaly, not failure.
  - **Dedupe**: `size_anomaly:<YYYY-MM-DD>`

---

## Parsing guidance (practical)

- Prefer “explicit markers + exit codes” over fuzzy string matching.
- Use log parsing mainly for:
  - human-friendly context
  - extracting rsync exit codes
  - extracting skip reasons
- Recommended priority order for backup status:
  1. wrapper exit (if you run wrapper as the top-level job)
  2. local success marker date (freshness)
  3. NAS markers (`.backup_lock`, `.backup_failed`, `.backup_in_progress`, `.backup_complete`)
  4. latest backup log tail

---

## Notification dedupe & rate limits (recommended defaults)

- **Per-event dedupe**: key as specified above.
- **Rate limits**:
  - Critical: at most 1 per hour per dedupe key.
  - Warning: at most 1 per 6 hours per dedupe key.
  - Info: at most 1 per day per dedupe key.

---

## Minimal “status summary” payload (recommended for every alert)

Include this in every notification (even if partially unknown):

- machine hostname
- script origin (`wrapper` | `backup` | `restore` | `rotation`)
- timestamp
- last success date (from local marker)
- NAS marker snapshot:
  - lock present? (pid/host/since)
  - in_progress present?
  - failed present? (contents)
  - complete present?
- paths:
  - latest relevant log file path

