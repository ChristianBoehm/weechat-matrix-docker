# WeeChat + Matrix in Docker (Alpine) — Usage

## What's in this directory

| File | Purpose |
|---|---|
| `Dockerfile` | `alpine:3.22` (multi-arch, native on Apple Silicon) + weechat 4.6.3, weechat-python, weechat-matrix (for its deps), socat; script code copied from the fork; non-root `weechat` user; config autosave script; runtime entrypoint (autoload symlinks, socat SSO bridge) |
| `docker-compose.yml` | Mounts `./data` over the user's home, TTY-enabled, SSO port mapping, `restart: unless-stopped`, `/secure` passphrase secret |
| `.gitignore` / `.dockerignore` | Keep `data/`, `secrets/`, backups and personal notes out of git and out of the build context |
| `secrets/weechat_passphrase` | *(not in git, created during setup)* random passphrase for WeeChat's `/secure` data (compose secret, read by `sec.crypt.passphrase_command`) |
| `data/` | *(not in git, created on first start)* all persisted WeeChat state: config, E2EE keys, Matrix access token, logs |

Image: `weechat-matrix:alpine` (~188MB).

**Script source (maintained fork):** [`ChristianBoehm/weechat-matrix`](https://github.com/ChristianBoehm/weechat-matrix).
Upstream `poljar/weechat-matrix` is orphaned (last commit 2023-07-23 = the exact
commit Alpine pins). The fork (signed release tags) carries the
session-persistence, python-future and shebang fixes plus self cross-signing,
key backup restore and `auto_ignore_new_devices`.
**The image is built from the pinned tag:** the `Dockerfile` stage `fork`
fetches `https://github.com/ChristianBoehm/weechat-matrix.git#${WEECHAT_MATRIX_VERSION}`
with `ADD --checksum=${WEECHAT_MATRIX_COMMIT}`, so the build fails if the tag
ever points to a different commit. No local clone is needed. Both values are
`ARG`s at the top of the `Dockerfile` — the only place the version is set.

## First run

```bash
# passphrase for WeeChat's encrypted /secure data (compose secret, required)
mkdir -m 700 secrets
openssl rand -base64 33 > secrets/weechat_passphrase
chmod 600 secrets/weechat_passphrase

mkdir -m 700 data
docker compose up -d
docker compose attach weechat
```

Inside WeeChat, tell it where the passphrase is and encrypt `/secure` data
(once; the second command reads the secret without echoing it):

```
/set sec.crypt.passphrase_command "cat /run/secrets/weechat_passphrase"
```

```bash
docker compose exec -T weechat sh -c \
  'printf "*/secure passphrase %s\n" "$(cat /run/secrets/weechat_passphrase)" > ~/.cache/weechat/weechat_fifo_1'
```

### Password login

```
/matrix server add myserver matrix.example.org
/set matrix.server.myserver.username <your-user>
/secure set matrix_password <password>
/set matrix.server.myserver.password "${sec.data.matrix_password}"
/matrix connect myserver
/set matrix.server.myserver.autoconnect on
```

### SSO-only homeserver

Some homeservers (e.g. university IdPs) offer no password login — only
SSO/OIDC. Leave username/password empty:

```
/matrix server add myserver matrix.example.org
/set matrix.server.myserver.sso_helper_listening_port 8443
/matrix connect myserver
```

WeeChat prints a login URL → open it in a browser **on the Docker host** →
sign in. The IdP redirects to `http://127.0.0.1:8443`, which is bridged into
the container (compose maps `127.0.0.1:8443` → socat on container `8444` → the
helper on container loopback `8443`). Then:

```
/set matrix.server.myserver.autoconnect on
```

Config changes are saved automatically within 15 s (autosave script in the image).

The Matrix **access token** is stored in
`data/.local/share/weechat/matrix/<server>/access_token`, so later starts
reconnect silently (`matrix: Already logged in, syncing...`). A browser login
is only needed again if the homeserver revokes the token (HTTP 401); temporary
server errors keep it (fork 0.3.5). The login URL is also written to
`data/.local/share/weechat/logs/python.server.<server>.weechatlog`.

## Daily use

The container runs **detached** and keeps the Matrix session alive (survives reboots, `restart: unless-stopped`):

```bash
docker compose up -d           # start (no-op if already running)
docker compose attach weechat  # open the TUI; Ctrl-P Ctrl-Q leaves, container keeps running
docker compose down            # stop
```

Commands can also be sent headless through WeeChat's FIFO
(`*<command>` = current buffer, `<buffer> *<command>` for a specific one):

```bash
docker compose exec -T weechat sh -c "echo '*/matrix server list' > ~/.cache/weechat/weechat_fifo_1"
```

### Verifying the weechat session (cross-signing)

Element only shows a session as verified if it's signed with the account's
cross-signing key. Weechat can sign itself with the **Element recovery key**
(Settings → Security & Privacy → Recovery). In the server buffer or any
Matrix room:

```
/olm cross-sign <recovery key>
```

→ `This device is now signed with the self-signing key …` — Element shows the
session as verified. Only needed once per device. The recovery key is passed
to the helper on stdin and not stored. If the server ever loses the device
keys, weechat re-uploads them automatically (message "The server lost the
keys of this device…") — then run `/olm cross-sign` again.

### Unlocking old encrypted messages (key backup)

```
/olm backup restore <recovery key>
```

Imports all room keys from Element's server-side key backup and decrypts
messages already shown as locked; older history via Page Up. Repeat whenever
old messages show up locked.

To avoid typing the recovery key each time, store it once in WeeChat's
secured data — it is **encrypted** in `sec.conf` (passphrase from
`secrets/weechat_passphrase`):

```
/secure set matrix_recovery_key <recovery key>
/olm backup restore        # and /olm cross-sign — no key argument needed
```

### "Untrusted devices found in room" (encrypted rooms)

The script refuses to send into an encrypted room while any device in it has
no trust decision. Device states (`/olm`): **verified** (checked), **ignored**
(not checked, but encrypt for it anyway — *not* "ignore the person"),
**blacklisted** (never encrypt for it), unset (blocks sending).

- `matrix.network.auto_ignore_new_devices = on` (fork 0.3.4; set via
  `MATRIX_AUTO_IGNORE_NEW_DEVICES: "on"` in `docker-compose.yml`) ignores new
  devices of **other** people automatically, like Element — new chats just work.
- Your **own** new devices still block sending until you decide:
  `/olm verify @you:example.org <device>` or `/olm blacklist …`.
- `/set matrix.network.resending_ignores_devices off`: sending the same
  message twice no longer silently drops the undecided devices (with `on` the
  resend goes out *unreadable* for them).
- Check: `/olm info unverified` (includes ignored), `/olm info ignored`.

## Persistence & backup

- Everything lives in `./data` (XDG layout: `.config/weechat/`, `.local/share/weechat/`, `.local/state/weechat/`)
- Includes: WeeChat config, `sec.conf` (encrypted `/secure` data), E2EE device keys / nio account DB, access token, logs
- Your device identity survives container rebuilds and image upgrades
- Backup (while stopped): `tar czf weechat-backup.tgz data secrets` — `secrets/` holds the passphrase for the encrypted `/secure` data; without it that data is lost
- Keep `data/` and `secrets/` at `chmod 700`, never commit them (both are in `.gitignore`)

### Moving to another machine

Copy `data/` and `secrets/` (the backup above) next to a clone of this repo
and `docker compose up -d`. Matrix sees the **same device** (device ID, token
and E2EE keys are all in `data/`), so it stays verified and old messages stay
readable. Never run two copies with the same `data/` at once — they would
break each other's encryption sessions. On a Linux host, `data/` must be
owned by the container's `weechat` user (UID 1000).

## Upgrade

```bash
docker compose build --pull
docker compose up -d          # recreates the container on the new image
```

Image is replaced, `data/` is untouched (config, keys and access token persist).

Releases of this repo are tagged `<script version>-r<n>` (signed), e.g.
`0.3.5-r1`. To update: `git pull` (or `git checkout <tag>`), then build and
`up -d` as above.

**Maintainers — new fork release:**

```bash
# 1. Dockerfile: set WEECHAT_MATRIX_VERSION=<tag> and
#    WEECHAT_MATRIX_COMMIT=$(git -C <fork clone> rev-parse '<tag>^{commit}')
# 2. README.md: update the weechat-matrix badge
docker compose build && docker compose up -d   # build checks tag, commit and script version
# 3. commit, then: git tag -s <tag>-r1 -m "..."
```

For testing an unpushed fork change, replace the `fork` stage with a local
clone (the version check still applies):
`docker buildx build --load --build-context fork=<path to fork clone> -t weechat-matrix:alpine .`

## Notes

- The Alpine package pins the 2023-07-23 upstream commit (orphaned since); the **fork** is the maintained source. The image keeps the Alpine package only for its dependencies and copies the fork's script over it.
- E2EE works; the device can cross-sign itself (`/olm cross-sign`) and restore keys from the backup (`/olm backup restore`), but verifying other users via cross-signing, uploading to the key backup and session unwedging are not implemented
- `/python reload matrix` fails (cryptography can't be loaded twice) — use `docker compose restart`
- `docker compose run … <cmd>` passes `<cmd>` to weechat (the entrypoint ends in `exec weechat "$@"`); use `--entrypoint sh` for anything else
- Don't start a second container on the same `./data` while one is running — they race on config load/save
- The persisted login is a Matrix **access token** (no refresh-token support) — it stays valid until the homeserver revokes it; after that one browser SSO is needed again, same device/keys
- After an SSO-helper error the script's reconnect loop can stall → `docker compose restart` clears it
- Optional: add `weechat-relay` to the Dockerfile to reach WeeChat from a phone or web client
