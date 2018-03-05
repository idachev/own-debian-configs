#!/bin/bash


BUCKET_NAME=$1
MOUNT_POINT=$2

S3_URL=https://S3.wasabisys.com

s3fs "${BUCKET_NAME}" -o url=${S3_URL}  -o use_cache=/tmp -o uid=1000 -o mp_umask=002 -o multireq_max=5 "${MOUNT_POINT}"

