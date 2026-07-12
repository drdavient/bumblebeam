# Elements boot check

This is deliberately a one-shot boot job. It gives the Elements USB disk up to
two minutes to mount with the expected UUID, read-write mode, sentinel file, and
media directory. A healthy result resets the reboot counter and exits.

Docker restart policies are disabled because the check should not monitor the disk
after startup. The host systemd unit is the boot trigger.

This job does not start, stop, gate, or monitor Plex or any other application.
Services remain available for configuration if Elements later fails or is removed.
The job's authority ends when its boot-time check exits.

Install it once:

```sh
sudo install -m 0644 systemd/bumblebeam-elements-boot-check.service \
  /etc/systemd/system/bumblebeam-elements-boot-check.service
sudo systemctl daemon-reload
sudo systemctl enable bumblebeam-elements-boot-check.service
sudo systemctl start bumblebeam-elements-boot-check.service
```

Check the result with:

```sh
systemctl status bumblebeam-elements-boot-check.service
tail /var/log/mount-rebooter/mount-rebooter.log
```

If the expected disk is present but read-only, the job refuses to force a reboot
so the NTFS filesystem can be repaired safely.
