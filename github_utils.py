#!/usr/bin/env python3
"""
GitHub Utilities

Shared utilities for GitHub API scripts including:
- Environment configuration
- Data classes for commits and PR comments
- Common API operations
- JIRA ticket extraction
"""

from __future__ import annotations

import http
import logging
import os
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

from github_rate_limiter import github_request

# Environment configuration
GITHUB_API_URL = "https://api.github.com"
GITHUB_API_TOKEN = os.environ.get("GITHUB_API_TOKEN")
GITHUB_OWNER = os.environ.get("GITHUB_OWNER")
GITHUB_AUTHOR = os.environ.get("GITHUB_AUTHOR")
GITHUB_COMMENTS_LAST_DAYS = int(os.environ.get("GITHUB_COMMENTS_LAST_DAYS", default=7))
GITHUB_REPOS = os.environ.get("GITHUB_REPOS")

# GitHub API headers
github_headers = {
    'Authorization': f'Bearer {GITHUB_API_TOKEN}',
    'Content-Type': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28'
}

logger = logging.getLogger(__name__)


def setup_logging() -> None:
    """Configure logging for GitHub scripts."""
    os.environ["TZ"] = "UTC"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S%z",
    )


def get_repos_list() -> list[str]:
    """Parse GITHUB_REPOS environment variable into a list."""
    if not GITHUB_REPOS:
        raise ValueError("GITHUB_REPOS environment variable is not set")
    return [x.strip() for x in GITHUB_REPOS.split(',')]


def get_time_threshold(last_days: int) -> datetime:
    """Get datetime threshold for filtering by last N days."""
    return datetime.now(timezone.utc) - timedelta(days=last_days)


def get_time_since_iso(last_days: int) -> str:
    """Get ISO format time string for 'since' API parameter."""
    return (datetime.now(timezone.utc) - timedelta(days=last_days)).isoformat(timespec='seconds')


def parse_github_time(time_str: str) -> datetime:
    """Parse GitHub API timestamp to datetime."""
    return datetime.fromisoformat(time_str.replace("Z", "+00:00"))


@dataclass
class JiraTicketInfo:
    """Information about a JIRA ticket extracted from GitHub activity."""
    commit_msg: str
    author: str
    activity_time: str
    source: str  # 'commit', 'merge_review', 'pr_comment', 'approved_review'

    def __str__(self):
        return f"[{self.source}] commit_msg: {self.commit_msg}, author: {self.author}, time: {self.activity_time}"

    def __repr__(self):
        return self.__str__()


def get_commit_message(repo: str, commit_sha: str) -> str:
    """
    Fetch commit message for a specific commit SHA.

    Returns:
        Commit message string, or empty string on error.
    """
    url = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/commits/{commit_sha}'

    response = github_request('GET', url, headers=github_headers)

    if response.status_code != http.HTTPStatus.OK:
        logger.warning(f"Failed to get commit message, "
                       f"repo: {repo}, sha: {commit_sha}, "
                       f"Status code: {response.status_code}, "
                       f"Response body: {response.text}")
        return ""

    data = response.json()
    return data['commit']['message']


def get_pr_reviews(repo: str, pr_number: int) -> list[dict[str, Any]]:
    """Fetch reviews for a specific PR."""
    url = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/pulls/{pr_number}/reviews'

    response = github_request('GET', url, headers=github_headers)

    if response.status_code != http.HTTPStatus.OK:
        logger.warning(f"Failed to get reviews for PR: {repo}/pulls/{pr_number}, "
                       f"Status code: {response.status_code}, "
                       f"Response body: {response.text}")
        return []

    return response.json()


def get_commits(repo: str, last_days: int) -> list[dict[str, Any]]:
    """Fetch commits for a repo since last_days ago."""
    time_since = get_time_since_iso(last_days)
    url = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/commits'

    logger.info(f"Getting commits for repo: {repo}, time_since: {time_since}")

    page = 1
    all_commits: list[dict[str, Any]] = []

    while True:
        response = github_request('GET', url, headers=github_headers,
                                  params={"since": time_since, "page": page})

        if response.status_code != http.HTTPStatus.OK:
            logger.warning(f"Failed to get commits: {repo}, "
                           f"Status code: {response.status_code}, "
                           f"Response body: {response.text}")
            return []

        data = response.json()

        if len(data) == 0:
            break

        all_commits.extend(data)
        page += 1

    return all_commits


