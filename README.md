# Learn Consul HashiDays 2023 Presentation

This is a companion repo for the [HashiDays 2023 Consul Lab](https://developer.hashicorp.com/consul/tutorials/resiliency/hashidays-2023), containing sample configuration to:

- Deploy a Kubernetes cluster in AWS and Azure with Terraform
- Deploy Consul and a demo application on both clusters

On the first cluster, you will:

- Connect non-mesh services to Consul services using permissive mTLS
- Migrate services to Consul and configuring intentions on the first cluster
- Re-secure the mesh by restricting permissive mTLS

Afterwards, you will:

- Peer the two Consul clusters
- Connect the services across the peered service mesh
- Apply a service resolver to set up failover
- Stimulate a failover event

