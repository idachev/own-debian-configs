#!/usr/bin/env python3
import os

import dropbox
from dropbox.files import DeletedMetadata

access_token = os.environ.get("DROPBOX_TOKEN")


def list_deleted_files(path=''):
    dbx = dropbox.Dropbox(access_token)

    has_more = True
    cursor = None

    while has_more:
        if cursor:
            res = dbx.files_list_folder_continue(cursor)
        else:
            res = dbx.files_list_folder(path=path, recursive=True, include_deleted=True, limit=100)

        for entry in res.entries:
            if isinstance(entry, DeletedMetadata):
                print(f"{entry.path_lower}")

        has_more = res.has_more
        cursor = res.cursor


if __name__ == '__main__':
    list_deleted_files()
