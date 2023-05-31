
# HashiDays 2023 - Build scalable applications with cluster peering and failover

## Prerequisites

1. this
2. this
3. this

## Create infrastructure 

```sh
terraform init
terraform apply
```

```sh
aws eks update-kubeconfig \
  --region $(terraform output -raw region) \
  --name $(terraform output -raw cluster_name)  --alias=dc1
```

## Compile consul-k8s binary

1. this
2. this
3. maybe we can zip the current consul-k8s
4. be mindful of the im2nguyen images
5. be mindful that these environments build in EKS only (add AKS?)
6. be mindful this requires an enterprise license to use


## Deploy Consul

Deploy Consul with the enterprise license and using the custom consul-k8s binary.

```sh
secret=$(cat k8s-yamls/consul.hclic)
kubectl create namespace consul --context=dc1
kubectl create secret generic consul-ent-license --from-literal="key=${secret}" -n consul --context=dc1
./consul-k8s install -config-file k8s-yamls/values-dc1.yaml --context=dc1
```

Confirm Consul is running successfully.

```sh
kubectl get pods -n consul --context=dc1
```
```log
NAME                                           READY   STATUS    RESTARTS   AGE
consul-connect-injector-59b5b4fccd-mqmhv       1/1     Running   0          90s
consul-mesh-gateway-7b86b77d99-rhfgd           1/1     Running   0          90s
consul-server-0                                1/1     Running   0          90s
consul-webhook-cert-manager-57c5bb695c-qxc5t   1/1     Running   0          90s
```

Confirm that helm chart version is `1.2.0-dev`.

```sh
helm list -n consul --kube-context=dc1
```
```log
NAME    NAMESPACE       REVISION        UPDATED                                 STATUS     CHART            APP VERSION
consul  consul          1               2023-05-14 06:12:25.898867 -0700 PDT    deployed   consul-1.2.0-dev 1.15.1     
```

## Deploy mesh-enabled services

Deploy HashiCups v1.0.2 in dc1.

```sh
for service in {products-api,postgres,intentions-api-db}; do kubectl apply -f hashicups-v1.0.2/$service.yaml --context=dc1; done
```
```log
service/products-api created
serviceaccount/products-api created
servicedefaults.consul.hashicorp.com/products-api created
configmap/db-configmap created
deployment.apps/products-api created
service/postgres created
serviceaccount/postgres created
servicedefaults.consul.hashicorp.com/postgres created
deployment.apps/postgres created
serviceintentions.consul.hashicorp.com/postgres created
serviceintentions.consul.hashicorp.com/deny-all created
```

Verify services in k8s.

```sh
kubectl get service --context=dc1
```
```log
NAME           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kubernetes     ClusterIP   172.20.0.1      <none>        443/TCP    12m
postgres       ClusterIP   172.20.196.70   <none>        5432/TCP   4s
products-api   ClusterIP   172.20.182.94   <none>        9090/TCP   7s
```

Verify services in Consul.

```sh
kubectl exec --namespace consul --context=dc1 -it consul-server-0 -- consul catalog services
```
```log
Defaulted container "consul" out of: consul, locality-init (init)
consul
mesh-gateway
postgres
postgres-sidecar-proxy
products-api
products-api-sidecar-proxy
```

## Deploy non-mesh services

First, you need to deploy services to your Kubernetes clusters. Permissive mTLS requires TProxy (so it only works with Consul on Kubernetes for now). The following HashiCups service deployments have `consul.hashicorp.com/connect-inject` explicitly set to `false` so Consul does not register them.

(might need to do a deeper dive on tproxy and how routing works)

```sh
$ for service in {frontend,nginx,public-api,payments}; do kubectl apply -f hashicups-v1.0.2/$service.yaml --context=dc1; done
```
```log
service/frontend created
serviceaccount/frontend created
servicedefaults.consul.hashicorp.com/frontend created
deployment.apps/frontend created
service/nginx created
serviceaccount/nginx created
servicedefaults.consul.hashicorp.com/nginx created
configmap/nginx-configmap created
deployment.apps/nginx created
service/public-api created
serviceaccount/public-api created
servicedefaults.consul.hashicorp.com/public-api created
deployment.apps/public-api created
service/payments created
serviceaccount/payments created
servicedefaults.consul.hashicorp.com/payments created
deployment.apps/payments created
```

Verify services in k8s.

```sh
kubectl get service --context=dc1
```
```log
NAME           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
frontend       ClusterIP   172.20.55.80     <none>        3000/TCP   20s
kubernetes     ClusterIP   172.20.0.1       <none>        443/TCP    14m
nginx          ClusterIP   172.20.11.54     <none>        80/TCP     18s
payments       ClusterIP   172.20.172.174   <none>        1800/TCP   14s
postgres       ClusterIP   172.20.196.70    <none>        5432/TCP   117s
products-api   ClusterIP   172.20.182.94    <none>        9090/TCP   2m
public-api     ClusterIP   172.20.255.151   <none>        8080/TCP   16s
```

