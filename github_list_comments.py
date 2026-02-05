#!/usr/bin/env python3
"""
GitHub List Comments

Lists PR comments, approved reviews, and merge commit reviews for the configured author,
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
    get_pr_comments,
    get_pr_reviews,
    get_pulls,
    get_repos_list,
    get_time_threshold,
    parse_github_time,
    print_tickets_by_date,
    setup_logging,
)

logger = logging.getLogger(__name__)


def add_approved_review_info(res, repo, pr_number, pr_title, merge_commit_sha=None):
    """
    Add approved review info for a PR.

    For each APPROVED review, creates a JiraTicketInfo with:
    - commit_msg from merge_commit_sha if available, else pr_title
    - author from reviewer
    - activity_time from review submitted_at
    """
    reviews = get_pr_reviews(repo, pr_number)

    for review in reviews:
        if review["state"] == "APPROVED":
            user_login = review["user"]["login"]
            approval_time = review["submitted_at"]

            if merge_commit_sha:
                commit_msg = get_commit_message(repo, merge_commit_sha)
            else:
                commit_msg = pr_title

            pr_info = JiraTicketInfo(
                commit_msg=commit_msg,
                author=user_login,
                activity_time=approval_time,
                source='approved_review'
            )

            logger.info(f"Adding approved review: {pr_info}")
            res.append(pr_info)


def add_approved_reviews(res, repo, last_days):
    """
    Add approved reviews from all PRs (any state) updated within last_days.
    """
    logger.info(f"Getting pull requests for repo: {repo}")

    prs = get_pulls(repo, state='all', last_days=last_days)

    for pr in prs:
        pr_number = pr["number"]
        pr_title = pr["title"]
        merge_commit_sha = pr.get("merge_commit_sha")

        add_approved_review_info(res, repo, pr_number, pr_title, merge_commit_sha)


def add_merge_commits(res, repo, last_days):
    """
    Add merge commit reviews for closed PRs.

    Only adds reviews where the reviewer is GITHUB_AUTHOR.
    """
    logger.info(f"Getting merge commits for repo: {repo}")

    time_after = get_time_threshold(last_days)
    prs = get_pulls(repo, state='closed', last_days=last_days)

    for pr in prs:
        # Skip PRs that don't have a merge commit
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

                if user_login == GITHUB_AUTHOR:
                    pr_info = JiraTicketInfo(
                        commit_msg=commit_msg,
                        author=user_login,
                        activity_time=approval_time,
                        source='merge_review'
                    )
                    logger.info(f"Adding merge commit review: {pr_info}")
                    res.append(pr_info)


def get_review_comments(repo, last_days):
    """
    Get all review-related activities for a repo.

    Includes:
    1. PR comments
    2. Approved reviews (all PRs)
    3. Merge commit reviews (GITHUB_AUTHOR only)

    Returns:
        Tuple of (repo, list[JiraTicketInfo])
    """
    logger.info(f"Getting review comments for repo: {repo}")

    comments = get_pr_comments(repo, last_days)
    res = []

    for pr_comment in comments:
        commit_msg = get_commit_message(repo, pr_comment["commit_id"])

        res.append(JiraTicketInfo(
            commit_msg=commit_msg,
            author=pr_comment['user']['login'],
            activity_time=pr_comment['created_at'],
            source='pr_comment'
        ))

    # Add approved reviews (including merge commits)
    add_approved_reviews(res, repo, last_days)

    # Add merge commits
    add_merge_commits(res, repo, last_days)

    return repo, res


def get_review_comments_concurrent(repos, last_days):
    """Fetch review comments from all repos concurrently."""
    all_res = []

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        futures = {}

        for repo in repos:
            future = executor.submit(get_review_comments,
                                     repo=repo,
                                     last_days=last_days)
            futures[future] = repo

        for future in concurrent.futures.as_completed(futures):
            repo = futures[future]
            try:
                result = future.result()
                logger.info(f"Completed processing repo: {result[0]}")
                all_res.append(result)
            except Exception as e:
                logger.error(f"Failed to process repo {repo}: {e}")

    return all_res


def main():
    setup_logging()

    repos = get_repos_list()

    all_repos_res = get_review_comments_concurrent(repos, GITHUB_COMMENTS_LAST_DAYS)

    all_tickets = collect_tickets_by_date(all_repos_res, GITHUB_AUTHOR)

    print_tickets_by_date(all_tickets)


if __name__ == '__main__':
    main()
