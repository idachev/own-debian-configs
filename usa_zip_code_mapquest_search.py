#!/usr/bin/env python3

# ========================================
# Imports

import argparse
import re
import sys
from datetime import datetime, timezone
from os import path

import requests
from openai import OpenAI

# ========================================
# Settings

ADDRESSES_FILE = None


# ========================================
# Debugging

VERBOSE = False
DEBUG = False


def time_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def stdout_msg(msg):
    print(msg)
    sys.stdout.flush()
    sys.stderr.flush()


def stdout_msg_noln(msg):
    sys.stdout.write(msg)
    sys.stdout.flush()
    sys.stderr.flush()


def level_msg(level, msg):
    stdout_msg("%s [%s] %s" % (time_iso(), level, msg))


def log_verbose(msg):
    if VERBOSE:
        level_msg('INF', msg)


def log_verbose_nhdr(msg):
    if VERBOSE:
        stdout_msg_noln(msg)


def log_debug(msg):
    if DEBUG:
        level_msg('DBG', msg)


def log_error(msg):
    level_msg('ERR', msg)


# ========================================
# Use cases

def search_google_by_address_from_file(file_path):
    with open(file_path, 'r') as file:
        addresses = file.readlines()

    client = OpenAI()

    zip_codes = {}
    for address in addresses:
        address = address.strip()
        query = f"Return only the USA zip code for address: >>>{address}<<<, return only the zip code nothing else."

        response = client.chat.completions.create(
            model="gpt-4-turbo",
            messages=[{"role": "system", "content": "You are a browser tool specialized in web searches. Search in https://www.mapquest.com/search/"},
                      {"role": "user", "content": query}]
        )

        zip_codes[address] = response.choices[0].message.content

        log_verbose(f"Address: {address} -> Zip code: {zip_codes[address]}")

    return zip_codes


def cleanup_address_str(address):
    return re.sub(r'\s+', ' ', address).strip()


def mapquest_fetch_zip_code(address):
    url = "https://services-here.aws.mapquest.com/v1/search"
    params = {
        "query": address,
        "count": 1,
        "client": "yogi",
        "clip": "none"
    }

    headers = {
        "Host": "services-here.aws.mapquest.com",
        "User-Agent": "Chrome/58.0.3029.110",
        "Accept": "application/json"
    }

    response = requests.get(url, params=params, headers=headers)

    data = response.json()

    return data['results'][0]['address']['postalCode']


def mapquest_fetch_addresses(file_path):
    with open(file_path, 'r') as file:
        addresses = file.readlines()

    zip_codes = {}
    for address in addresses:
        address = cleanup_address_str(address) + ", USA"

        zip_codes[address] = mapquest_fetch_zip_code(address)

        log_verbose(f"Address: {address} -> Zip code: {zip_codes[address]}")

    return zip_codes


def parse_args():
    """
    Parse arguments and print help message if requested.
    """
    global ADDRESSES_FILE
    global DEBUG
    global VERBOSE

    parser = argparse.ArgumentParser(description='Script to find zip codes by USA addresses')

    parser.add_argument('addresses_file', metavar='ADDRESSES_FILE', nargs=1,
                        help='point to addresses file')

    parser.add_argument('-q', '--quiet',
                        dest="quiet",
                        action='store_true',
                        help='quiet messages')

    parser.add_argument('-v', '--debug',
                        dest="debug",
                        action='store_true',
                        help='debug messages')

    args = parser.parse_args()

    ADDRESSES_FILE = args.addresses_file[0]
    DEBUG = (not args.quiet) and args.debug
    VERBOSE = (not args.quiet) or DEBUG

    if not path.isfile(ADDRESSES_FILE) or not path.exists(ADDRESSES_FILE):
        log_error("Addresses file does not exists: %s" % ADDRESSES_FILE)
        sys.exit(1)


def main():
    parse_args()

    # search_google_by_address_from_file(ADDRESSES_FILE)
    mapquest_fetch_addresses(ADDRESSES_FILE)


# ========================================

if __name__ == '__main__':
    main()
