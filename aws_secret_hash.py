#!/usr/bin/env python3

import base64
import hashlib
import hmac
import sys

username = sys.argv[1]
app_client_id = sys.argv[2]
key = sys.argv[3]

message = bytes(username + app_client_id, 'utf-8')
key = bytes(key, 'utf-8')

secret_hash = base64.b64encode(hmac.new(key, message, digestmod=hashlib.sha256).digest()).decode()

print("SECRET HASH:", secret_hash)
