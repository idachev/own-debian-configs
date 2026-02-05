#!/usr/bin/env python3
"""
GitHub List Commits

Lists commits and merge commit reviews for the configured author,
extracting JIRA tickets grouped by date.
"""

import concurrent.futures
import logging

from github_utils import (
    GITHUB_AUTHOR,
    GITHUB_COMMENTS_LAST_DAYS,
    JiraTicketInfo,
    collect_tickets_by_date,
    get_commit_message,
    get_commits,
    get_pr_reviews,
    get_pulls,
    get_repos_list,
    get_time_threshold,
    parse_github_time,
    print_tickets_by_date,
    setup_logging,
)

logger = logging.getLogger(__name__)


def get_commit_messages(repo, last_days):
    """
    Get commit messages for a repo.

    Returns:
        Tuple of (repo, list[JiraTicketInfo])
    """
    logger.info(f"Getting commit messages for repo: {repo}")

    commits = get_commits(repo, last_days)
    res = []

    for commit in commits:
        commit_msg = commit['commit']['message']

        if commit['author'] is None:
            continue

        author = commit['author']['login']
        commit_time = commit['commit']['author']['date']

        res.append(JiraTicketInfo(
            commit_msg=commit_msg,
            author=author,
            activity_time=commit_time,
            source='commit'
        ))

    return repo, res


def get_merge_commits(repo, last_days):
    """
    Get merge commit reviews for a repo.

    For each closed PR with merge_commit_sha and merged_at within time range,
    creates a JiraTicketInfo for each APPROVED review.

    Returns:
        Tuple of (repo, list[JiraTicketInfo])
    """
    logger.info(f"Getting merge commits for repo: {repo}")

    time_after = get_time_threshold(last_days)
    prs = get_pulls(repo, state='closed', last_days=last_days)
    res = []

    for pr in prs:
        if not pr.get("merge_commit_sha") or not pr.get("merged_at"):
            continue

        pr_number = pr["number"]
        merge_commit_sha = pr["merge_commit_sha"]
        merged_at = pr["merged_at"]

        merged_time = parse_github_time(merged_at)

        if merged_time < time_after:
            continue

        commit_msg = get_commit_message(repo, merge_commit_sha)
        reviews = get_pr_reviews(repo, pr_number)

        for review in reviews:
            if review["state"] == "APPROVED":
                user_login = review["user"]["login"]
                approval_time = review["submitted_at"]

                res.append(JiraTicketInfo(
                    commit_msg=f"[MERGE] {commit_msg}",
                    author=user_login,
                    activity_time=approval_time,
                    source='merge_review'
                ))

    return repo, res


def get_commits_messages_concurrent(repos, last_days):
    """Fetch commits and merge commits from all repos concurrently."""
    all_res = []

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        futures = {}

        for repo in repos:
            future_commits = executor.submit(get_commit_messages,
                                             repo=repo,
                                             last_days=last_days)
            futures[future_commits] = f"{repo}:commits"

            future_merge = executor.submit(get_merge_commits,
                                           repo=repo,
                                           last_days=last_days)
            futures[future_merge] = f"{repo}:merge"

        for future in concurrent.futures.as_completed(futures):
            task_name = futures[future]
            try:
                result = future.result()
                logger.info(f"Completed: {task_name}")
                all_res.append(result)
            except Exception as e:
                logger.error(f"Failed {task_name}: {e}")

    return all_res


def main():
    setup_logging()

    repos = get_repos_list()

    all_repos_res = get_commits_messages_concurrent(repos, GITHUB_COMMENTS_LAST_DAYS)

    all_tickets = collect_tickets_by_date(all_repos_res, GITHUB_AUTHOR)

    print_tickets_by_date(all_tickets)


if __name__ == '__main__':
    main()
