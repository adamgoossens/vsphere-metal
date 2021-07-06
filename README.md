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
7. Deploy haproxy and template haproxy config; start the haproxy service.
8. Establish some additional `dnsmasq` records needed for local resolution.
9. Add the vCenter certificate to the Equinix gateway's trust store.
10. Install various repos and packages (e.g. `podman`, `skopeo`).
11. Download and install into `/usr/local/bin` the `openshift-install` and `oc` binaries.
12. Deploy and configure a simple docker v2 registry.
13. Mirror the target openshift release into this registry.
14. Generate an `install-config-content-sources.yaml` and `imagecontentsourcepolicy.yaml` for disconnected deployments.
15. Dump a collection of needed detail to the screen.

## How do I run this?

Firstly - clone the required submodule:

```
git submodule init
```

To provision:

```
ansible-playbook -i localhost, provision.yml --ask-vault-pass
```

To deprovision:

```
ansible-playbook -i localhost, deprovision.yml --ask-vault-pass
```

Skip `--ask-vault-pass` if you aren't using Ansible Vault for the sensitive values.

## What does success look like?

The following prompt before the playbook terminates:

```
[pause]
Deployment complete.

Equinix Gateway is available at <gateway_ip>
  ssh root@<gateway_ip> -i <ssh_key_path>

vCenter is available at https://<vcenter_ip>

vCenter credentials are Administrator@vsphere.local / <vsphere_pass_here>

API and apps URLs for up to 3 have been configured:

  Cluster 1
    - https://api.vsphere1.metal.adamgoossens.com
    - *.apps.vsphere1.metal.adamgoossens.com (both HTTP and HTTPS)
    
    API VIP: 172.16.0.10
    Apps VIP: 172.16.0.11

  Cluster 2
    - https://api.vsphere2.metal.<base_domain>
    - *.apps.vsphere2.metal.<base_domain> (both HTTP and HTTPS)
    
    API VIP: 172.16.0.20
    Apps VIP: 172.16.0.21

  Cluster 3
    - https://api.vsphere3.metal.<base_domain>
    - *.apps.vsphere3.metal.<base_domain> (both HTTP and HTTPS)
    
    API VIP: 172.16.0.30
    Apps VIP: 172.16.0.31


The cluster URLs above will resolve to the Elastic IP of the AWS gateway 
node from outside vSphere; they will resolve to the respective VIPs from within vSphere.

vSphere certificate is available in the file vc.pem in this directory.

A Secret has been created that will add this vSphere instance as a provider
connection in ACM; see the file vsphere-acm-secret.yaml in this directory. Create that
Secret into a namespace of your choosing and a new provider should appear in ACM labelled
'vsphere-equinix'.
```

You will have a Kubernetes secret named `vsphere-acm-secret.yaml` in your playbook local directory -
use this to quickly add vSphere as a provider to ACM.

## What can I configure?

See `group_vars/all/all.yml` ; these are documented.

You may wish to provide the sensitive values in an Ansible Vault; the default values in `group_vars/all/all.yml` assume this.

## I don't like the default cluster name prefix 'vsphere'. Can I change that?

Yes, see `cluster_name_prefix` in `group_vars/all/all.yml`.

## Can I provision more than one ESXi host?

Yes, see the `esxi_host_count` variable.

You'll probably want to change the `esxi_host_size` variable to something smaller, like `c3.medium.x86`.

This will also trigger some additional deployment logic in the Equinix terraform, namely the configuration of vSAN. YMMV here.

## What do I get in the standard deployment?

The default ESXi host used here (`m3.large.x86`) has the following specifications:

* 24 cores / 48 threads @ 2.5GHz (AMD EPYC)
* 256 GB DDR4
* 2x 3.8TB NVMe.

More than enough for a few OCP clusters.

## How long does it take?

60 minutes. 99% of that time is waiting for ESXi and vCenter to provision with Terraform.

Definitely something you want to spin up early if you have a demonstration planned.

## Is it safe to run multiple times?

Yes, however the Terraform portion will be skipped once the `terraform.tfstate` file exists. It will not try to
run it twice. The rest is just standard Ansible modules.

## How much does this cost?

Currently, as of July 2021, the prices for the environment are around $2 - $2.50 USD per hour. It takes at least an hour to provision.

Best not to leave this running long term.

## What can go wrong?

There's a few ways the provisioning can go sideways. The solution in all cases is to deprovision and start again.

### Equinix provisioning fails due to not enough capacity

Sometimes there's just not enough capacity in a facility, contrary to what the API says. Deprovision and try again with
a different facility.

### Equinix provisioning fails due to a timeout error

This happens occasionally, and always when provisioning ESXi. The ESXi server never finishes and Equinix's API kills the
provisioning. Unfortunately there's no way back here - deprovision the environment and start again.

### Provisioning starts, but I can't see the 'esx01' server in my Equinix server list?

Brace yourself for a failure - once again, there's not enough capacity for the ESXi host. Let the playbook fail, then deprovision
and start again with a different facility.


