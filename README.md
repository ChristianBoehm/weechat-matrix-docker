# weechat-matrix-docker

[WeeChat](https://weechat.org) 4.6 with the Matrix script
[weechat-matrix](https://github.com/ChristianBoehm/weechat-matrix) (maintained
fork) in a small Alpine container. Runs detached, keeps the Matrix session
alive, and stores all state in `./data` on the host.

- **End-to-end encryption** — the session can cross-sign itself with your
  recovery key (shows as verified in Element) and import old room keys from
  the server-side key backup.
- **SSO-only homeservers** — the browser login callback is bridged into the
  container; the access token is kept across restarts, so the browser is
  needed only once.
- **Headless operation** — `restart: unless-stopped`, config autosave,
  commands through WeeChat's FIFO.
- **Secrets stay out of the image** — WeeChat's `/secure` data is encrypted
  with a passphrase passed in as a Compose secret.

## Quick start

```bash
git clone https://github.com/ChristianBoehm/weechat-matrix-docker.git
cd weechat-matrix-docker

mkdir -m 700 secrets data
openssl rand -base64 33 > secrets/weechat_passphrase
chmod 600 secrets/weechat_passphrase

docker compose up -d
docker compose attach weechat     # Ctrl-P Ctrl-Q detaches
```

Then add your homeserver and log in — see [USAGE.md](USAGE.md) (password and
SSO login, `/secure` setup, verification, key backup, backup and moving to
another machine).

Requires Docker with BuildKit (Docker Desktop or Docker Engine ≥ 23 with the
Compose plugin); the build fetches the script from the fork's signed tag on
GitHub.

## Files

| File | |
|---|---|
| [`Dockerfile`](Dockerfile) | Alpine 3.22 + WeeChat, Python plugin, socat; installs the fork's script |
| [`docker-compose.yml`](docker-compose.yml) | volume, SSO port mapping, restart policy, passphrase secret |
| [`USAGE.md`](USAGE.md) | setup and day-to-day use |

`data/` (access token, encryption keys, config, logs) and `secrets/` are
created locally and are ignored by git and by the Docker build context.
Back them up together while the container is stopped:
`tar czf weechat-backup.tgz data secrets`.

## License

[MIT](LICENSE) for the files in this repository. The weechat-matrix script
installed into the image is ISC-licensed (upstream) — see the
[fork](https://github.com/ChristianBoehm/weechat-matrix).
