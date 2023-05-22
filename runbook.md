
# Permissive mTLS runbook
## Create environment 

```
terraform init
terraform apply
```

```
aws eks update-kubeconfig \
  --region $(terraform output -raw region) \
  --name $(terraform output -raw cluster_name)  --alias=dc1
```

### Deploy Consul

```
secret=$(cat k8s-yamls/consul.hclic)
kubectl create namespace consul --context=dc1
kubectl create secret generic consul-ent-license --from-literal="key=${secret}" -n consul --context=dc1
~/consul-k8s install -config-file k8s-yamls/values.yaml --context=dc1
```

Confirm Consul is up.

```
$ kubectl get pods -n consul --context=dc1
NAME                                           READY   STATUS    RESTARTS   AGE
consul-connect-injector-59b5b4fccd-mqmhv       1/1     Running   0          90s
consul-mesh-gateway-7b86b77d99-rhfgd           1/1     Running   0          90s
consul-server-0                                1/1     Running   0          90s
consul-webhook-cert-manager-57c5bb695c-qxc5t   1/1     Running   0          90s
```

Confirm that helm chart version is `1.2.0-dev`.

```
$ helm list -n consul --kube-context=dc1
NAME    NAMESPACE       REVISION        UPDATED                                 STATUS     CHART            APP VERSION
consul  consul          1               2023-05-14 06:12:25.898867 -0700 PDT    deployed   consul-1.2.0-dev 1.15.1     
```

### Deploy HashiCups services

```
$ for service in {products-api,postgres,intentions-api-db}; do kubectl apply -f hashicups-v1.0.2/$service.yaml --context=dc1; done
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

```
$ kubectl get service --context=dc1
NAME           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kubernetes     ClusterIP   172.20.0.1      <none>        443/TCP    12m
postgres       ClusterIP   172.20.196.70   <none>        5432/TCP   4s
products-api   ClusterIP   172.20.182.94   <none>        9090/TCP   7s
```

Verify services in Consul.

```
$ kubectl exec --namespace consul -it consul-server-0 -- consul catalog services
Defaulted container "consul" out of: consul, locality-init (init)
consul
mesh-gateway
postgres
postgres-sidecar-proxy
products-api
products-api-sidecar-proxy
```

## Enable permissive mTLS (mesh)

```
$ kubectl apply -f k8s-yamls/mesh-config-entry.yaml -n consul --context=dc1
mesh.consul.hashicorp.com/mesh created
```

## Connect services to Consul services

First, you need to deploy services to your Kubernetes clusters. Permissive mTLS requires TProxy (so it only works with Consul on Kubernetes for now). The following HashiCups service deployments have `consul.hashicorp.com/connect-inject` explicitly set to `false` so Consul does not register them.

(might need to do a deeper dive on tproxy and how routing works)

```
$ for service in {frontend,nginx,public-api,payments}; do kubectl apply -f hashicups-v1.0.2/$service.yaml --context=dc1; done
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

```
$ kubectl get service --context=dc1
NAME           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
frontend       ClusterIP   172.20.55.80     <none>        3000/TCP   20s
kubernetes     ClusterIP   172.20.0.1       <none>        443/TCP    14m
nginx          ClusterIP   172.20.11.54     <none>        80/TCP     18s
payments       ClusterIP   172.20.172.174   <none>        1800/TCP   14s
postgres       ClusterIP   172.20.196.70    <none>        5432/TCP   117s
products-api   ClusterIP   172.20.182.94    <none>        9090/TCP   2m
public-api     ClusterIP   172.20.255.151   <none>        8080/TCP   16s
```

Verify services do not appear in Consul.

```
$ kubectl exec --namespace consul -it consul-server-0 -- consul catalog services
Defaulted container "consul" out of: consul, locality-init (init)
consul
mesh-gateway
postgres
postgres-sidecar-proxy
products-api
products-api-sidecar-proxy
```

Open HashiCups in your browser. In a new terminal, port-forward the `nginx` service to port `8080`. 

```
$ kubectl port-forward deploy/nginx 8080:80 --context=dc1
```

Open [localhost:8080]() in your browser to view the HashiCups UI. Notice that it displays no products, since the `public-api` cannot connect to the `products-api`.

### Set permissive mTLS at service level

Enable `products-api` to allow non-mTLS traffic.

```
$ kubectl apply -f k8s-yamls/service-defaults-products-api.yaml -n consul --context=dc1
```

## Migrate services to Consul

Even though `public-api` was able to connect to `products-api` and there is a deny-all intention on the Consul datacenter, **intentions only take effect for mTLS connections**. For non-mTLS connections (permissive), intentions are effectively ignored.
As a result, use permissive mTLS with great caution and be mindful of [security best practices]().

You will migrate the remaining HashiCups services to Consul service mesh. First, in each service deployment definition, update the `consul.hashicorp.com/connect-inject` annotation from `false` to `true`.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
      annotations:
        consul.hashicorp.com/connect-inject: "true"
```

Once you have done this to all four files, apply the changes. In addition, you will apply a file that creates intentions between these services. 

```
$ for service in {frontend,nginx,public-api,payments,intentions-new-services}; do kubectl apply -f hashicups-v1.0.2/$service.yaml --context=dc1; done
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

Verify services appear in Consul.

