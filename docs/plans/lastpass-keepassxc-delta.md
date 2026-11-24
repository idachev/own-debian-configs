# LastPass delta export for KeePassXC

## Command

```sh
./lastpass_to_keepassxc.py --previous old.csv -i new.csv --base current.kdbx -o changes.kdbx
```

`--previous` and `--base` select delta mode together. Delta mode requires an explicit input path. `--dry-run` reports the same comparison without an output path or database. `--base-keyfile` optionally supplies the key file for the current database. The base and output passwords use separate prompts and environment variables (`KEEPASS_BASE_PASSWORD` and `KEEPASS_MASTER_PASSWORD`). The original single-CSV conversion remains available.

## Compare snapshots

- Parse both CSVs completely before producing output. Require the columns used for identity and core data. Accept a UTF-8 BOM, multiline fields, and exports with optional columns omitted. Fail on malformed CSV structure. Treat a missing `totp` column as unknown and an explicitly blank value as empty. Ignore `fav`, since the existing converter does not import it. Diagnostics in both modes identify rows without displaying their values.
- Use the converter's representation of titles, URLs, usernames, notes and LastPass paths. Cancel unchanged rows with multiplicity. Compare unique records with the same group path, title, URL and username. Detect password, notes and TOTP edits. Never print field values in delta diagnostics.
- Apply the original migration's cleanup when matching old values to KeePassXC. An unchanged field in the new CSV can carry the same unstorable characters as the old CSV. Preserve its value in KeePassXC when applying other changes to the entry. Send new or edited values containing unstorable characters for review and continue with other entries.
- A CSV row has no stable LastPass ID. Send ambiguous identity buckets for manual review. A remaining old-only record is report-only. When both old-only and new-only identities remain, report the unmatched new rows for review as well. A pair may be a rename, move, or several edits on one entry. When there are only new-only identities and each is unique, treat them as additions.

## Reconcile with the current database

- Scope changes to the existing `LastPass Migrated` group and match a prior identity uniquely before looking up its entry UUID. Report missing or ambiguous targets. Hold affected rows when multiple sibling groups share a name on the entry's path. Before adding, check for an existing match to avoid duplicate imports and report a collision if the entry differs or appears in another group.
- Compare each LastPass-changed field with its old LastPass value and its incoming value. Preserve unrelated KeePassXC fields. An incoming value already present is a no-op. A value changed differently in KeePassXC is a conflict. Send legacy KeePassXC TOTP formats for review when LastPass changes that field. If the old export omitted TOTP and the incoming nonempty TOTP differs from KeePassXC, report a conflict because the old value is unknown. Hold the entire conflicting entry for manual review.
- The new database contains only new or updated entries and their required ancestor groups. Preserve the UUIDs of existing entries and groups. Copy the full current entry for each update and patch the changed fields. Preserve attachments and their references, custom attributes, history and referenced custom icons. Let KeePassXC store the pre-merge version in entry history. Set each updated entry's modification time one whole-second tick after its base value. Preserve existing group modification times and location times so a password change does not relocate an entry or overwrite group settings. Create new group UUIDs only for new paths. Remove database-level custom data shipped with the pykeepass template. KeePassXC can merge this data separately and remove destination-only keys when it considers the source settings newer. Start with an empty deletion list. [KeePassXC merge implementation](https://github.com/keepassxreboot/keepassxc/blob/2.8.0/src/core/Merger.cpp#L660-L717)

## Output and verification

- Open the base database read-only at the application level. Reject output paths that refer to either input or to the base database or its key file, including aliases. Refuse to replace an existing output unless `--force` is supplied. Build and reopen the output in a private temporary location on the same filesystem, then publish it atomically. With no eligible entries, write no output. Report counts for additions, updates, already applied entries and review items. Include CSV line numbers for review items. Exit with status 2 for unresolved rows, even if a partial delta was produced. Exit with status 1 for input or output errors.
- Use the delta with `Database → Merge From Database` on a copy of the same base database. Generate the delta again if the base changed before merge, because merge compares whole entries by timestamp. The tool does not auto-merge.
- Test the old command, all comparison categories, already applied additions and updates, local field conflicts, optional TOTP data, CSV validation, and output reuse. Run an actual KeePassXC CLI merge on synthetic data and verify metadata with and without a timestamp, UUIDs, group placement, original entry history, current and historical attachment bytes with distinct binary IDs, and custom icons.

Run the tests with `python3 -m unittest discover -s tests/lastpass_to_keepassxc -v`. Install `pykeepass` for the Python tests and put `keepassxc-cli` on `PATH` for the integration tests.