Verify only the following services appear in Consul at this time.

```sh
kubectl exec --namespace consul --context=dc1 -it consul-server-0 -- consul catalog services
```
```log
Defaulted container "consul" out of: consul, locality-init (init)
consul
mesh-gateway
postgres
postgres-sidecar-proxy
products-api
products-api-sidecar-proxy
```

## Migrate non-mesh services to the mesh with Permissive mTLS

### Enable permissive mTLS at mesh level

Enable permissive mTLS at the mesh level.

```sh
kubectl apply -f k8s-yamls/permissive-mtls-mesh-enable.yaml -n consul --context=dc1
```
```log
mesh.consul.hashicorp.com/mesh created
```

Open HashiCups in your browser to check the application state. In a new terminal, port-forward the `nginx` service to port `8080`. 

```sh
kubectl port-forward deploy/nginx 8080:80 --context=dc1
```

Open [localhost:8080](localhost:8080) in your browser to view the HashiCups UI. Notice that it displays no products, since the `public-api` cannot connect to the `products-api`.

### Set permissive mTLS at service level

Enable permissive mTLS on the `products-api` service to allow non-mTLS traffic.

```sh
kubectl apply -f k8s-yamls/permissive-mtls-service-products-api-enable.yaml -n consul --context=dc1
```

### Migrate services to Consul

Even though `public-api` was able to connect to `products-api` and there is a deny-all intention on the Consul datacenter, **intentions only take effect for mTLS connections**. For non-mTLS connections (permissive), intentions are effectively ignored.
As a result, use permissive mTLS with great caution and be mindful of [security best practices]().

You will migrate the remaining HashiCups services to Consul service mesh by updating the `consul.hashicorp.com/connect-inject` annotation from `false` to `true`. These changes have been implemented in the `hashicups-v1.0.2-sidecars/` folder.

```sh
for service in {frontend,nginx,public-api,payments,intentions-new-services}; do kubectl apply -f hashicups-v1.0.2-sidecars/$service.yaml --context=dc1; done
```
```log
service/frontend unchanged
serviceaccount/frontend unchanged
servicedefaults.consul.hashicorp.com/frontend unchanged
deployment.apps/frontend configured
service/nginx unchanged
serviceaccount/nginx unchanged
servicedefaults.consul.hashicorp.com/nginx unchanged
configmap/nginx-configmap unchanged
deployment.apps/nginx configured
service/public-api unchanged
serviceaccount/public-api unchanged
servicedefaults.consul.hashicorp.com/public-api unchanged
deployment.apps/public-api configured
service/payments unchanged
serviceaccount/payments unchanged
servicedefaults.consul.hashicorp.com/payments unchanged
deployment.apps/payments configured
serviceintentions.consul.hashicorp.com/public-api created
serviceintentions.consul.hashicorp.com/payments created
serviceintentions.consul.hashicorp.com/frontend created
```

Verify these services appear in Consul.

```sh
kubectl exec --namespace consul --context=dc1 -it consul-server-0 -- consul catalog services
```
```log
Defaulted container "consul" out of: consul, locality-init (init)
consul
frontend
frontend-sidecar-proxy
mesh-gateway
nginx
nginx-sidecar-proxy
payments
payments-sidecar-proxy
postgres
postgres-sidecar-proxy
products-api
products-api-sidecar-proxy
public-api
public-api-sidecar-proxy
```

### Set up intentions

```sh
kubectl apply -f hashicups-v1.0.2-sidecars/intentions-public-products-api.yaml -n consul --context=dc1
serviceintentions.consul.hashicorp.com/public-api created
```

### Restrict permissive mTLS at the service level

Restrict `products-api` to only accept mTLS traffic.

```sh
kubectl apply -f k8s-yamls/permissive-mtls-service-products-api-disable.yaml -n consul --context=dc1
```
```log
servicedefaults.consul.hashicorp.com/products-api configured
```

### Restrict permissive mTLS at the mesh level

Restrict permissive mTLS at the mesh level.

```sh
kubectl apply -f k8s-yamls/permissive-mtls-mesh-disable.yaml -n consul --context=dc1
mesh.consul.hashicorp.com/mesh configured
```

This completes the permissive mTLS section.


## Increase your application resilience with cluster peering and service failover

### Establish cluster peering between dc1 and dc2

Enable cluster peering through mesh gateways in both Consul datacenters.

```sh
for dc in {dc1,dc2}; do kubectl --context=$dc apply -f k8s-yamls/peer-through-meshgateways-enable.yaml -n consul; done
```

Configure local mode for traffic routed over the mesh gateways for both Consul datacenters.

```sh
for dc in {dc1,dc2}; do kubectl --context=$dc apply -f k8s-yamls/local-mode-meshgateways-enable.yaml; done
```

Configure a PeeringAcceptor role for `dc1`.

```sh
kubectl --context=dc1 apply -f k8s-yamls/cluster-peering-acceptor-on-dc1-for-dc2.yaml
```

Confirm you successfully created the peering acceptor custom resource definition (CRD).

