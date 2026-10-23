# rsync_from

`~/bin/rsync_from.sh` pulls `~/develop/personal/` from another machine
over SSH into `~/develop/personal/` on this Mac.

The source and the destination are fixed. The only required argument is
the SSH destination. A bare host is sent as the local user name
(`id -un` @ host). An SSH config `User` does not replace that name.
`user@host` keeps the remote user you wrote.

Without `doit` the run is a dry-run (`rsync -n`). Nothing is written.
`doit` copies, and `caffeinate -i` keeps the Mac awake until rsync exits.

There is no `--delete`. Files that exist only on this Mac stay.
The script does not pass `-F` or `-C`, so a `.rsync-filter` on the
source does not hide files. `tmp/`, `.venv/`, `.env`, `node_modules/`
and the rest are copied.

An exclude file is optional. Pass your own `rsync --exclude-from` list
when you want to skip names. The script does not ship a list. A leading
`/` anchors a pattern to `~/develop/personal/`. A trailing `/` matches
a directory only. This script does not read that file as an rsync
filter (`-F`). It only passes it to `--exclude-from`.

Homebrew `rsync` is required (`/opt/homebrew/bin/rsync`). Apple `rsync`
rejects `--info=progress2`. Override the binary with `RSYNC=/path/to/rsync`.

## Commands

Preview:

```bash
rsync_from.sh 172.10.9.128
```

Copy:

```bash
rsync_from.sh 172.10.9.128 doit
```

Preview, skipping names in a list you pass:

```bash
rsync_from.sh 172.10.9.128 ./skip.txt
```

Copy with that list:

```bash
rsync_from.sh 172.10.9.128 ./skip.txt doit
```

`skip.txt` is not part of this repo. One pattern per line. Blank lines
and lines that start with `#` or `;` are comments.