def get_pulls(repo: str, state: str, last_days: int) -> list[dict[str, Any]]:
    """
    Fetch pull requests for a repo.

    Args:
        repo: Repository name
        state: 'all', 'open', or 'closed'
        last_days: Filter by updated_at within last N days

    Returns:
        List of PR dicts from GitHub API
    """
    url = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/pulls'
    time_after = get_time_threshold(last_days)

    logger.info(f"Getting pull requests for repo: {repo}, state: {state}")

    page = 1
    all_prs: list[dict[str, Any]] = []

    while True:
        response = github_request('GET', url, headers=github_headers,
                                  params={"sort": "updated", "direction": "desc",
                                          "page": page, "state": state})

        if response.status_code != http.HTTPStatus.OK:
            logger.warning(f"Failed to get pull requests: {repo}, "
                           f"Status code: {response.status_code}, "
                           f"Response body: {response.text}")
            return []

        data = response.json()

        if len(data) == 0:
            break

        for pr in data:
            updated_at = pr["updated_at"]
            given_time = parse_github_time(updated_at)

            if given_time < time_after:
                return all_prs

            all_prs.append(pr)

        page += 1

    return all_prs


def get_pr_comments(repo: str, last_days: int) -> list[dict[str, Any]]:
    """Fetch PR review comments for a repo since last_days ago."""
    url = f'{GITHUB_API_URL}/repos/{GITHUB_OWNER}/{repo}/pulls/comments'
    time_since = get_time_since_iso(last_days)

    logger.info(f"Getting PR comments for repo: {repo}, time_since: {time_since}")

    page = 1
    all_comments: list[dict[str, Any]] = []

    while True:
        response = github_request('GET', url, headers=github_headers,
                                  params={"since": time_since, "page": page})

        if response.status_code != http.HTTPStatus.OK:
            logger.warning(f"Failed to get PR comments: {repo}, "
                           f"Status code: {response.status_code}, "
                           f"Response body: {response.text}")
            return []

        data = response.json()

        if len(data) == 0:
            break

        all_comments.extend(data)
        page += 1

    return all_comments


def extract_jira_ticket_numbers(commit_messages: list[str]) -> list[str]:
    """
    Extract JIRA ticket numbers from commit messages.

    Args:
        commit_messages: List of commit message strings

    Returns:
        Sorted list of unique JIRA ticket IDs, excluding those with '-000'
    """
    ticket_pattern = r'[A-Z]+-\d+'
    ticket_ids = set(re.findall(ticket_pattern, ' '.join(commit_messages)))

    return sorted(set(
        filter(lambda ticket_id: '-000' not in ticket_id, ticket_ids)))


def collect_tickets_by_date(
    results: list[tuple[str, list[JiraTicketInfo]]],
    author: str
) -> dict[str, set[str]]:
    """
    Collect JIRA tickets grouped by date from JiraTicketInfo results.

    This preserves the exact logic from original scripts:
    - Filter by author
    - Extract first JIRA ticket from commit_msg
    - Group by date (YYYY-MM-DD)

    Args:
        results: List of (repo, list[JiraTicketInfo]) tuples
        author: GitHub author to filter by

    Returns:
        Dict mapping date string to set of ticket IDs
    """
    all_tickets: dict[str, set[str]] = {}

    for (repo, res) in results:
        logger.info(f"Processing repo: {repo}")

        res_author = [x for x in res if x.author == author]

        if len(res_author) > 0:
            for x in res_author:
                jira_ticket = extract_jira_ticket_numbers([x.commit_msg])

                if len(jira_ticket) > 0:
                    date_only = x.activity_time.split("T")[0]

                    if date_only not in all_tickets:
                        all_tickets[date_only] = set()

                    all_tickets[date_only].add(jira_ticket[0])

    return {k: v for k, v in sorted(all_tickets.items(), key=lambda item: item[0])}


def print_tickets_by_date(all_tickets: dict[str, set[str]]) -> None:
    """Print tickets grouped by date."""
    for key, value in all_tickets.items():
        logger.info(f"{key}: {value}")
