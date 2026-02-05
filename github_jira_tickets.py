#!/usr/bin/env python3
"""
GitHub JIRA Tickets Extractor

Optimized script that extracts JIRA tickets from both commits and comments.
Combines functionality of github_list_commits.py and github_list_comments.py
with reduced API calls by:
- Fetching PRs once and reusing for multiple purposes
- Caching commit messages to avoid duplicate fetches
- Fetching PR reviews once per PR
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


def get_jira_tickets_for_repo(repo, last_days):
    """
    Get all JIRA ticket info for a single repo from both commits and comments.

    This combines the logic from both scripts while reducing API calls:
    1. Direct commits (from github_list_commits.py)
    2. Merge commit reviews (from both scripts - fetched once)
    3. PR comments (from github_list_comments.py)
    4. Approved reviews on all PRs (from github_list_comments.py)

    Returns:
        Tuple of (repo, list[JiraTicketInfo])
    """
    results = []
    time_after = get_time_threshold(last_days)

    # Cache for commit messages to avoid duplicate API calls
    commit_msg_cache = {}

    def get_commit_msg_cached(commit_sha):
        if commit_sha not in commit_msg_cache:
            commit_msg_cache[commit_sha] = get_commit_message(repo, commit_sha)
        return commit_msg_cache[commit_sha]

    # ==========================================================================
    # 1. Direct commits (from github_list_commits.py)
    # ==========================================================================
    logger.info(f"[{repo}] Fetching direct commits...")
    commits = get_commits(repo, last_days)

    for commit in commits:
        commit_msg = commit['commit']['message']

        if commit['author'] is None:
            continue

        author = commit['author']['login']
        commit_time = commit['commit']['author']['date']

        # Cache the commit message
        if 'sha' in commit:
            commit_msg_cache[commit['sha']] = commit_msg

        results.append(JiraTicketInfo(
            commit_msg=commit_msg,
            author=author,
            activity_time=commit_time,
            source='commit'
        ))

    # ==========================================================================
    # 2. PR comments (from github_list_comments.py)
    # ==========================================================================
    logger.info(f"[{repo}] Fetching PR comments...")
    pr_comments = get_pr_comments(repo, last_days)

    for pr_comment in pr_comments:
        commit_id = pr_comment["commit_id"]
        commit_msg = get_commit_msg_cached(commit_id)

        results.append(JiraTicketInfo(
            commit_msg=commit_msg,
            author=pr_comment['user']['login'],
            activity_time=pr_comment['created_at'],
            source='pr_comment'
        ))

    # ==========================================================================
    # 3. Fetch ALL PRs once (state=all) and process in single loop:
    #    - Approved reviews (from github_list_comments.py add_approved_reviews)
    #    - Merge commit reviews (from both scripts)
    # ==========================================================================
    logger.info(f"[{repo}] Fetching all PRs...")
    all_prs = get_pulls(repo, state='all', last_days=last_days)

    # Cache PR reviews to avoid fetching twice
    pr_reviews_cache = {}

    def get_pr_reviews_cached(pr_number):
        if pr_number not in pr_reviews_cache:
            pr_reviews_cache[pr_number] = get_pr_reviews(repo, pr_number)
        return pr_reviews_cache[pr_number]

    # Process all PRs in a single loop for both approved reviews and merge commits
    for pr in all_prs:
        pr_number = pr["number"]
        pr_title = pr["title"]
        merge_commit_sha = pr.get("merge_commit_sha")
        merged_at = pr.get("merged_at")

        reviews = get_pr_reviews_cached(pr_number)

        # Check if this is a merged PR within time range (for merge_review source)
        is_merged_in_range = False
        if merge_commit_sha and merged_at:
            merged_time = parse_github_time(merged_at)
            is_merged_in_range = merged_time >= time_after

        for review in reviews:
            if review["state"] == "APPROVED":
                user_login = review["user"]["login"]
                approval_time = review["submitted_at"]

                # 1. Add approved_review (from github_list_comments.py add_approved_reviews)
                # Use merge_commit_sha if available, else pr_title
                if merge_commit_sha:
                    commit_msg = get_commit_msg_cached(merge_commit_sha)
                else:
                    commit_msg = pr_title

                results.append(JiraTicketInfo(
                    commit_msg=commit_msg,
                    author=user_login,
                    activity_time=approval_time,
                    source='approved_review'
                ))

                # 2. Add merge_review if PR was merged within time range
                # (from github_list_commits.py get_merge_commits)
                if is_merged_in_range:
                    results.append(JiraTicketInfo(
                        commit_msg=f"[MERGE] {commit_msg}",
                        author=user_login,
                        activity_time=approval_time,
                        source='merge_review'
                    ))

    logger.info(f"[{repo}] Found {len(results)} total activities")
    return repo, results


def get_jira_tickets_concurrent(repos, last_days):
    """
    Fetch JIRA tickets from all repos concurrently.

    Args:
        repos: List of repository names
        last_days: Number of days to look back

    Returns:
        List of (repo, list[JiraTicketInfo]) tuples
    """
    all_res = []

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        futures = {}

        for repo in repos:
            future = executor.submit(get_jira_tickets_for_repo,
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

    logger.info(f"Fetching JIRA tickets for {len(repos)} repos, last {GITHUB_COMMENTS_LAST_DAYS} days")
    logger.info(f"Author filter: {GITHUB_AUTHOR}")

    all_repos_res = get_jira_tickets_concurrent(repos, GITHUB_COMMENTS_LAST_DAYS)

    all_tickets = collect_tickets_by_date(all_repos_res, GITHUB_AUTHOR)

    logger.info("=" * 60)
    logger.info("JIRA Tickets by Date:")
    logger.info("=" * 60)
    print_tickets_by_date(all_tickets)


if __name__ == '__main__':
    main()
