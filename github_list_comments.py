#!/usr/bin/env python3

import concurrent.futures
import http
import logging
import os
import re
from datetime import datetime, timedelta, timezone

import requests as requests

GITHUB_API_URL = "https://api.github.com"

GITHUB_API_TOKEN = os.environ.get("GITHUB_API_TOKEN")

GITHUB_OWNER = os.environ.get("GITHUB_OWNER")

GITHUB_AUTHOR = os.environ.get("GITHUB_AUTHOR")

GITHUB_COMMENTS_LAST_DAYS = int(os.environ.get("GITHUB_COMMENTS_LAST_DAYS", default=7))

GITHUB_REPOS = os.environ.get("GITHUB_REPOS")

github_headers = {
    'Authorization': f'Bearer {GITHUB_API_TOKEN}',
    'Content-Type': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28'
}


class PullRequestInfo:
    def __init__(self, title, url, author):
        self.title = title
        self.url = url
        self.author = author

    def __str__(self):
        return f"title: {self.title}, url: {self.url}, author: {self.author}"

    def __repr__(self):
        return self.__str__()


class PullRequestCommentInfo:
    def __init__(self, commit_msg, author, comment_time):
        self.commit_msg = commit_msg
        self.author = author
        self.comment_time = comment_time

    def __str__(self):
        return f"commit_msg: {self.commit_msg}, author: {self.author}, comment_time: {self.comment_time}"

    def __repr__(self):
        return self.__str__()


logger = logging.getLogger(__name__)

os.environ["TZ"] = "UTC"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
)


def get_commit_message(repo, commit_sha):
    url = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/commits/{commit_sha}'

    response = requests.get(url, headers=github_headers)

    if response.status_code != http.HTTPStatus.OK:
        logger.warning(f"Failed to get commit message, "
                       f"repo: {repo}, sha: {commit_sha}, "
                       f"Status code: {response.status_code}, "
                       f"Response body: {response.text}")
        return []

    data = response.json()

    commit_msg = data['commit']['message']

    return commit_msg


def add_approved_review_info(res, repo, pr_number, pr_title, merge_commit_sha=None):
    url = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/pulls/{pr_number}/reviews'

    response = requests.get(url, headers=github_headers)

    if response.status_code != http.HTTPStatus.OK:
        logger.warning(f"Failed to get pulls reviews: {repo}/pulls/{pr_number}, "
                       f"Status code: {response.status_code}, "
                       f"Response body: {response.text}")
        return

    reviews = response.json()
    for review in reviews:
        if review["state"] == "APPROVED":
            user_login = review["user"]["login"]
            approval_time = review["submitted_at"]

            if merge_commit_sha:
                commit_msg = get_commit_message(repo, merge_commit_sha)
            else:
                commit_msg = pr_title

            pr_info = PullRequestCommentInfo(commit_msg, user_login, approval_time)

            logger.info(f"Adding approved review: {pr_info}")

            res.append(pr_info)


def add_approved_reviews(res, repo, last_days):
    url = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/pulls'

    logger.info(f"Getting pull request for repo: {repo}")

    time_after = datetime.now(timezone.utc) - timedelta(days=last_days)

    page = 1

    while True:
        response = requests.get(url, headers=github_headers,
                                params={"sort": "updated", "direction": "desc", "page": page, "state": "all"})

        if response.status_code != http.HTTPStatus.OK:
            logger.warning(f"Failed to get pulls requests: {repo}, "
                           f"Status code: {response.status_code}, "
                           f"Response body: {response.text}")
            return repo, []

        data = response.json()

        if len(data) == 0:
            break

        for pr in data:
            pr_number = pr["number"]
            pr_title = pr["title"]
            updated_at = pr["updated_at"]
            merge_commit_sha = pr.get("merge_commit_sha")

            given_time = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))

            if given_time < time_after:
                break

            add_approved_review_info(res, repo, pr_number, pr_title, merge_commit_sha)

        page += 1


def get_review_comments(repo, last_days):
    url = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/pulls/comments'

    time_since = (datetime.now(timezone.utc) - timedelta(days=last_days)).isoformat(timespec='seconds')

    logger.info(f"Getting review comments for repo: {repo}, time_since: {time_since}")

    page = 1

    res = []
    while True:
        response = requests.get(url, headers=github_headers, params={"since": time_since, "page": page})

        if response.status_code != http.HTTPStatus.OK:
            logger.warning(f"Failed to get pulls comments: {repo}, "
                           f"Status code: {response.status_code}, "
                           f"Response body: {response.text}")
            return repo, []

        data = response.json()

        if len(data) == 0:
            break

        for pr_comment in data:
            commit_msg = get_commit_message(repo, pr_comment["commit_id"])

            res.append(
                PullRequestCommentInfo(commit_msg, pr_comment['user']['login'], pr_comment['created_at']))

        page += 1

    # Add approved reviews (including merge commits)
    add_approved_reviews(res, repo, last_days)

    # Add merge commits
    add_merge_commits(res, repo, last_days)

    return repo, res


