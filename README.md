# K3s for Arc
Environment to deploy Arc Data Services in a fresh K3s Cluster.

<!-- TOC depthfrom:2 -->

- [K3s for Arc](#k3s-for-arc)
  - [Creating the host](#creating-the-host)
    - [Sizing](#sizing)
  - [K3s install](#k3s-install)
  - [`arc-ci-launcher` deploy](#arc-ci-launcher-deploy)
  - [Notes on lessons learned with K3s](#notes-on-lessons-learned-with-k3s)
    - [Reduced image size will lead to more deployment resiliency](#reduced-image-size-will-lead-to-more-deployment-resiliency)
    - [Exposing configurable `requests` and `limits` at the Data Controller CRD for each control plane component](#exposing-configurable-requests-and-limits-at-the-data-controller-crd-for-each-control-plane-component)
    - [DNS differences in K3s](#dns-differences-in-k3s)
    - [Kubernetes backing store, "KINE"](#kubernetes-backing-store-kine)
    - [K3s code changes compared to github.com/kubernetes/kubernetes](#k3s-code-changes-compared-to-githubcomkuberneteskubernetes)
      - [Major components they've  dropped from K8s](#major-components-theyve--dropped-from-k8s)
      - [Components they’ve added into K3s](#components-theyve-added-into-k3s)
      - [Misc Notes](#misc-notes)
  - [Summary](#summary)

<!-- /TOC -->

## Creating the host

### Sizing
For Arc (HAIKU) + Arc Data (no DB instances), a 3 worker-node AKS cluster with all CRDs running has the following specs:
* 1 x [Standard_DS3_v2](https://learn.microsoft.com/en-us/azure/virtual-machines/dv2-dsv2-series#dsv2-series) = 4 core,	14 GB
  Which is 12 cores, 42 GB RAM.

With all pods deployed, each Node has about ~50% base-request utilization:
```bash
kubectl describe node aks-agentpool-18830753-vmss00000d

  Resource           Requests      Limits
  --------           --------      ------
  cpu                1625m (42%)   12290m (318%)
  memory             6010Mi (55%)  42174Mi (391%)
```
This means that roughly, our K3s host, single-node to start should need:
* To serve up pod requests: 6 cores, 21 GB RAM
* [K3s Control Plane](https://rancher.com/docs/k3s/latest/en/installation/installation-requirements/resource-profiling/): 1 core, 1 GB RAM

> Let's start with **8 core** and **20 GB RAM** and see if we face resource pressure.

```powershell
# ===========================================================
# Creation
# ===========================================================
multipass launch -n arc-k3s -c 8 -m 20G -d 50G 20.04

# Follow the rest of this README for setup
# ===========================================================
# Destruction steps - for later as required
# ===========================================================
# Stop
multipass stop arc-k3s

# Delete
multipass delete arc-k3s
multipass purge
```

## K3s install

```powershell
multipass transfer scripts/install-k3s.sh arc-k3s:.
multipass exec arc-k3s -- chmod +x install-k3s.sh
multipass exec arc-k3s -- ./install-k3s.sh
```

## `arc-ci-launcher` deploy
```bash
multipass exec arc-k3s -- git clone https://github.com/microsoft/azure_arc.git

# Pass in the pre-prepped env vars:
tree /f
# └───launcher
#    ├───base
#    │   └───configs
#    │           .test.env              # 1
#    │
#    └───overlays
#        └───k3s
#            │   kustomization.yaml     # 2
#            │
#            └───configs
#                    patch.json         # 3

$local="launcher"
$remote="/home/ubuntu/azure_arc/arc_data_services/test/launcher"

multipass transfer $local/base/configs/.test.env arc-k3s:$remote/base/configs/.test.env

multipass exec arc-k3s -- mkdir -p $remote/overlays/k3s/configs
multipass transfer $local/overlays/k3s/configs/patch.json arc-k3s:$remote/overlays/k3s/configs/patch.json
multipass transfer $local/overlays/k3s/kustomization.yaml arc-k3s:$remote/overlays/k3s/kustomization.yaml

# Run a launch script that follows launcher
multipass transfer scripts/launch-ci.sh arc-k3s:.
multipass exec arc-k3s -- chmod +x launch-ci.sh
multipass exec arc-k3s -- ./launch-ci.sh $remote/overlays/k3s

# Clean up Launcher
multipass exec arc-k3s -- kubectl delete -k $remote/overlays/k3s
```

## Notes on lessons learned with K3s

### Reduced image size will lead to more deployment resiliency

Our images each take up about **2.5 GB _each_**, which adds up across the control plane. Depending on the ingress speed, pulling the images might be tough for smaller clusters. E.g. my underlying Ubuntu host got a handful of `imagePull` failures because of download throttling from ISP:
    
```text
Events:
  Type     Reason     Age                    From               Message
  ----     ------     ----                   ----               -------
  Normal   Scheduled  5m56s                  default-scheduler  Successfully assigned ns1663589732/controldb-0 to arc-k3s
  Normal   Pulling    5m54s                  kubelet            Pulling image "mcr.microsoft.com/arcdata/arc-monitor-fluentbit:v1.11.0_2022-09-13"
  Normal   Pulled     5m49s                  kubelet            Successfully pulled image "mcr.microsoft.com/arcdata/arc-monitor-fluentbit:v1.11.0_2022-09-13" in 5.436781507s
  Normal   Created    5m49s                  kubelet            Created container fluentbit
  Normal   Started    5m49s                  kubelet            Started container fluentbit
  Warning  Failed     5m14s                  kubelet            Failed to pull image "mcr.microsoft.com/arcdata/arc-controller-db:v1.11.0_2022-09-13": rpc error: code = Unknown desc = failed to pull and unpack image "mcr.microsoft.com/arcdata/arc-controller-db:v1.11.0_2022-09-13": failed to copy: httpReadSeeker: failed open: failed to do request: Get "https://eastus.data.mcr.microsoft.com/aba285c624a04409823b708c7a50e7b9-jttfjm99vo//docker/registry/v2/blobs/sha256/09/093eb31e4b6a2880fe0b82336e2d429a44d9c06d7ed70f71a2634a6a501a1f55/data?se=2022-09-19T12%3A42%3A56Z&sig=eNeKnR7zBos8BDmJgc2uZBDor62m4Mz%2Fd6Bt2qUhKhY%3D&sp=r&spr=https&sr=b&sv=2016-05-31&regid=aba285c624a04409823b708c7a50e7b9": dial tcp: lookup eastus.data.mcr.microsoft.com on 127.0.0.53:53: read udp 127.0.0.1:41824->127.0.0.53:53: i/o timeout
  Warning  Failed     4m48s                  kubelet            Failed to pull image "mcr.microsoft.com/arcdata/arc-controller-db:v1.11.0_2022-09-13": rpc error: code = Unknown desc = failed to pull and unpack image "mcr.microsoft.com/arcdata/arc-controller-db:v1.11.0_2022-09-13": failed to copy: httpReadSeeker: failed open: failed to do request: Get "https://mcr.microsoft.com/v2/arcdata/arc-controller-db/manifests/sha256:1e35da1fc5c6a3072d430f22a94c6560dd91f79a064b263ea228a9d2936f8707": dial tcp: lookup mcr.microsoft.com on 127.0.0.53:53: read udp 127.0.0.1:52988->127.0.0.53:53: i/o timeout
  Warning  Failed     3m44s                  kubelet            Failed to pull image "mcr.microsoft.com/arcdata/arc-controller-db:v1.11.0_2022-09-13": rpc error: code = Unknown desc = failed to pull and unpack image "mcr.microsoft.com/arcdata/arc-controller-db:v1.11.0_2022-09-13": failed to copy: httpReadSeeker: failed open: failed to do request: Get "https://eastus.data.mcr.microsoft.com/aba285c624a04409823b708c7a50e7b9-jttfjm99vo//docker/registry/v2/blobs/sha256/09/093eb31e4b6a2880fe0b82336e2d429a44d9c06d7ed70f71a2634a6a501a1f55/data?se=2022-09-19T12%3A42%3A56Z&sig=eNeKnR7zBos8BDmJgc2uZBDor62m4Mz%2Fd6Bt2qUhKhY%3D&sp=r&spr=https&sr=b&sv=2016-05-31&regid=aba285c624a04409823b708c7a50e7b9": dial tcp 204.79.197.219:443: i/o timeout
  Warning  Failed     3m44s (x3 over 5m14s)  kubelet            Error: ErrImagePull
  Normal   BackOff    3m6s (x5 over 5m14s)   kubelet            Back-off pulling image "mcr.microsoft.com/arcdata/arc-controller-db:v1.11.0_2022-09-13"
  Warning  Failed     3m6s (x5 over 5m14s)   kubelet            Error: ImagePullBackOff
  Normal   Pulling    2m51s (x4 over 5m49s)  kubelet            Pulling image "mcr.microsoft.com/arcdata/arc-controller-db:v1.11.0_2022-09-13"
  Normal   Pulled     108s                   kubelet            Successfully pulled image "mcr.microsoft.com/arcdata/arc-controller-db:v1.11.0_2022-09-13" in 1m3.623332692s
``` 
- Reducing  our overall base image footprint (e.g. mariner) would probably be the biggest win as far as K3s and edge goes - as deployments would become quicker, similar to Azure Arc connected cluster (images are fairly lean).

> Note that this is not as much of a K3s limitation (K3s seems to handle large images just fine), but more of an _edge_ limitation (where most customers use K3s). In other words, if we deployed K3s in a powerful datacenter with powerful ingress, it doesn't seem like K3s itself provides a limitation in dealing with large images, since Kubelet handles that per pod and K3s implements the same Kubelet code as full-blown K8s.


### Exposing configurable `requests` and `limits` at the Data Controller CRD for each control plane component

- On the same note, being able to expose Controller specific Requests and Limits (e.g. this for Controller, this is for Control DB, this is for `MonitorStack`) would allow saving a bit of resources, if required. Also, not all clusters are created equal, a Raspberry PI `cpu` isn't the same as a Hyper-V `cpu` or a vSphere `cpu`, so being able to expose these into the Data Controller CRD would help with any Crash Loop/OOMKills happening on specific hardware with the same `spec` (we can tell Customers with weak hardware to increase the `request` and `limit` in the CRD to trigger redeploy), e.g, if these were configurable at a per-component level:

  ```text
  spec.containers[].resources.limits.cpu
  spec.containers[].resources.limits.memory
  spec.containers[].resources.requests.cpu
  spec.containers[].resources.requests.memory
  ```

### DNS differences in K3s

- In K8s, a Node's hostname is a first class DNS citizen, because it gets a unique FQDN. In K3s, they packaged a few processes together, including the tunnel proxy, i.e. they have their own operators that serve up DNS tunnels between Server and Agent:
  
   ![K3s arch](https://www.suse.com/c/wp-content/uploads/2021/09/rancher_blog_k3s-architecture.jpeg)
   
- Therefore, there are specifics to DNS on k3s that do not use K8s standard operators (they have their own operators implemented as a workaround), Kerberos implementation would need to be specifically tested - see:
    
    [https://github.com/k3s-io/k3s/issues/1527](https://github.com/k3s-io/k3s/issues/1527)
    
This doesn't seem overly difficult to implement (i.e. Kerberos with K3s), but the use case may not be as relevant for edge, as Customers will probably not have Domain Controllers deployed and distributed at the edge (this is hard with Active Directory).

> That being said, K3s can be tested with Arc `ActiveDirectoryConnectors` in an AD domain, if required, same as how we test Kubeadm.

---

### Kubernetes backing store, "KINE"

K3s doesn’t use etcd, it uses a shim layer called KINE:
    
[https://github.com/k3s-io/kine](https://github.com/k3s-io/kine)
    
This mimcs etcd’s API on top of sqllite (CosmosDB is doing the same thing for AKS):
    
[aks-engine/readme.md at master · Azure/aks-engine](https://github.com/Azure/aks-engine/blob/master/examples/cosmos-etcd/readme.md)
    
Also, uses DQLite for WAL replication across the nodes:
    
[Dqlite - High-Availability SQLite | Dqlite](https://dqlite.io/)
    
[GitHub - rqlite/rqlite: The lightweight, distributed relational database built on SQLite](https://github.com/rqlite/rqlite)
    
Overall, this is transparent to Arc Data Services, Kubernetes resiliency is handled external to Data Controller.

---

### K3s code changes compared to github.com/kubernetes/kubernetes

Not a fork - but a distribution. Basically was competing against Kubeadm for easy deployment of K8s binaries.
    
From their repo:
    
[GitHub - k3s-io/k3s: Lightweight Kubernetes](https://github.com/k3s-io/k3s#is-this-a-fork)
    
> *No, it's a distribution. A fork implies continued divergence from the original. This is not K3s's goal or practice. K3s explicitly intends not to change any core Kubernetes functionality. We seek to remain as close to upstream Kubernetes as possible. However, **we maintain a small set of patches (well under 1000 lines)** important to K3s's use case and deployment model. 
We maintain patches for other components as well. When possible, we contribute these changes back to the upstream projects, for example, with [SELinux support in containerd](https://github.com/containerd/cri/pull/1487/commits/24209b91bf361e131478d15cfea1ab05694dc3eb). This is a common practice amongst software distributions.*
> 
> 
> ***K3s is a distribution because it packages additional components and services necessary for a fully functional cluster that go beyond vanilla Kubernetes**. These are opinionated choices on technologies for components like ingress, storage class, network policy, service load balancer, and even container runtime. These choices and technologies are touched on in more detail in the [What is this?](https://github.com/k3s-io/k3s#what-is-this) section.*
    
#### Major components they've  dropped from K8s
    
- Drop legacy 3rd party Storage Drivers that used to bloat up Kubernetes
        
  Basically, say you’re PortWorx, you’d have to write code and merge into Kubernetes Upstream. These volume plugins bloat up Kubernetes source code a lot because conformance testing all these providers is painful.
        
  [community/volume-plugin-faq.md at master · kubernetes/community](https://github.com/kubernetes/community/blob/master/sig-storage/volume-plugin-faq.md)
        
  K3s supports CSI, which is the future route anyway (see github above)
        
  [Container Storage Interface (CSI) for Kubernetes GA](https://kubernetes.io/blog/2019/01/15/container-storage-interface-ga/#why-csi)
        
- Drops Cloud Provider and Cloud SDKs in K8s (go modules), this makes the binary bloated in K8s. Dropping these helped reduce the K3s binary to ~50 MB.
  - They haven’t upstreamed this stuff because K8s maintainers will push back (they introduced most of this cloud SDK bloat into core K8s in the first place)

#### Components they’ve added into K3s
- Rootless support - similar to upstream K8s, [how it works](https://rootlesscontaine.rs/how-it-works/)
- Reverse tunnel proxy (server talks to client over 443, MSFT uses same technique for [Azure Data Factory SHIR](https://learn.microsoft.com/en-us/azure/data-factory/create-self-hosted-integration-runtime?tabs=data-factory#command-flow-and-data-flow)) - kubelet makes outbound connection to APIServer, APIServer latches on and talks back with that connection (for networking)
- kine - etcd shim on MySQL, postgres, etc
- dsqlite - sqllite replication
- busybox userspace - iptables, ipset - basically networking
- k3s binary archive - self unzips to give you Kubernetes when you run their installer
- Cert gen/rotation for tokens etc and Server bootstrapping (distributing CAs between workers agents etc)
- Manifest/images auto deploy - basically Gitops, you give it YAMLs and images and K3s comes up with your stack
- Helm chart CRD and controller for free
- Kubelet client side load balancer (to work their above outbound proxy)
- Local `storageClass` with a dynamic PV provisioner (cleans up when PVC is released) for free
    
    
#### Misc Notes
    
- Note that the binary is 50 MB, and you pull the image tarballs (decompressed is 250 MB)
- K3s scales to thousands of nodes - they’ve load tested:
  [Installation Requirements](https://rancher.com/docs/k3s/latest/en/installation/installation-requirements/#cpu-and-memory)
  -  i.e. they claim their architecture hasn't limited K8s horizontal scalability (and Rancher public docs support 500+ nodes, so this claim seems viable)
- Only thing that’s different is APIserver and ControllerManager runs as seperate processes on the same container, but that's a Kubernetes deployment flavor, as long as it doesn't impact scalability, seems to be of no concern


## Summary 
Overall, it seems that as far as design, it's not as far as "design for K3s because K3s introduces lots of limitations", but more "design lean for edge, because edge has physics limitations like storage space, image pull bandwidth, etc. For example, if we somehow threw on full blown K8s on an edge cluster, it would impose the same limitations as the exact same computers running K3s."

