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
            echo "  --raw               Output raw TSV (7 fields: timestamp, ticket, repo, hash, files, ins, del)"
            echo "  (default)           Group by date with time estimates"
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
# Convert ISO timestamp to epoch seconds (portable awk, no mktime)
function iso_to_epoch(ts,    parts, dparts, tparts, y, m, d, H, M, S, epoch, ym) {
    # ts = "2026-02-18T10:30:45Z"
    split(ts, parts, "T")
    split(parts[1], dparts, "-")
    gsub(/Z$/, "", parts[2])
    split(parts[2], tparts, ":")
    y = dparts[1] + 0; m = dparts[2] + 0; d = dparts[3] + 0
    H = tparts[1] + 0; M = tparts[2] + 0; S = tparts[3] + 0
    # Days from year 1970 using a common formula
    # Adjust month: Jan/Feb are months 13/14 of the previous year
    if (m <= 2) { m += 12; y-- }
    # Julian day number calculation (integer days from epoch)
    epoch = int(365.25 * (y + 4716)) + int(30.6001 * (m + 1)) + d - 1524.5
    epoch = epoch - 2440587.5  # Convert Julian day to Unix epoch day
    epoch = int(epoch) * 86400 + H * 3600 + M * 60 + S
    return epoch
}

function format_time(mins,    h, m) {
    h = int(mins / 60)
    m = int(mins) % 60
    return sprintf("~%dh %02dm", h, m)
}

{
    # Extract date portion from ISO timestamp (first 10 chars)
    ts_date = substr($1, 1, 10)
    ticket = $2
    repo = $3
    hash_val = $4
    # Fields 5-7: diff stats (default to 0 for old 4-field entries)
    files_changed = (NF >= 5) ? ($5 + 0) : 0
    insertions = (NF >= 6) ? ($6 + 0) : 0
    deletions = (NF >= 7) ? ($7 + 0) : 0

    # Date filter
    if (start != "" && ts_date < start) next
    if (end != "" && ts_date > end) next

    # Project filter
    if (project != "" && index(ticket, project "-") != 1) next

    if (raw == "1") {
        print $0
        next
    }

    # Store every commit for time estimation
    commit_idx++
    c_ts[commit_idx] = $1
    c_date[commit_idx] = ts_date
    c_ticket[commit_idx] = ticket
    c_repo[commit_idx] = repo
    c_ins[commit_idx] = insertions
    c_del[commit_idx] = deletions
    c_files[commit_idx] = files_changed

    dates[ts_date] = 1
}
END {
    if (raw == "1") exit

    if (commit_idx == 0) {
        print "No tickets found for the specified period."
        exit
    }

    MAX_GAP = 7200  # 2 hours in seconds
    BASE_MIN = 30   # base estimate for new sessions (minutes)

    # Compute time estimate per commit.
    # For each commit, find the previous commit in the same repo on the same date.
    # If gap <= 2h, estimate = gap. Otherwise, estimate = 30min + diff/10.
    for (i = 1; i <= commit_idx; i++) {
        epoch_i = iso_to_epoch(c_ts[i])
        diff_lines = c_ins[i] + c_del[i]

        # Find most recent prior commit in same repo on same date
        best_gap = -1
        for (j = 1; j < i; j++) {
            if (c_repo[j] == c_repo[i] && c_date[j] == c_date[i]) {
                epoch_j = iso_to_epoch(c_ts[j])
                gap = epoch_i - epoch_j
                if (gap >= 0 && (best_gap < 0 || gap < best_gap)) {
                    best_gap = gap
                }
            }
        }

        if (best_gap >= 0 && best_gap <= MAX_GAP) {
            # Within session: estimate = gap in minutes
            c_est_min[i] = best_gap / 60.0
        } else {
            # New session or first commit: base + 1 min per 10 lines
            c_est_min[i] = BASE_MIN + int(diff_lines / 10)
        }
    }

    # Aggregate per (date, ticket)
    for (i = 1; i <= commit_idx; i++) {
        key = c_date[i] SUBSEP c_ticket[i]
        dt_commits[key] += 1
        dt_time[key] += c_est_min[i]
        dt_ins[key] += c_ins[i]
        dt_del[key] += c_del[i]
        # Track unique tickets per date
        if (!(key in dt_seen)) {
            dt_seen[key] = 1
            if (c_date[i] in ticket_list) {
                ticket_list[c_date[i]] = ticket_list[c_date[i]] "\n" c_ticket[i]
            } else {
                ticket_list[c_date[i]] = c_ticket[i]
            }
        }
    }

    # Sort dates
    n = 0
    for (d in dates) {
        sorted_dates[++n] = d
    }
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

        # Split tickets and sort
        split(ticket_list[d], tlist, "\n")
        tc = 0
        for (t in tlist) tc++
        for (ti = 2; ti <= tc; ti++) {
            ttmp = tlist[ti]
            tj = ti - 1
            while (tj >= 1 && tlist[tj] > ttmp) {
                tlist[tj + 1] = tlist[tj]
                tj--
            }
            tlist[tj + 1] = ttmp
        }

        day_total = 0
        for (ti = 1; ti <= tc; ti++) {
            t = tlist[ti]
            key = d SUBSEP t
            cnt = dt_commits[key]
            est = dt_time[key]
            ins = dt_ins[key]
            del = dt_del[key]
            day_total += est
            cs = (cnt == 1) ? "commit" : "commits"
            printf "  %-14s %s  (%d %s, +%d/-%d)\n", t, format_time(est), cnt, cs, ins, del
        }
        printf "  ---\n"
        printf "  Total:         %s\n\n", format_time(day_total)
    }
}
' "${LOG_FILE}"
