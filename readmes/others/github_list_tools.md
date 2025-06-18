# GitHub Activity Tracker

Here are Python scripts to track GitHub activity and extract JIRA ticket numbers from commits and PR reviews.

## Scripts

### github_list_commits.py
Fetches commit messages and merge commits from GitHub repositories and extracts JIRA ticket numbers.

**Features:**
- Retrieves commits from specified repositories within a date range
- Fetches merge commits and their approval information
- Extracts JIRA ticket numbers from commit messages
- Groups tickets by date
- Supports concurrent processing for multiple repositories

### github_list_comments.py
Tracks PR review comments, approvals, and merge commits to extract JIRA ticket information.

**Features:**
- Fetches PR review comments from repositories
- Retrieves PR approvals and merge commit information
- Extracts JIRA ticket numbers from commit messages
- Groups activity by date
- Supports concurrent processing for multiple repositories

## Configuration

Both scripts use environment variables for configuration:

- `GITHUB_API_TOKEN` - GitHub API token for authentication
- `GITHUB_OWNER` - GitHub organization/owner name
- `GITHUB_AUTHOR` - GitHub username to filter activity for
- `GITHUB_REPOS` - Comma-separated list of repository names
- `GITHUB_COMMENTS_LAST_DAYS` - Number of days to look back (default: 7)

## Usage Examples

### Basic Usage

```bash
# Set environment variables
export GITHUB_API_TOKEN="your_token_here"
export GITHUB_OWNER="your_github_organization_here"
export GITHUB_AUTHOR="your_github_username_here"
export GITHUB_REPOS="repo-1,repo-2,repo-3"
export GITHUB_COMMENTS_LAST_DAYS=7

# Run commit tracker
python3 github_list_commits.py

# Run comment tracker
python3 github_list_comments.py
```

## Output

Both scripts output:
- Grouped JIRA tickets by date
- Logging information about processing status
- Extracted ticket numbers in format: `YYYY-MM-DD: {TICKET-123, TICKET-456}`

Example output:
```
2024-06-10: {'SCU-1234', 'SCU-5678'}
2024-06-11: {'SCU-2345', 'SCU-6789'}
2024-06-12: {'SCU-3456'}
```

## Dependencies

- Python 3.x
- requests library
- Standard library modules: concurrent.futures, http, logging, os, re, datetime
