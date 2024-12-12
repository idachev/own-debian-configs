#!/usr/bin/env python3

"""
This scripts accepts: <jira URL> <project id/key>

The jira URL is in format: https://your-domain.atlassian.net

The user and API key should be located in: ~/.jira_api_key
The file should contain one line: JIRA_URL API_USER API_KEY

Check info on XRAY API: https://docs.getxray.app/display/XRAYCLOUD/Version+2
"""
import json
import os
import sys
import tempfile

import requests
from jira import JIRA

'''
Format of the key file:
JIRA_URL API_USER API_KEY
'''
JIRA_API_KEY_FILE = '~/.jira_api_key'

STORY_POINTS_FIELD = 'customfield_10027'
STORY_POINTS_ESTIMATES_FIELD = 'customfield_10016'

TIME_ORIGINAL_ESTIMATE_FIELD = 'timeoriginalestimate'

XRAY_CLIENT_ID = os.getenv('XRAY_CLIENT_ID')
XRAY_CLIENT_SECRET = os.getenv('XRAY_CLIENT_SECRET')

# Need to make a backup and extract the tests_*.json files and pass them here:
XRAY_EXPORT_FILES = ['export/tests_10042_0.json',
                     'export/tests_10042_1.json']


class ApiInfo(object):
    def __init__(self, api_url, api_user, api_key):
        self.api_url = api_url
        self.api_user = api_user
        self.api_key = api_key

    def __str__(self):
        return 'ApiInfo(%s, %s, api_key_len: %d)' % (self.api_url, self.api_user, len(self.api_key))


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


def search_task(jira, project_id, start_at=0):
    res = jira.search_issues(jql_str='project=' + project_id + ' AND type = Test ORDER BY created DESC',
                             startAt=start_at)
    return res


def read_xray_export_files():
    res = {}

    for iter in XRAY_EXPORT_FILES:
        with open(iter, 'rt') as f:
            data = json.load(f)
            for test in data['tests']:
                test_id = test['id']
                res[test_id] = test

    return res


XRAY_TOKEN = None


def get_xray_auth_token():
    """
    Fetches the XRAY authenticaiton token

    Need to have as system environment variables:
    XRAY_CLIENT_ID
    XRAY_CLIENT_SECRET

    To get them check here:
    https://docs.getxray.app/display/XRAYCLOUD/Global+Settings%3A+API+Keys
    :return:
    """
    global XRAY_TOKEN

    auth_url = "https://xray.cloud.getxray.app/api/v2/authenticate"
    headers = {
        "Content-Type": "application/json"
    }
    auth_payload = {
        "client_id": XRAY_CLIENT_ID,
        "client_secret": XRAY_CLIENT_SECRET
    }

    if XRAY_TOKEN is None:
        auth_response = requests.post(auth_url, json=auth_payload, headers=headers)
        auth_response.raise_for_status()
        XRAY_TOKEN = auth_response.text.strip('"')  # Remove quotes from token

    return XRAY_TOKEN


def do_backup(issue_key: str):
    print(f"Fetching test steps for {issue_key}")

    try:
        xray_headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {get_xray_auth_token()}"
        }

        # First we need to backup the test steps
        # test_steps_url = f"https://us.xray.cloud.getxray.app/api/v2/backup"
        # steps_response = requests.post(test_steps_url, json={},headers=xray_headers)
        # steps_response.raise_for_status()

        # Next is to check the status of the backup
        # jobId = "6ca52631ae6f4817a5770e7569833afe"
        # test_steps_url = f"https://us.xray.cloud.getxray.app/api/v2/backup/{jobId}/status"
        # steps_response = requests.get(test_steps_url, headers=xray_headers)
        # steps_response.raise_for_status()

        # Finally we can download the backup file
        # It redirects to AWS onetime download link
        # "https://us.xray.cloud.getxray.app/api/v2/backup/file"

        return None

    except requests.exceptions.RequestException as e:
        print(f"Error fetching test steps: {str(e)}")

        if hasattr(e.response, 'text'):
            print(f"Response content: {e.response.text}")

        return None


# You need to get a link to the image in an existing XRAY test and extract the JWT token from the query params
JWT_ATTACHMENT = "..."


def get_attachment(attachment_id: str):
    """
    Fetches the attachment content from XRAY

    The /api/v2/attachments does not work so we need to use the internal API

    :param attachment_id:
    :return:
    """
    print(f"Fetching attachment for {attachment_id}")

    try:
        # xray_headers = {
        #     "Content-Type": "application/json",
        #     "Authorization": f"Bearer {get_xray_auth_token()}"
        # }
        # url = f"https://us.xray.cloud.getxray.app/api/v2/attachments/{attachment_id}"

        url = f"https://us.xray.cloud.getxray.app/api/internal/attachments/{attachment_id}?jwt={JWT_ATTACHMENT}&inXray=true"

        response = requests.get(url)
        response.raise_for_status()

        return response.content

    except requests.exceptions.RequestException as e:
        print(f"Error fetching test steps: {str(e)}")

        if hasattr(e.response, 'text'):
            print(f"Response content: {e.response.text}")

        return None


