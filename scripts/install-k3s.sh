#!/bin/bash
#
# Install k3s with 'local-path' storageclass.
#
# calling convention:
#  install-k3s.sh

set -e -o pipefail

# --- constants ---
TIMEOUT=180
RETRY_INTERVAL=5

# --- helper function for poliing nodes ---
poll_till_ready()
{
    echo "Verifying that the cluster is ready for use..."
    while true ; do
        if [ "$TIMEOUT" -le 0 ]; then
            echo "Cluster node failed to reach the 'Ready' state. K3s setup failed."
            exit 1
        fi
        status=`kubectl get nodes --no-headers=true | awk '{print $2}'`
        if [ "$status" == "Ready" ]; then
            echo
            echo "K3s cluster is ready."
            echo
            kubectl get nodes
            echo
            kubectl get storageclass
            break
        fi
        sleep "$RETRY_INTERVAL"
        TIMEOUT=$(($TIMEOUT-$RETRY_INTERVAL))
        echo "Cluster not ready. Retrying..."
    done
}

echo "==========================================================================="
echo " Installing K3s with StorageClass "
echo "==========================================================================="
curl -sfL https://get.k3s.io | sh - 
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
poll_till_ready

echo "==========================================================================="
echo " Kubeconfig "
echo "==========================================================================="
cat /etc/rancher/k3s/k3s.yaml

echo "==========================================================================="