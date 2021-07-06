# vSphere on Equinix Metal

This repository uses existing Equinix Terraform to deploy a single node vSphere deployment.

## Pre-requisites

* An account at [metal.equinix.com](https://metal.equinix.com)
* An API token for the Equinix API.
* An organization created via the Equinix metal console (take note of the organisation's UUID).
* A Project created via the Equinix metal console (take note of the project's UUID).
* An AWS S3 bucket - preferably not publically accessible.
* AWS IAM credentials (access/secret key) for provisioning AWS instances/VPCs/Route53 records/etc.
* AWS IAM credentials (access/secret key) for accessing your S3 bucket.
* A Route53 base domain available in AWS and accessible via your IAM credentials.
* Terraform 1.0.0 installed on your Ansible controller.

## Architecture

![Architecture](/assets/architecture.png)

Two nodes are deployed in Equinix:

* A `c3.small.x86` Ubuntu 18.04-based gateway node. This node is accessible via a public IP and is also assigned
  an IP address on the `172.16.0.0/24` network. It also hosts `dnsmasq` for DHCP assignment of IPs and DNS resolution.
* A `m3.medium.x86` ESXi node. vCenter is deployed on this node and is accessible via a public IP address.

Equinix does not provide large quantities of Elastic IPs. OpenShift clusters, to be accessible, would all need
to be placed on the public routable subnet and there will not be enough IPs to support this. Instead, we deploy
OpenShift clusters on a private subnet (`172.16.0.0/24`).

haproxy is deployed onto the Equinix edge gateway. This terminates incoming connections on the public IP to ports
`443`, `6443` and `80`. haproxy proxies the incoming connection to the appropriate VIP on the `172.16.0.0/24` network.

To support multiple incoming cluster URLs on the one public IP, haproxy applies Layer 7 routing based on 
Server Name Indication. For example, incoming requests to a hostname of `api.vsphere1.<base_domain>` would be proxied
to the VIP `172.16.0.10`.

### Fixed cluster VIPs

The variable `max_clusters` determines how many OpenShift clusters you want to provide haproxy support for. The default, and
recommended maximum, is three.

Each cluster is given fixed VIPs that you **must** use when provisioning clusters. These VIPs are hardcoded as the backends
in `haproxy.cfg` so they need to be the same:

| Cluster Number | API VIP     | Apps VIP    |
| :------------: | :---------: | :---------: |
|       1        | 172.16.0.10 | 172.16.0.11 |
|       2        | 172.16.0.20 | 172.16.0.21 |
|       3        | 172.16.0.30 | 172.16.0.31 |

Note the pattern - `172.16.0.<cluster_number>0` and `172.16.0.<cluster_number>1`.

## How it works

The repository uses the [Equinix Terraform Repo](https://github.com/equinix/terraform-metal-vsphere) to provision
the Equinix environment. 

The `provision.yml` playbook perform the following tasks:

1. Check if `terraform.tfstate` files exist in `terraform-equinix` and `terraform-aws`. If so, it considers the
   environment 'provisioned' and skips `terraform apply` again.
2. Assuming a new deployment, it will query Route53 and present a list of the available Route53 hosted zones.
3. The user chooses one of these; this becomes the 'base domain' for the deployment.
4. Equinix environment provisioning starts:
    1. The Equinix provisioning API is queried to find viable facilities (datacenters) that can host the two servers.
    2. The user is presented with the matching facilities; choose one of them.
    3. The `terraform.tfvars` file is generated for `terraform-equinix` using variables set in `group_vars/all/all.yml`.
    4. `terraform apply` is run to deploy the Equinix environment. **This takes at least 60 minutes**.
5. AWS provisioning occurs to add the required Route53 record (we use a very short TTL here to account for dynamic environments).
6. Fetch the vCenter CA certificate and store it locally on the Ansible host.
7. Deploy haproxy and template haproxy config.
8. Establish some additional `dnsmasq` records needed for local resolution.
9. Add the vCenter certificate to the system trust store.
10. Install various repos and packages (e.g. `podman`, `skopeo`).
11. Download and install into `$PATH` the `openshift-install` and `oc` binaries.
12. Deploy and configure a simple docker v2 registry.
13. Mirror the target openshift release into this registry.
14. Generate an `install-config-content-sources.yaml` and `imagecontentsourcepolicy.yaml` for disconnected deployments.
15. Dump a collection of needed detail to the screen.

## What can go wrong?

### Equinix provisioning fails due to not enough capacity

Sometimes there's just not enough capacity in a facility, contrary to what the API says. Deprovision and try again with
a different facility.

### Equinix provisioning fails due to a timeout error

This happens occasionally, and always when provisioning ESXi. The ESXi server never finishes and Equinix's API kills the
provisioning. Unfortunately there's no way back here - deprovision the environment and start again.

### Provisioning starts, but I can't see the 'esx01' server in my Equinix server list?

Brace yourself for a failure - once again, there's not enough capacity for the ESXi host. Let the playbook fail, then deprovision
and start again with a different facility.