```
$ kubectl exec --namespace consul -it consul-server-0 -- consul catalog services
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

```
$ kubectl apply -f hashicups-v1.0.2/intentions-public-products-api.yaml -n consul --context=dc1
serviceintentions.consul.hashicorp.com/public-api created
```

### Restrict permissive mTLS at service level

Restrict `products-api` to only accept mTLS traffic.

In `k8s-yamls/service-defaults-products-api.yaml`, update `mutualTLSMode` to `"strict"`.

```yaml
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceDefaults
metadata:
  name: products-api
spec:
  protocol: http
  mutualTLSMode: "permissive"
```

Then, apply the changes.

```
$ kubectl apply -f k8s-yamls/service-defaults-products-api.yaml -n consul --context=dc1
servicedefaults.consul.hashicorp.com/products-api configured
```

## Restrict permissive mTLS (mesh)

In `k8s-yamls/mesh-config-entry.yaml`, update `allowEnablingPermissiveMutualTLS` to `false`.

```yaml
apiVersion: consul.hashicorp.com/v1alpha1
kind: Mesh
metadata:
  name: mesh
spec:
  allowEnablingPermissiveMutualTLS: true
```

Then, apply the changes.

```
$ kubectl apply -f k8s-yamls/mesh-config-entry.yaml -n consul --context=dc1
mesh.consul.hashicorp.com/mesh configured
```

Now, connect the self-managed cluster to HCP.

# Cluster peering runbook

For `dc1`, we need to modify the mesh gateway then apply it.

```
apiVersion: consul.hashicorp.com/v1alpha1
kind: Mesh
metadata:
  name: mesh
spec:
  allowEnablingPermissiveMutualTLS: false
   peering:
     peerThroughMeshGateways: true
```

```
$ kubectl apply -f k8s-yamls/mesh-config-entry.yaml -n consul --context=dc1
```

Configure cluster peering (`dc1` to `dc2`) -- peering through mesh gateways.

```
kubectl --context=dc2 apply -f k8s-yamls/peer-through-meshgateways.yaml
```

Configure local mode for traffic routed over the mesh gateways for both `dc1` and `dc2`.

```
for dc in {dc1,dc2}; do kubectl --context=$dc apply -f k8s-yamls/originate-via-meshgateways.yaml; done
```

Configure a PeeringAcceptor role for `dc1`.

```
kubectl --context=dc1 apply -f k8s-yamls/acceptor-on-dc1-for-dc2.yaml
```

Confirm you successfully created the peering acceptor custom resource definition (CRD).

```
kubectl --context=dc1 get peeringacceptors
```

Confirm that the PeeringAcceptor CRD generated a peering token secret.

```
kubectl --context=dc1 get secrets peering-token-dc2
```

Import the peering token generated in `dc1` into `dc2`.

```
kubectl --context=dc1 get secret peering-token-dc2 -o yaml | kubectl --context=dc2 apply -f -
```

Configure a `PeeringDialer` role for `dc2`. This will create a peering connection from the second datacenter towards the first one.

```
kubectl --context=dc2 apply -f k8s-yamls/dialer-dc2.yaml
```

Verify that the two Consul clusters are peered.

```
kubectl exec --namespace=consul -it --context=dc1 consul-server-0 \
-- curl --cacert /consul/tls/ca/tls.crt --header "X-Consul-Token: $(kubectl --context=dc1 --namespace=consul get secrets consul-bootstrap-acl-token -o go-template='{{.data.token|base64decode}}')" "https://127.0.0.1:8501/v1/peering/dc2" \
 | jq
```

In `dc2`, apply the `ExportedServices` custom resource file that exports the `products-api` service to `dc1`.

```
kubectl --context=dc2 apply -f k8s-yamls/exportedsvc-products-api.yaml
```

Confirm that the Consul cluster in `dc1` can access the `products-api` in `dc2`.

```
kubectl \
--context=dc1 --namespace=consul exec -it consul-server-0 \
-- curl --cacert /consul/tls/ca/tls.crt \
--header "X-Consul-Token: $(kubectl --context=dc1 --namespace=consul get secrets consul-bootstrap-acl-token -o go-template='{{.data.token|base64decode}}')" "https://127.0.0.1:8501/v1/health/connect/products-api?peer=dc2" \
| jq '.[].Service.ID,.[].Service.PeerName'
```

Apply intentions.

```
kubectl --context=dc2 apply -f k8s-yamls/intention-dc1-public-api-to-dc2-products-api.yaml
```

Update virtual DNS for products API and apply configuration.

```
kubectl --context=dc1 apply -f ../hashicups-full/public-api.yaml
```

Apply fail-over `dc1` on `dc2`.

```
kubectl apply -f k8s-yamls/failover.yaml --context=dc1
```

Port forward the nginx service locally to port 8080 to test the products-api successfully failover.

```
kubectl --context=dc1 port-forward deploy/nginx 8080:80
```

Scale down `products-api` in `dc1` to test failover.

```
kubectl scale --context=dc1 deploy/products-api --replicas=0
```

Scale down `products-api` in `dc2` to test failover.

```
kubectl scale --context=dc2 deploy/products-api --replicas=0
```

Scale up `products-api` in `dc2`.

```
kubectl scale --context=dc2 deploy/products-api --replicas=1
```

Scale up `products-api` in `dc1`.

```
kubectl scale --context=dc1 deploy/products-api --replicas=1
```