```sh
kubectl --context=dc1 get peeringacceptors
```

Confirm that the PeeringAcceptor CRD generated a peering token secret.

```sh
kubectl --context=dc1 get secrets peering-token-dc2
```

Import the peering token generated in `dc1` into `dc2`.

```sh
kubectl --context=dc1 get secret peering-token-dc2 -o yaml | kubectl --context=dc2 apply -f -
```

Configure a `PeeringDialer` role for `dc2`. This will create a peering connection from `dc2` to `dc1`.

```sh
kubectl --context=dc2 apply -f k8s-yamls/cluster-peering-dialer-dc2.yaml
```

Verify that the two Consul clusters are peered.

```sh
kubectl exec --namespace=consul -it --context=dc1 consul-server-0 \
-- curl --cacert /consul/tls/ca/tls.crt --header "X-Consul-Token: $(kubectl --context=dc1 --namespace=consul get secrets consul-bootstrap-acl-token -o go-template='{{.data.token|base64decode}}')" "https://127.0.0.1:8501/v1/peering/dc2" \
| jq
```

### Configure service failover

In `dc2`, apply the `ExportedServices` custom resource file that exports the `products-api` service to `dc1`.

```sh
kubectl --context=dc2 apply -f k8s-yamls/exportedsvc-products-api.yaml
```

Confirm that the Consul cluster in `dc1` can access the `products-api` in `dc2`.

```sh
kubectl \
--context=dc1 --namespace=consul exec -it consul-server-0 \
-- curl --cacert /consul/tls/ca/tls.crt \
--header "X-Consul-Token: $(kubectl --context=dc1 --namespace=consul get secrets consul-bootstrap-acl-token -o go-template='{{.data.token|base64decode}}')" "https://127.0.0.1:8501/v1/health/connect/products-api?peer=dc2" \
| jq '.[].Service.ID,.[].Service.PeerName'
```

Apply intentions.

```sh
kubectl --context=dc2 apply -f k8s-yamls/intention-dc1-public-api-to-dc2-products-api.yaml
```

Update virtual DNS for products API and apply configuration.

```sh
kubectl apply -f hashicups-v2.0.0/public-api.yaml --context=dc2
```

Apply fail-over `dc1` on `dc2`.

```sh
kubectl apply -f k8s-yamls/service-resolver-failover-config.yaml --context=dc1
```

### Test service failover

Scale down `products-api` in `dc2` to test failover.

```sh
kubectl scale --context=dc1 deploy/products-api --replicas=0
```

Port forward the nginx service locally to port 8080 to test that `products-api` fails over successfully.

```sh
kubectl --context=dc1 port-forward deploy/nginx 8080:80
```

Scale up `products-api` in `dc1` to bring all services back into a healthy state.

```sh
kubectl scale --context=dc1 deploy/products-api --replicas=1
```

This completes the cluster peering and service failover section.

# Enable centralized visibility and control of your Consul deployments with HCP management plane

Now, connect the self-managed cluster to HCP.

1. Sign in to [https://portal.cloud.hashicorp.com](https://portal.cloud.hashicorp.com).

1. In the `Consul` section, click the button to `Link an Existing Self-Managed Cluster`.

1. Link each self-managed cluster with this naming convention:

```log
dc1-eks-ca-central-1
dc2-aks-us-east-2
```

1. Follow the on-screen instructions in the HCP portal UI. Repeat these steps for each of your Consul datacenters.

```sh
kubectl create secret generic consul-hcp-client-id --from-literal=client-id='UNIQUE-ID' --namespace consul --context=dc1 && \
kubectl create secret generic consul-hcp-client-secret --from-literal=client-secret='UNIQUE-ID' --namespace consul --context=dc1 && \
kubectl create secret generic consul-hcp-resource-id --from-literal=resource-id='UNIQUE-ID' --namespace consul --context=dc1
```

```sh
kubectl create secret generic consul-hcp-client-id --from-literal=client-id='UNIQUE-ID' --namespace consul --context=dc2 && \
kubectl create secret generic consul-hcp-client-secret --from-literal=client-secret='UNIQUE-ID' --namespace consul --context=dc2 && \
kubectl create secret generic consul-hcp-resource-id --from-literal=resource-id='UNIQUE-ID' --namespace consul --context=dc2
```

1. Ensure the cloud stanza is present in your `k8s-yamls/values-dc#-hcp.yaml` files.

```yaml
cloud:
  enabled: true
  resourceId:
    secretName: "consul-hcp-resource-id"
    secretKey: "resource-id"
  clientId:
    secretName: "consul-hcp-client-id"
    secretKey: "client-id"
  clientSecret:
    secretName: "consul-hcp-client-secret"
    secretKey: "client-secret"
```

1. Upgrade Consul deployment for each `dc#`

```sh
./consul-k8s upgrade -config-file k8s-yamls/values-dc1-hcp.yaml --context=dc1
```

```sh
../consul-k8s upgrade -config-file values-dc2-hcp.yaml --context=dc2
```

This completes the HCP management plane section.