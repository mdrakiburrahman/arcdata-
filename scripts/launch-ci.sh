#!/bin/bash
#
# Deploys arc-ci-launcher and runs tests.
#
# calling convention:
#  launch-ci.sh <manifest directory>

if [ $# -lt 1 ];
then
    echo "Usage: launch-ci.sh <manifest directory>"
    exit 1
fi
MANIFEST_DIR="$1"

kubectl apply -k "${MANIFEST_DIR}"
kubectl wait --for=condition=Ready --timeout=360s pod -l job-name=arc-ci-launcher -n arc-ci-launcher
kubectl logs job/arc-ci-launcher -n arc-ci-launcher --follow