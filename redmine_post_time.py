#!/usr/bin/env python

import csv
import os
from copy import deepcopy

import requests
import sys

'''
Format of the key file:
REDMINE_URL_1 API_KEY_1
REDMINE_URL_2 API_KEY_2
'''
REDMINE_API_KEY_FILE = '~/.redmine_api_key'

'''
Format of the time entries CSV file:
issue id, activity id, hours, comments, spent on
1234, 10, 2, Comment 1, 2017-08-08
1234, 17, 4.5, Comment 2, 2017-08-09

Get your issue ID and activity ID from redmine.

'''

TIME_ENTRIES_URL = "/time_entries.json"
GET_TIME_ENTRY_URL = "/time_entries/%d.json"

TIME_ENTRY_TEMPLATE_JSON = {"time_entry":
    {
        "issue_id": 0,
        "activity_id": 0,
        "hours": 0,
        "comments": "",
        "spent_on": ""
    }
}

ACTIVITY_ID_PROFESSIONAL_SERVICES = 10
ACTIVITY_ID_TRACKING_ACTIVITY = 17
ACTIVITY_ID_IT_TICKET_TRACKING = 49
ACTIVITY_ID_DEVELOPMENT = 13
ACTIVITY_ID_DEV_OPS = 280
ACTIVITY_ID_PM = 281
ACTIVITY_ID_CRITICAL_ISSUE = 282
ACTIVITY_ID_AFTERHOURS_SUPPORT = 283


class ApiInfo(object):
    def __init__(self, api_url, api_key):
        self.api_url = api_url
        self.api_key = api_key

    def __str__(self):
        return 'ApiInfo(%s, api_key_len: %d)' % (self.api_url, len(self.api_key))


class TimeEntry(object):
    def __init__(self, issue_id, activity_id, hours, comments, spent_on):
        self.issue_id = int(issue_id)
        self.activity_id = int(activity_id)
        self.hours = float(hours)
        self.comments = comments
        self.spent_on = spent_on

    def __str__(self):
        return 'TimeEntry(%s, %s, %s, %s, %s)' % (self.issue_id, self.activity_id,
                                                  self.hours, self.comments, self.spent_on)


def parse_time_entries_csv(csv_file_path, time_entries):
    print('Parsing %s' % csv_file_path)

    with open(csv_file_path, 'rb') as csv_file:
        csv_reader = csv.reader(csv_file, delimiter=',', quotechar='"')
        for row in csv_reader:
            row = [unicode(cell, 'utf-8').strip() for cell in row]

            if len(row) == 0:
                continue

            if row[0].lower() == 'issue id':
                continue

            try:
                time_entry = TimeEntry(*row)
                time_entries.append(time_entry)
            except TypeError:
                raise Exception('Unexpected row size: %s' % row)

    return time_entries


def redmine_post_time_entry(api_info, time_entry):
    assert isinstance(api_info, ApiInfo)
    assert isinstance(time_entry, TimeEntry)

    headers = {'X-Redmine-API-Key': api_info.api_key}

    time_entry_json = deepcopy(TIME_ENTRY_TEMPLATE_JSON)
    time_entry_json["time_entry"]["issue_id"] = time_entry.issue_id
    time_entry_json["time_entry"]["activity_id"] = time_entry.activity_id
    time_entry_json["time_entry"]["hours"] = time_entry.hours
    time_entry_json["time_entry"]["comments"] = time_entry.comments
    time_entry_json["time_entry"]["spent_on"] = time_entry.spent_on

    response_data = requests.post(api_info.api_url + TIME_ENTRIES_URL, json=time_entry_json,
                                  headers=headers, verify=False)
    return response_data


def redmine_get_time_entry(api_info, entry_id):
    assert isinstance(api_info, ApiInfo)

    headers = {'X-Redmine-API-Key': api_info.api_key}
    response_data = requests.get(api_info.api_url + GET_TIME_ENTRY_URL % entry_id, headers=headers, verify=False)

    return response_data


def redmine_get_time_entries(api_info):
    assert isinstance(api_info, ApiInfo)

    headers = {'X-Redmine-API-Key': api_info.api_key}
    response_data = requests.get(api_info.api_url + TIME_ENTRIES_URL, headers=headers, verify=False)

    return response_data


def redmine_create_time_entries(api_info, time_entries):
    for time_entry in time_entries:
        assert isinstance(time_entry, TimeEntry)
        print('\nCreating %s' % time_entry)
        response_data = redmine_post_time_entry(api_info, time_entry)
        if response_data.status_code != 201:
            raise Exception(str(response_data) + str(response_data.text))
        else:
            print(response_data.json())


def read_api_info(api_url):
    api_key_file = os.path.expanduser(REDMINE_API_KEY_FILE)
    api_key = None
    with open(api_key_file, 'rt') as f:
        check = f.readline().strip()
        if check.startswith(api_url):
            api_key = check[len(api_url):].strip()

    if api_key is None:
        raise Exception('Failed to find API key for %s in %s' % (api_url, api_key_file))

    return ApiInfo(api_url, api_key)


def main():
    if len(sys.argv) != 3:
        print('Expected 2 arguments: redmine_url time_entries.csv')
        sys.exit(1)

    redmine_url = sys.argv[1]
    time_entries_csv = sys.argv[2]

    api_info = read_api_info(redmine_url)
    print('Loaded %s' % api_info)

    # print(redmine_get_time_entries(api_info).json())

    time_entries = []
    parse_time_entries_csv(time_entries_csv, time_entries)
    redmine_create_time_entries(api_info, time_entries)


if __name__ == '__main__':
    main()