def add_merge_commits(res, repo, last_days):
    url = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/pulls'

    logger.info(f"Getting merge commits for repo: {repo}")

    time_after = datetime.now(timezone.utc) - timedelta(days=last_days)

    page = 1

    while True:
        response = requests.get(url, headers=github_headers,
                                params={"direction": "desc", "page": page,
                                        "state": "closed", "sort": "updated"})

        if response.status_code != http.HTTPStatus.OK:
            logger.warning(f"Failed to get closed pull requests: {repo}, "
                           f"Status code: {response.status_code}, "
                           f"Response body: {response.text}")
            return

        data = response.json()

        if len(data) == 0:
            break

        for pr in data:
            # Skip PRs that don't have a merge commit
            if not pr.get("merge_commit_sha") or not pr.get("merged_at"):
                continue

            pr_number = pr["number"]
            pr_title = pr["title"]
            merge_commit_sha = pr["merge_commit_sha"]
            merged_at = pr["merged_at"]

            given_time = datetime.fromisoformat(merged_at.replace("Z", "+00:00"))

            if given_time < time_after:
                break

            commit_msg = get_commit_message(repo, merge_commit_sha)

            url_reviews = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/pulls/{pr_number}/reviews'
            reviews_response = requests.get(url_reviews, headers=github_headers)

            if reviews_response.status_code != http.HTTPStatus.OK:
                logger.warning(f"Failed to get reviews for PR: {repo}/pulls/{pr_number}, "
                               f"Status code: {reviews_response.status_code}, "
                               f"Response body: {reviews_response.text}")
                continue

            reviews = reviews_response.json()
            for review in reviews:
                if review["state"] == "APPROVED":
                    user_login = review["user"]["login"]
                    approval_time = review["submitted_at"]

                    if user_login == GITHUB_AUTHOR:
                        pr_info = PullRequestCommentInfo(commit_msg, user_login, approval_time)
                        logger.info(f"Adding merge commit review: {pr_info}")
                        res.append(pr_info)

        page += 1


def get_review_comments_concurrent(repos, last_days):
    all_res = []

    with concurrent.futures.ThreadPoolExecutor() as executor:

        futures = []

        for repo in repos:
            futures.append(executor.submit(get_review_comments,
                                           repo=repo,
                                           last_days=last_days))

        for future in concurrent.futures.as_completed(futures):
            logging.info(f"Future create connectors result: {future.result()}")
            all_res.append(future.result())

    return all_res


def get_commit_messages(repo, base_branch, compare_branch):
    url = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/compare/{compare_branch}...{base_branch}'

    response = requests.get(url, headers=github_headers)

    if response.status_code != http.HTTPStatus.OK:
        logger.warning(f"Failed to get commit messages, "
                       f"repo: {repo}, {compare_branch}...{base_branch}, "
                       f"Status code: {response.status_code}, "
                       f"Response body: {response.text}")
        return []

    data = response.json()

    if 'commits' not in data:
        logger.warning(f"Missing commits, "
                       f"repo: {repo}, {compare_branch}...{base_branch}, "
                       f"Status code: {response.status_code}, "
                       f"Response body: {response.text}")
        return []

    commit_messages = [commit['commit']['message']
                       for commit in data['commits']]

    return commit_messages


def extract_jira_ticket_numbers(commit_messages):
    ticket_pattern = r'[A-Z]+-\d+'
    ticket_ids = set(re.findall(ticket_pattern, ' '.join(commit_messages)))

    return sorted(set(
        filter(lambda ticket_id: '-000' not in ticket_id, ticket_ids)))


def main():
    repos = [x.strip() for x in GITHUB_REPOS.split(',')]

    all_tickets = {}

    all_repos_res = get_review_comments_concurrent(repos, GITHUB_COMMENTS_LAST_DAYS)

    for (repo, res) in all_repos_res:
        logger.info(f"Processing repo: {repo}")

        res_author = [x for x in res if x.author == GITHUB_AUTHOR]

        if len(res_author) > 0:
            for x in res_author:
                jira_ticket = extract_jira_ticket_numbers([x.commit_msg])

                if len(jira_ticket) > 0:
                    date_only = x.comment_time.split("T")[0]

                    if date_only not in all_tickets:
                        all_tickets[date_only] = set()

                    all_tickets[date_only].add(jira_ticket[0])

    all_tickets = {k: v for k, v in sorted(all_tickets.items(), key=lambda item: item[0])}

    for key, value in all_tickets.items():
        logger.info(f"{key}: {value}")


if __name__ == '__main__':
    main()
