In the `quadctlt matrixl all` view need to account for dependencies (same named volumes, image, files) correctly

This could include sidecars / backup scripts, like postgres-walg-backup-script. 

this would mean everything needs the correct prefix.

I already have regular systemd services in quadctl / matrix view because of that prefix. 

---

some commands a wrapped too softly, like quadctl status cannot use -l as systemctl --user status could 

Depends-on / depended-by are flawed currently, give incorrect results, should also be soft wrappers, since I believe systemctl has a similar command.

```bash

➜  q cat intent ente-web | head -10
:: [Intent View] Inspecting Deployed Quadlet...
   File: /var/home/handahl/.config/containers/systemd/hanlab-ente-web.container
   ------------------------------------------------------------
[Unit]
Description=Ente Photos Web Frontend
Documentation=https://ente.io/docs/
Upholds=hanlab-ente.service hanlab-garage.service hanlab-postgres.service hanlab-traefik.service
After=hanlab-ente.service hanlab-garage.service hanlab-postgres.service hanlab-traefik.service

[Container]


➜  q depends-on ente
hanlab-ente.service
● ├─hanlab-backend-network.service
● ├─hanlab-garage.service
● ├─hanlab-postgres.service
● ├─hanlab-proxy-network.service
● ├─hanlab-traefik.service
●     ├─hanlab-lego.timer
●     ├─hanlab-postgres-backup.timer
●     ├─hanlab-postgres-wal-verify.timer


➜  q depends-on ente-web
hanlab-ente-web.service
○ ├─hanlab-ente.service
● ├─hanlab-garage.service
● ├─hanlab-postgres.service
● ├─hanlab-proxy-network.service
● ├─hanlab-traefik.service
●     ├─hanlab-lego.timer
●     ├─hanlab-postgres-backup.timer
●     ├─hanlab-postgres-wal-verify.timer


➜  q depended-by ente-web
hanlab-ente-web.service


➜  q depended-by ente
hanlab-ente.service
○ └─hanlab-ente-web.service


➜  systemctl --help | rg depen
  list-dependencies [UNIT...]         Recursively show units which are required
  add-wants TARGET UNIT...            Add 'Wants' dependency for the target
  add-requires TARGET UNIT...         Add 'Requires' dependency for the target
     --reverse           Show reverse dependencies with 'list-dependencies'
     --before            Show units ordered before with 'list-dependencies'
     --after             Show units ordered after with 'list-dependencies'
     --with-dependencies Show unit dependencies with 'status', 'cat',
     --plain             Print unit dependencies as a list instead of a tree

➜  systemctl --user list-dependencies hanlab-ente.service
hanlab-ente.service
● ├─hanlab-backend-network.service
● ├─hanlab-garage.service
● ├─hanlab-postgres.service
● ├─hanlab-proxy-network.service
● ├─hanlab-traefik.service
● ├─hanlab.slice
● ├─podman-user-wait-network-online.service
● └─basic.target
●   ├─systemd-tmpfiles-setup.service
●   ├─paths.target
●   ├─sockets.target
●   │ ├─dbus.socket
●   │ ├─podman.socket
●   │ ├─systemd-ask-password.socket
●   │ ├─systemd-importd.socket
●   │ └─systemd-machined.socket
●   └─timers.target
●     ├─han3-motd-sysinfo.timer
●     ├─hanlab-lego.timer
●     ├─hanlab-postgres-backup.timer
●     ├─hanlab-postgres-wal-verify.timer
●     ├─rustic-immich.timer
●     └─systemd-tmpfiles-clean.timer


➜  systemctl --user list-dependencies hanlab-ente.service --reverse
hanlab-ente.service
○ └─hanlab-ente-web.service


```

although just because timers.target is involved doesn't mean all of them are dependencies

---

the prefix could be hanlab, regardless of which machine, making deployment easier. 