def add_jira_attachment(jira, new_issue, attachment_content, filename):
    temp_file = tempfile.NamedTemporaryFile(delete=False)
    temp_file.write(attachment_content)
    temp_file.close()

    with open(temp_file.name, 'rb') as buffered_reader:
        attachment = jira.add_attachment(new_issue, buffered_reader, filename=filename)

    os.unlink(temp_file.name)

    return attachment


def create_spike_test(jira, project_id, xray_issue_key, existing_links, summary, description, steps):
    steps_description = ""
    for index, step in enumerate(steps):
        action = step.get('action') if 'action' in step and step['action'] else None
        result = step.get('result') if 'result' in step and step['result'] else None
        data = step.get('data') if 'data' in step and step['data'] else None

        if action is None:
            continue

        steps_description += "\n\n" + '=' * 40

        steps_description += f"\n*Step {index + 1}*"

        steps_description += f"\n\n{action}"

        if data:
            steps_description += "\n\n*Data*\n\n{code:json}" + f"{data}" + "{code}"

        if result and result != "As requested.":
            steps_description += f"\n\n*Expected Result*\n\n{result}"

    print(f"Summary: {summary}")
    # print(f"Description: {description}")
    # print(f"Steps: {steps_description}")

    new_issue = jira.create_issue(project=project_id, summary=summary, description=description,
                                  issuetype={'name': 'Spike'}, labels=['QA', 'XRAY'])

    # use this for testing
    # new_issue = jira.issue('ABC-123')

    print(f"Created new issue: {new_issue.key}")

    for existing_link in existing_links:
        if hasattr(existing_link, 'inwardIssue'):
            if existing_link.inwardIssue and new_issue.key != existing_link.inwardIssue.key:
                jira.create_issue_link(type=existing_link.type.name, inwardIssue=new_issue.key,
                                       outwardIssue=existing_link.inwardIssue.key)
        elif hasattr(existing_link, 'outwardIssue'):
            if existing_link.outwardIssue and new_issue.key != existing_link.outwardIssue.key:
                jira.create_issue_link(type=existing_link.type.name, outwardIssue=new_issue.key,
                                       inwardIssue=existing_link.outwardIssue.key)

    jira.create_issue_link(type='Relates', inwardIssue=new_issue.key, outwardIssue=xray_issue_key)

    attachment_map = {}

    for index_step, step in enumerate(steps):
        attachments = step.get('attachments') if 'attachments' in step and step['attachments'] else None
        if attachments:
            for index_attachment, attachment in enumerate(attachments):
                attachment_id = attachment.get('id') if 'id' in attachment and attachment['id'] else None
                filename = f"step_{index_step + 1}_att_{index_attachment + 1}_" + (
                    attachment.get('filename') if 'filename' in attachment and attachment['filename'] else 'image.png')
                if attachment_id:
                    attachment_content = get_attachment(attachment_id)
                    if attachment_content:
                        add_jira_attachment(jira, new_issue, attachment_content, filename)

                        attachment_map[attachment_id] = filename

    for attachment_id, filename in attachment_map.items():
        steps_description = steps_description.replace(f"xray-attachment://{attachment_id}", filename)

    jira.issue(new_issue).update(description=description + "\n" + steps_description)


def jira_export(api_info, project_id):
    res = read_xray_export_files()

    print(f'Loaded {len(res)} tests')

    jira = JIRA(api_info.api_url, basic_auth=(api_info.api_user, api_info.api_key))

    got = 1
    start_at = 0

    # Use this to skip already processed XRAY Tests issues key in case
    # something fails and need to be fixed in the code
    skip_issues = ['ABC-123', 'ABC-1232', 'ABC-1233']

    while got > 0:
        issues = search_task(jira, project_id, start_at)

        for issue in issues:
            if issue.key in skip_issues:
                continue

            print(f'Processing key: {issue.key}, id: {issue.id}, title: {issue.fields.summary}, '
                  f'description: {issue.fields.description}')

            if issue.id in res:
                existing_links = [link for link in issue.fields.issuelinks if link.type.name != 'Cloners']

                print(f'Found {issue.key} in XRAY export: {res[issue.id]}')

                create_spike_test(jira, project_id, issue.key, existing_links, issue.fields.summary,
                                  issue.fields.description,
                                  res[issue.id]['steps'])

                print("\n\n")

        got = len(issues)
        start_at += got


def main():
    if len(sys.argv) != 3:
        print('Expected 2 arguments: jira_url project_id')
        sys.exit(1)

    jira_url = sys.argv[1]
    project_id = sys.argv[2]

    api_info = read_api_info(jira_url)
    print('Loaded %s' % api_info)

    jira_export(api_info, project_id)


if __name__ == '__main__':
    main()
