#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_FILE="${HOME}/.local/share/jira-commit-log/commits.log"

# --- Defaults ---
MODE="today"
FILTER_DATE=""
FILTER_DAYS=""
FILTER_PROJECT=""
RAW=0

# --- Parse arguments ---
while [ $# -gt 0 ]; do
    case "$1" in
        --date)
            MODE="date"
            FILTER_DATE="$2"
            if [ -z "${FILTER_DATE}" ]; then
                echo "Error: --date requires YYYY-MM-DD argument" >&2
                exit 1
            fi
            shift 2
            ;;
        --days)
            MODE="days"
            FILTER_DAYS="$2"
            if [ -z "${FILTER_DAYS}" ] || ! [[ "${FILTER_DAYS}" =~ ^[0-9]+$ ]]; then
                echo "Error: --days requires a positive integer argument" >&2
                exit 1
            fi
            shift 2
            ;;
        --all)
            MODE="all"
            shift
            ;;
        --project)
            FILTER_PROJECT="$2"
            if [ -z "${FILTER_PROJECT}" ]; then
                echo "Error: --project requires a prefix argument (e.g., LITE)" >&2
                exit 1
            fi
            shift 2
            ;;
        --raw)
            RAW=1
            shift
            ;;
        --help|-h)
            echo "Usage: jira_commit_log.sh [OPTIONS]"
            echo ""
            echo "Query Jira tickets extracted from git commit messages."
            echo ""
            echo "Modes (mutually exclusive):"
            echo "  (default)           Show today's tickets"
            echo "  --date YYYY-MM-DD   Show tickets for a specific date"
            echo "  --days N            Show tickets for the last N days"
            echo "  --all               Show all tickets"
            echo ""
            echo "Filters:"
            echo "  --project PREFIX    Only show tickets matching PREFIX (e.g., LITE)"
            echo ""
            echo "Output:"
            echo "  --raw               Output raw TSV (timestamp, ticket, repo, hash)"
            echo "  (default)           Group by date, list unique tickets"
            echo ""
            echo "Examples:"
            echo "  jira_commit_log.sh                          # today"
            echo "  jira_commit_log.sh --days 7                 # last 7 days"
            echo "  jira_commit_log.sh --date 2026-02-13        # specific day"
            echo "  jira_commit_log.sh --days 30 --project LITE # filtered"
            echo "  jira_commit_log.sh --raw                    # raw TSV"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Use --help for usage." >&2
            exit 1
            ;;
    esac
done

# --- Check log file ---
if [ ! -f "${LOG_FILE}" ]; then
    echo "No commit log found at ${LOG_FILE}"
    echo "Run jira_commit_log_setup.sh first, then make some commits."
    exit 0
fi

# --- Compute date range ---
case "${MODE}" in
    today)
        START_DATE="$(date '+%Y-%m-%d')"
        END_DATE="${START_DATE}"
        ;;
    date)
        START_DATE="${FILTER_DATE}"
        END_DATE="${FILTER_DATE}"
        ;;
    days)
        START_DATE="$(date -d "${FILTER_DAYS} days ago" '+%Y-%m-%d')"
        END_DATE="$(date '+%Y-%m-%d')"
        ;;
    all)
        START_DATE=""
        END_DATE=""
        ;;
esac

# --- Query with awk (single pass) ---
awk -F'\t' -v start="${START_DATE}" -v end="${END_DATE}" \
    -v project="${FILTER_PROJECT}" -v raw="${RAW}" '
{
    # Extract date portion from ISO timestamp (first 10 chars)
    ts_date = substr($1, 1, 10)
    ticket = $2
    repo = $3
    hash = $4

    # Date filter
    if (start != "" && ts_date < start) next
    if (end != "" && ts_date > end) next

    # Project filter
    if (project != "" && index(ticket, project "-") != 1) next

    if (raw == "1") {
        print $0
        next
    }

    # Track unique tickets per date
    key = ts_date SUBSEP ticket
    if (!(key in seen)) {
        seen[key] = 1
        dates[ts_date] = 1
        if (ts_date in tickets) {
            tickets[ts_date] = tickets[ts_date] "\n" ticket
        } else {
            tickets[ts_date] = ticket
        }
    }
}
END {
    if (raw == "1") exit

    # Sort dates
    n = 0
    for (d in dates) {
        sorted_dates[++n] = d
    }
    # Simple insertion sort (few dates)
    for (i = 2; i <= n; i++) {
        tmp = sorted_dates[i]
        j = i - 1
        while (j >= 1 && sorted_dates[j] > tmp) {
            sorted_dates[j + 1] = sorted_dates[j]
            j--
        }
        sorted_dates[j + 1] = tmp
    }

    for (i = 1; i <= n; i++) {
        d = sorted_dates[i]
        printf "=== %s ===\n", d
        # Split and sort tickets for this date
        split(tickets[d], tlist, "\n")
        # Count tickets
        tc = 0
        for (t in tlist) tc++
        # Simple insertion sort
        for (ti = 2; ti <= tc; ti++) {
            ttmp = tlist[ti]
            tj = ti - 1
            while (tj >= 1 && tlist[tj] > ttmp) {
                tlist[tj + 1] = tlist[tj]
                tj--
            }
            tlist[tj + 1] = ttmp
        }
        for (ti = 1; ti <= tc; ti++) {
            printf "  %s\n", tlist[ti]
        }
        printf "\n"
    }

    if (n == 0) {
        print "No tickets found for the specified period."
    }
}
' "${LOG_FILE}"
