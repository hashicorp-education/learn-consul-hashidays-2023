- `terraform init`
- `terraform apply`
- `aws eks update-kubeconfig \
    --region $(terraform output -raw region) \
    --name $(terraform output -raw cluster_name)`
- `~/consul-k8s install -config-file k8s-yamls/consul-helm.yaml`

confirm Consul is up

```
$ kubectl get pods --namespace consul
NAME                                           READY   STATUS    RESTARTS   AGE
consul-connect-injector-59b5b4fccd-dttkl       1/1     Running   0          70s
consul-mesh-gateway-7b86b77d99-4jtm7           1/1     Running   0          70s
consul-server-0                                1/1     Running   0          70s
consul-webhook-cert-manager-57c5bb695c-68n4d   1/1     Running   0          70s
```

confirm that helm chart version is `1.2.0-dev`

```
$ helm list --namespace consul
NAME    NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                   APP VERSION
consul  consul          1               2023-05-12 15:13:44.115705 -0700 PDT    deployed        consul-1.2.0-dev        1.15.1
```

# deploy products api and postgres (initial services in consul)
for service in {products-api,postgres,intentions-api-db}; do kubectl apply -f hashicups-v1.0.2/$service.yaml; done

verify services in k8s
```
$ kubectl get service
NAME           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kubernetes     ClusterIP   172.20.0.1      <none>        443/TCP    3h31m
postgres       ClusterIP   172.20.179.41   <none>        5432/TCP   23s
products-api   ClusterIP   172.20.43.190   <none>        9090/TCP   25s
```

verify services in consul

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

# view consul ui
`kubectl get services consul-ui -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' --namespace consul`

## enable permissive mTLS (mesh)

- `kubectl apply -f k8s-yamls/mesh-config-entry.yaml --namespace consul`

## migrate remaining services to consul

- `for service in {frontend,nginx,public-api,payments}; do kubectl delete -f hashicups-v1.0.2/$service.yaml; done`

verify services in k8s

```
$ kubectl get service
NAME           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
frontend       ClusterIP   172.20.95.83     <none>        3000/TCP   40s
kubernetes     ClusterIP   172.20.0.1       <none>        443/TCP    3h42m
nginx          ClusterIP   172.20.105.108   <none>        80/TCP     38s
payments       ClusterIP   172.20.16.28     <none>        1800/TCP   33s
postgres       ClusterIP   172.20.179.41    <none>        5432/TCP   11m
products-api   ClusterIP   172.20.43.190    <none>        9090/TCP   11m
public-api     ClusterIP   172.20.225.18    <none>        8080/TCP   36s
```

verify service in consul

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