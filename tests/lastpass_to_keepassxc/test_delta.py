"""CLI and KeePassXC merge tests using disposable synthetic vaults."""

import base64
import csv
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from lxml.builder import E
from pykeepass import PyKeePass, create_database


SCRIPT = Path(__file__).resolve().parents[2] / "lastpass_to_keepassxc.py"
KPX = shutil.which("keepassxc-cli")
BASE_PASSWORD = "synthetic-base"
DELTA_PASSWORD = "synthetic-delta"
COLUMNS = ("url", "username", "password", "totp", "extra", "name", "grouping", "fav")
TIME = datetime(2025, 1, 1, tzinfo=timezone.utc)
ICON = ("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42"
        "mP8/x8AAwMCAO+XgxoAAAAASUVORK5CYII=")


def record(name, password="old-password", grouping=r"Work\Apps", **fields):
    return dict(url="https://example.test", username="demo", password=password,
                totp="", extra="", name=name, grouping=grouping, fav="0") | fields


def historical_attachment_id(entry):
    # pykeepass 4.2 filters out historical attachments in Entry.attachments.
    return int(entry._element.find("Binary/Value").get("Ref"))


class LastPassDeltaTest(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.folder = Path(folder.name)
        self.old = self.folder / "old.csv"
        self.new = self.folder / "new.csv"
        self.base = self.folder / "base.kdbx"
        self.delta = self.folder / "delta.kdbx"

    def csv(self, path, rows, *, has_otp=True, encoding="utf-8"):
        columns = [column for column in COLUMNS if has_otp or column != "totp"]
        with path.open("w", newline="", encoding=encoding) as output:
            writer = csv.DictWriter(output, columns, extrasaction="ignore")
            writer.writeheader()
            writer.writerows(rows)

    def script(self, *args, base_password=BASE_PASSWORD, output_password=DELTA_PASSWORD):
        env = dict(os.environ, KEEPASS_BASE_PASSWORD=base_password,
                   KEEPASS_MASTER_PASSWORD=output_password)
        return subprocess.run([sys.executable, SCRIPT, *args], env=env, cwd=self.folder,
                              capture_output=True, text=True, timeout=30)

    def base_from(self, rows, *, has_otp=True):
        self.csv(self.old, rows, has_otp=has_otp)
        result = self.script("-i", self.old, "-o", self.base, output_password=BASE_PASSWORD)
        self.assertEqual(result.returncode, 0, result.stderr)
        return PyKeePass(self.base, password=BASE_PASSWORD)

    def compare(self, *options, output=None, **credentials):
        return self.script("--previous", self.old, "-i", self.new, "--base", self.base,
                           "-o", output or self.delta, *options, **credentials)

    def open_delta(self):
        return PyKeePass(self.delta, password=DELTA_PASSWORD)

    @unittest.skipUnless(KPX, "keepassxc-cli is required for the merge integration test")
    def test_merge_updates_original_uuid_and_preserves_history_and_attachments(self):
        original = record("Change")
        unchanged = record("Unchanged")
        db = self.base_from([original, unchanged])
        entry = db.find_entries(title="Change", first=True)
        group = entry.group
        group.notes = "KeePassXC group notes"
        group.mtime = TIME
        untouched = db.find_entries(title="Unchanged", first=True)
        untouched.add_attachment(db.add_binary(b"not included in the delta"), "unrelated.txt")
        entry.password = "historical-password"
        entry.mtime = TIME
        historical = entry.add_attachment(db.add_binary(b"historical binary"), "history.txt")
        entry.save_history()
        historical.delete()
        entry.password = original["password"]
        entry.notes = "KeePassXC-only notes"
        entry.set_custom_property("Local field", "keep this", protect=True)
        entry.tags = ["local"]
        current_attachment = entry.add_attachment(db.add_binary(b"current binary"), "current.txt")
        self.assertNotEqual(current_attachment.id, historical_attachment_id(entry.history[0]))
        entry.mtime = TIME + timedelta(seconds=1)
        icon_id = base64.b64encode(uuid.uuid4().bytes).decode()
        entry._element.append(E.CustomIconUUID(icon_id))
        meta = db.tree.find("Meta")
        icons = meta.find("CustomIcons")
        if icons is None:
            icons = E.CustomIcons()
            meta.append(icons)
        icons.append(E.Icon(E.UUID(icon_id), E.Data(ICON)))
        for item in meta.findall("CustomData"):
            meta.remove(item)
        meta.append(E.CustomData(
            E.Item(E.Key("_LAST_MODIFIED"), E.Value("Wed Jan 1 00:00:00 2025 GMT")),
            E.Item(E.Key("KeepSetting"), E.Value("base metadata")),
        ))
        db.save()
        base_before = self.base.read_bytes()
        self.csv(self.new, [unchanged, original | {"password": "incoming-password"},
                            record("New", "new-secret", r"Work\New\Child")], encoding="utf-8-sig")

        result = self.compare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 added, 1 updated", result.stdout)
        self.assertEqual(self.base.read_bytes(), base_before)
        self.assertEqual(stat.S_IMODE(self.delta.stat().st_mode), 0o600)
        delta = self.open_delta()
        self.assertEqual({item.title for item in delta.entries}, {"Change", "New"})
        change = delta.find_entries(title="Change", first=True)
        self.assertEqual(change.uuid, entry.uuid)
        self.assertEqual(change.group.uuid, group.uuid)
        self.assertEqual(change.mtime, entry.mtime + timedelta(seconds=1))
        self.assertEqual(change.notes, entry.notes)
        self.assertEqual(change.attachments[0].data, b"current binary")
        self.assertEqual(delta.binaries[historical_attachment_id(change.history[0])],
                         b"historical binary")
        self.assertNotIn(b"not included in the delta", delta.binaries)
        self.assertEqual(delta.tree.findtext("Meta/CustomIcons/Icon/UUID"), icon_id)
        self.assertFalse(delta.tree.xpath("/KeePassFile/Meta/CustomData/Item"))

        merged_path = self.folder / "merged.kdbx"
        shutil.copyfile(self.base, merged_path)
        for _ in range(2):
            result = subprocess.run([KPX, "merge", "-q", merged_path, self.delta],
                                    input=f"{BASE_PASSWORD}\n{DELTA_PASSWORD}\n",
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
        merged = PyKeePass(merged_path, password=BASE_PASSWORD)
        changed = merged.find_entries(title="Change")
        self.assertEqual(len(changed), 1)
        changed = changed[0]
        self.assertEqual(changed.uuid, entry.uuid)
        self.assertEqual(changed.password, "incoming-password")
        self.assertEqual(changed.group.uuid, group.uuid)
        self.assertEqual(changed.group.notes, "KeePassXC group notes")
        self.assertEqual(changed.notes, "KeePassXC-only notes")
        self.assertEqual(changed.tags, ["local"])
        self.assertEqual(changed.get_custom_property("Local field"), "keep this")
        self.assertTrue(changed.is_custom_property_protected("Local field"))
        self.assertEqual(changed._element.findtext("CustomIconUUID"), icon_id)
        self.assertEqual(merged.tree.findtext("Meta/CustomIcons/Icon/Data"), ICON)
        self.assertEqual(changed.attachments[0].data, b"current binary")
        history = {version.password: version for version in changed.history}
        self.assertEqual(merged.binaries[historical_attachment_id(history["historical-password"])],
                         b"historical binary")
        self.assertEqual(merged.binaries[historical_attachment_id(history[original["password"]])],
                         b"current binary")
        self.assertEqual(merged.tree.xpath("//Meta/CustomData/Item[Key='KeepSetting']/Value/text()"),
                         ["base metadata"])
        added = merged.find_entries(title="New")
        self.assertEqual(len(added), 1)
        self.assertEqual(added[0].group.path, ["LastPass Migrated", "Work", "New", "Child"])
        self.assertEqual(merged.find_entries(title="Unchanged", first=True).uuid, untouched.uuid)

        shutil.copyfile(merged_path, self.base)
        result = self.compare("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0 added, 0 updated, 2 already applied", result.stdout)

    def test_reports_conflicts_ambiguous_rows_and_possible_rename(self):
        duplicate = record("Duplicate", "duplicate-old")
        second = duplicate | {"password": "duplicate-other"}
        removed = record("Old title", "removed-value")
        conflict = record("Conflict", "conflict-old")
        safe = record("Safe", "safe-old", extra="two\nlines")
        db = self.base_from([duplicate, second, removed, conflict, safe])
        db.find_entries(title="Conflict", first=True).password = "local-password"
        db.save()
        self.csv(self.new, [safe | {"password": "safe-new"}, second,
                            duplicate | {"password": "duplicate-new"},
                            conflict | {"password": "conflict-new"},
                            removed | {"name": "New title"}])

        result = self.compare()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("1 updated", result.stdout)
        self.assertIn("old CSV line(s) 2, new CSV line(s) 5 (ambiguous CSV identity)", result.stderr)
        self.assertIn("old CSV line(s) 4 (missing from new CSV)", result.stderr)
        self.assertIn("new CSV line(s) 6 (conflicting password in KeePassXC)", result.stderr)
        self.assertIn("new CSV line(s) 7 (possible rename or move)", result.stderr)
        for secret in ("local-password", "conflict-new", "duplicate-new", "removed-value"):
            self.assertNotIn(secret, result.stdout + result.stderr)
        self.assertEqual([item.title for item in self.open_delta().entries], ["Safe"])

    def test_ambiguous_group_path_is_review_only(self):
        original = record("Ambiguous", grouping=r"Work\Nested")
        db = self.base_from([original])
        db.add_group(db.find_groups(name="Work", first=True), "Nested")
        db.save()
        self.csv(self.new, [original | {"password": "incoming"}])
        result = self.compare()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("ambiguous group path", result.stderr)
        self.assertFalse(self.delta.exists())

    def test_matches_old_rows_using_original_migration_cleanup(self):
        changed = record(" \0 Changed \0 ", "old\x01password",
                         extra="multiple\nlines with \ufffeN and \x01")
        unchanged = record("Unchanged", extra="unchanged\0note")
        blank = dict.fromkeys(COLUMNS, "") | {"extra": "\0"}
        db = self.base_from([changed, unchanged, blank])
        original = db.find_entries(title="Changed", first=True)
        self.assertEqual(original.password, "oldpassword")
        self.csv(self.new, [unchanged, changed | {"password": "new-password"},
                            record("Added", "new-entry")])

        result = self.compare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 added, 1 updated", result.stdout)
        delta = self.open_delta()
        self.assertEqual({entry.title for entry in delta.entries}, {"Added", "Changed"})
        updated = delta.find_entries(title="Changed", first=True)
        self.assertEqual(updated.uuid, original.uuid)
        self.assertEqual(updated.password, "new-password")
        self.assertEqual(updated.notes, "multiple\nlines with N and ")
        self.assertEqual(updated.notes, original.notes)

    def test_new_unstorable_values_are_reviewed_without_blocking_other_updates(self):
        change = record("Unstorable edit", "pass")
        safe = record("Safe edit", "old")
        self.base_from([change, safe])
        self.csv(self.new, [change | {"password": "pa\x01ss"}, safe | {"password": "new"},
                            record("Unstorable addition", "synthetic\0secret")])
        result = self.compare()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("new CSV line(s) 2 (characters KDBX cannot store in password)",
                      result.stderr)
        self.assertIn("new CSV line(s) 4 (characters KDBX cannot store in password)",
                      result.stderr)
        self.assertNotIn("synthetic", result.stderr)
        [entry] = self.open_delta().entries
        self.assertEqual(entry.title, "Safe edit")
        self.assertEqual(entry.password, "new")

    def test_unknown_totp_conflicts_and_blank_totp_clears(self):
        original = record("TOTP")
        db = self.base_from([original], has_otp=False)
        new = original | {"totp": "JBSWY3DPEHPK3PXP"}
        self.csv(self.new, [new])
        preview = self.script("--previous", self.old, "-i", self.new, "--base", self.base,
                              "--dry-run")
        self.assertEqual(preview.returncode, 2, preview.stderr)
        self.assertIn("conflicting otp", preview.stderr)
        self.assertFalse(self.delta.exists())

        db.find_entries(title="TOTP", first=True).otp = (
            "otpauth://totp/TOTP?secret=JBSWY3DPEHPK3PXP&period=30&digits=6&issuer=TOTP")
        db.save()
        result = self.compare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 already applied", result.stdout)
        self.assertFalse(self.delta.exists())

        self.csv(self.old, [new])
        self.csv(self.new, [original | {"password": "new-pass"}], has_otp=False)
        result = self.compare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNotNone(self.open_delta().entries[0].otp)
        self.delta.unlink()

        self.csv(self.new, [original])
        result = self.compare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(self.open_delta().entries[0].otp)

    def test_legacy_totp_is_preserved_for_manual_review(self):
        original = record("Legacy OTP")
        db = self.base_from([original])
        entry = db.entries[0]
        entry.set_custom_property("TOTP Seed", "JBSWY3DPEHPK3PXP", protect=True)
        entry.set_custom_property("TOTP Settings", "30;6")
        db.save()
        self.csv(self.new, [original | {"totp": "GEZDGNBVGY3TQOJQ"}])
        result = self.compare()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("conflicting legacy otp", result.stderr)
        self.assertFalse(self.delta.exists())

    @unittest.skipUnless(KPX, "keepassxc-cli is required for the merge integration test")
    def test_merge_preserves_untimestamped_base_metadata(self):
        original = record("Metadata")
        db = self.base_from([original])
        meta = db.tree.find("Meta")
        for item in meta.findall("CustomData"):
            meta.remove(item)
        meta.append(E.CustomData(E.Item(E.Key("LegacySetting"), E.Value("keep"))))
        db.save()
        before = self.base.read_bytes()
        self.csv(self.new, [original | {"password": "incoming"}])
        result = self.compare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.open_delta().tree.xpath("/KeePassFile/Meta/CustomData/Item"))
        self.assertEqual(self.base.read_bytes(), before)
        merged_path = self.folder / "merged.kdbx"
        shutil.copyfile(self.base, merged_path)
        result = subprocess.run([KPX, "merge", "-q", merged_path, self.delta],
                                input=f"{BASE_PASSWORD}\n{DELTA_PASSWORD}\n",
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        merged = PyKeePass(merged_path, password=BASE_PASSWORD)
        self.assertEqual(merged.tree.xpath("//Meta/CustomData/Item[Key='LegacySetting']/Value/text()"),
                         ["keep"])
        self.assertEqual(merged.entries[0].password, "incoming")

    def test_refuses_output_aliases_and_preserves_existing_output_on_bad_csv(self):
        original = record("Validate")
        self.base_from([original])
        self.csv(self.new, [original | {"password": "incoming"}])
        base_before = self.base.read_bytes()
        hard_link = self.folder / "hard-link"
        os.link(self.base, hard_link)
        soft_link = self.folder / "soft-link"
        soft_link.symlink_to(self.new)
        for alias in (self.base, self.old, hard_link, soft_link):
            with self.subTest(alias=alias.name):
                result = self.compare("--force", output=alias)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("Output refers to an input file", result.stderr)
        self.assertEqual(self.base.read_bytes(), base_before)

        self.delta.write_bytes(b"existing output")
        result = self.compare()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("Output already exists", result.stderr)
        self.csv(self.new, [original | {"password": "sensitive\x01invalid"}])
        result = self.compare("--force")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("characters KDBX cannot store", result.stderr)
        self.assertNotIn("sensitive", result.stderr)
        self.assertEqual(self.delta.read_bytes(), b"existing output")
        self.new.write_text(",".join(COLUMNS) + '\n"unclosed,field\n')
        result = self.compare("--force")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("near line 2", result.stderr)
        self.assertEqual(self.delta.read_bytes(), b"existing output")

        self.csv(self.new, [original | {"password": "incoming"}])
        result = self.compare("--force")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.open_delta().entries[0].password, "incoming")

    def test_keyfile_only_base(self):
        key = self.folder / "fixture.key"
        key.write_bytes(b"fictional fixture key")
        db = create_database(self.base, keyfile=key)
        db.add_group(db.root_group, "LastPass Migrated")
        db.save()
        self.csv(self.old, [])
        self.csv(self.new, [record("Added", grouping="")])
        result = self.compare("--base-keyfile", key, base_password="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.open_delta().entries[0].title, "Added")

    def test_legacy_conversion_still_sanitizes_without_printing_values(self):
        row = record("secret-title", "secret-pass\x01", url="http://sn", extra="entry notes")
        missing = self.script("-i", self.old, "-o", self.base, output_password=BASE_PASSWORD)
        self.assertNotEqual(missing.returncode, 0)
        self.csv(self.old, [row])
        result = self.script("-i", self.old, "-o", self.base, output_password=BASE_PASSWORD)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CSV line 2", result.stdout)
        self.assertNotIn("secret-pass", result.stdout + result.stderr)
        self.assertNotIn("secret-title", result.stdout + result.stderr)
        [entry] = PyKeePass(self.base, password=BASE_PASSWORD).entries
        self.assertEqual(entry.password, "secret-pass")
        self.assertFalse(entry.url)
        self.assertEqual(entry.group.path, ["LastPass Migrated", "Work", "Apps"])


if __name__ == "__main__":
    unittest.main()
