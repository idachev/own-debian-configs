#!/usr/bin/env python3
"""
GitHub API Rate Limiter

Thread-safe rate limiter for GitHub API requests that:
- Tracks remaining API requests from X-RateLimit-Remaining header
- Monitors reset time from X-RateLimit-Reset header
- Enforces minimum delay between requests
- Pauses when remaining requests fall below threshold
- Handles 403/429 responses with automatic retry
- Uses connection pooling via requests.Session for better performance
"""

import logging
import threading
import time

import requests

logger = logging.getLogger(__name__)

# Rate limit threshold - start slowing down when remaining requests fall below this
RATE_LIMIT_THRESHOLD = 100
# Minimum delay between requests when rate limited (seconds)
RATE_LIMIT_MIN_DELAY = 0.5

# Global session for connection pooling
_session = requests.Session()


class GitHubRateLimiter:
    """Thread-safe rate limiter for GitHub API requests."""

    def __init__(self):
        self._lock = threading.Lock()
        self._remaining = None
        self._reset_time = None
        self._last_request_time = 0

    def update_from_response(self, response):
        """Update rate limit info from GitHub response headers."""
        with self._lock:
            remaining = response.headers.get('X-RateLimit-Remaining')
            reset_time = response.headers.get('X-RateLimit-Reset')

            if remaining is not None:
                self._remaining = int(remaining)
            if reset_time is not None:
                self._reset_time = int(reset_time)

            limit = response.headers.get('X-RateLimit-Limit')
            if self._remaining is not None and limit:
                logger.debug(f"GitHub rate limit: {self._remaining}/{limit} remaining")

    def wait_if_needed(self):
        """Wait if we're approaching rate limits."""
        wait_time = 0

        with self._lock:
            now = time.time()

            # Enforce minimum delay between requests
            time_since_last = now - self._last_request_time
            if time_since_last < RATE_LIMIT_MIN_DELAY:
                time.sleep(RATE_LIMIT_MIN_DELAY - time_since_last)

            # If we're running low on requests, calculate wait time
            if self._remaining is not None and self._remaining < RATE_LIMIT_THRESHOLD:
                if self._reset_time is not None:
                    wait_time = self._reset_time - time.time()
                    if wait_time > 0:
                        remaining = self._remaining
                        logger.warning(f"Rate limit low ({remaining} remaining). "
                                       f"Waiting {wait_time:.1f}s until reset.")

            self._last_request_time = time.time()

        # Sleep outside the lock to avoid blocking other threads
        if wait_time > 0:
            time.sleep(wait_time + 1)  # Add 1 second buffer

    def handle_rate_limit_response(self, response):
        """Handle 403/429 rate limit responses with exponential backoff."""
        if response.status_code in (403, 429):
            retry_after = response.headers.get('Retry-After')
            reset_time = response.headers.get('X-RateLimit-Reset')

            if retry_after:
                wait_time = int(retry_after)
            elif reset_time:
                wait_time = int(reset_time) - time.time() + 1
            else:
                wait_time = 60  # Default 1 minute wait

            if wait_time > 0:
                logger.warning(f"Rate limited! Waiting {wait_time:.1f}s before retry.")
                time.sleep(wait_time)
                return True  # Indicate retry is needed

        return False  # No retry needed


# Global rate limiter instance
_rate_limiter = GitHubRateLimiter()


def github_request(method, url, **kwargs):
    """Make a rate-limited request to GitHub API."""
    max_retries = 3
    response = None

    for attempt in range(max_retries):
        _rate_limiter.wait_if_needed()

        response = _session.request(method, url, **kwargs)
        _rate_limiter.update_from_response(response)

        if _rate_limiter.handle_rate_limit_response(response):
            if attempt < max_retries - 1:
                continue  # Retry after waiting
            else:
                logger.error(f"Max retries exceeded for {url}")

        return response

    return response
