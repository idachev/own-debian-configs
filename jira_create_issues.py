#!/usr/bin/env python3

"""
This scripts accepts: <jira URL> <project id/key> <jira issues CSV>

The jira URL is in format: https://your-domain.atlassian.net

The user and API key should be located in: ~/.jira_api_key
The file should contain one line: JIRA_URL API_USER API_KEY

The CSV format is:
ID, Component, Summary, Priority, Description
E101, ComponentA, My epic Summary, P0, My Epic Description
E101-S01, ComponentA, My story Summary, P1, My Story Description


The epics and story IDs are prepended to the summary.

The epic ID should be in format EXYZ - where XYZ is a number - keep the length always to 4
The story ID should start with epic ID and should contain -S - this is the code check for a story
"""

import csv
import os
import sys

from jira import JIRA

'''
Format of the key file:
JIRA_URL API_USER API_KEY
'''
JIRA_API_KEY_FILE = '~/.jira_api_key'

PRIORITY_MAP = {'P0': '2', 'P1': '3', 'P2': '4'}

DEFAULT_PRIORITY = '2'

EPIC_NAME_CUSTOM_FIELD = 'customfield_10002'
EPIC_KEY_CUSTOM_FIELD = 'customfield_10005'

DEBUG_CREATE = False


class ApiInfo(object):
    def __init__(self, api_url, api_user, api_key):
        self.api_url = api_url
        self.api_user = api_user
        self.api_key = api_key

    def __str__(self):
        return 'ApiInfo(%s, %s, api_key_len: %d)' % (self.api_url, self.api_user, len(self.api_key))


class JiraIssue(object):
    def __init__(self, id, component, summary, priority, description):
        self.id = id
        self.component = component
        self.summary = summary
        self.priority = priority
        self.description = description

    def __str__(self):
        return 'JiraIssue(%s, %s, %s, %s, %s)' % (self.id, self.component,
                                                  self.summary, self.priority, self.description)


def read_api_info(api_url):
    api_key_file = os.path.expanduser(JIRA_API_KEY_FILE)
    api_user = None
    api_key = None
    with open(api_key_file, 'rt') as f:
        check = f.readline().strip()
        api_data = check.split(' ')
        if api_data[0].strip() == api_url:
            api_user = api_data[1].strip()
            api_key = api_data[2].strip()

    if api_key is None:
        raise Exception('Failed to find API key for %s in %s' % (api_url, api_key_file))

    return ApiInfo(api_url, api_user, api_key)


def parse_jira_issues_csv(csv_file_path, jira_issues):
    print('Parsing %s' % csv_file_path)

    with open(csv_file_path, 'rt') as csv_file:
        csv_reader = csv.reader(csv_file, delimiter=',', quotechar='"')
        for row in csv_reader:
            row = [cell.strip().replace('\\n', '\n') for cell in row]

            if len(row) == 0:
                continue

            if row[0].lower() == 'ID':
                continue

            try:
                jira_issue = JiraIssue(*row)
                jira_issues.append(jira_issue)
            except TypeError:
                raise Exception('Unexpected row size: %s' % row)

    return jira_issues


def dump_jira_issues(jira_issues):
    print(*jira_issues, sep='\n\n')


def get_priority(csv_priority):
    jira_priority = DEFAULT_PRIORITY
    if csv_priority != '':
        jira_priority = PRIORITY_MAP.get(csv_priority)
    return jira_priority


def build_epic_fields(project_id, jira_issue):
    jira_summary = jira_issue.id + ' - ' + jira_issue.summary

    return {
        'project': project_id,
        'summary': jira_summary,
        'description': jira_issue.description,
        'issuetype': {'name': 'Epic'},
        'priority': {'id': get_priority(jira_issue.priority)},
        EPIC_NAME_CUSTOM_FIELD: jira_summary,
        "components": [{'name': jira_issue.component}]
    }


def build_story_fields(project_id, jira_issue, epic_key):
    jira_summary = jira_issue.id + ' - ' + jira_issue.summary

    return {
        'project': project_id,
        'summary': jira_summary,
        'description': jira_issue.description,
        'issuetype': {'name': 'Story'},
        'priority': {'id': get_priority(jira_issue.priority)},
        "components": [{'name': jira_issue.component}],
        EPIC_KEY_CUSTOM_FIELD: epic_key
    }


def search_epic(jira, project_id, summary):
    res = jira.search_issues('project=' + project_id + ' AND summary ~ ' + summary + ' AND type = epic')
    if len(res) > 0:
        return res[0]

    return None


def search_story(jira, project_id, summary):
    res = jira.search_issues('project=' + project_id + ' AND summary ~ ' + summary + ' AND type = story')
    if len(res) > 0:
        return res[0]

    return None


def jira_create_issues(api_info, project_id, jira_issues):
    jira = JIRA(api_info.api_url, basic_auth=(api_info.api_user, api_info.api_key))

    for jira_issue in jira_issues:
        story_id = None
        if '-S' in jira_issue.id:
            epic_id = jira_issue.id[0:4]
            story_id = jira_issue.id
        else:
            epic_id = jira_issue.id

        print('epic_id: %s story_id: %s' % (epic_id, story_id))

        epic_key = None
        epic_issue = search_epic(jira, project_id, epic_id)
        if epic_issue:
            epic_key = epic_issue.key

        if story_id:
            story_issue = search_story(jira, project_id, story_id)
            if story_issue:
                print('Story already exist: %s, %s' % (story_issue.key, jira_issue))
                continue

            if epic_key is None:
                print('Epic does not exist: %s' % epic_id)
                break

            fields = build_story_fields(project_id, jira_issue, epic_key)

            print('Will create story: %s' % fields)
        else:
            if epic_issue:
                print('Epic already exist: %s, %s' % (epic_issue.key, jira_issue))
                continue

            fields = build_epic_fields(project_id, jira_issue)

            print('Will create epic: %s' % fields)

        if DEBUG_CREATE:
            txt = input("Create: Y/N")
            if txt != 'Y':
                break

        new_issue = jira.create_issue(fields=fields)

        print('Created: %s' % new_issue.key)

        if DEBUG_CREATE:
            txt = input("Continue: Y/N")
            if txt != 'Y':
                break


def main():
    if len(sys.argv) != 4:
        print('Expected 3 arguments: jira_url project_id jira_issues.csv')
        sys.exit(1)

    jira_url = sys.argv[1]
    project_id = sys.argv[2]
    jira_issues_csv = sys.argv[3]

    api_info = read_api_info(jira_url)
    print('Loaded %s' % api_info)

    jira_issues = []
    parse_jira_issues_csv(jira_issues_csv, jira_issues)

    # dump_jira_issues(jira_issues)

    jira_create_issues(api_info, project_id, jira_issues)


if __name__ == '__main__':
    main()
