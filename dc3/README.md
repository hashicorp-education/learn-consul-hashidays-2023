## Consul dc3

This directory contains the Terraform configuration for the third datacenter (`dc3`).  It deploys an AKS cluster.

### Truncated runbook

1. Create an AD service principal account and update `terraform.tfvars` file.

    ```
    az ad sp create-for-rbac --skip-assignment
    ```

1. Configure `kubectl`.

    ```
    az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw kubernetes_cluster_name) --context=dc3
    ```

1. Deploy Consul. 

    ```
    secret=$(cat ../k8s-yamls/consul.hclic)
    kubectl create namespace consul --context=dc3
    kubectl create secret generic consul-ent-license --from-literal="key=${secret}" -n consul --context=dc3
    ~/consul-k8s install -config-file values.yaml --context=dc3
    ```


1. Deploy HashiCups.

    ```
    kubectl apply --filename ../hashicups-full --context=dc3
    ```

1. Verify pods are up and running.

    ```
    kubectl get pods --context=dc3
    ```

1. Configure cluster peering (`dc2` to `dc3`).

    ```
    for dc in {dc2,dc3}; do kubectl --context=$dc apply -f k8s-yamls/peer-through-meshgateways.yaml; done
    ```

1. Configure local mode for traffic routed over the mesh gateways for both `dc2` and `dc3`.

    ```
    for dc in {dc2,dc3}; do kubectl --context=$dc apply -f k8s-yamls/originate-via-meshgateways.yaml; done
    ```

1. Configure a PeeringAcceptor role for `dc2`.

    ```
    kubectl --context=dc2 apply -f k8s-yamls/acceptor-on-dc2-for-dc3.yaml
    ```

1. Confirm you successfully created the peering acceptor custom resource definition (CRD).

    ```
    kubectl --context=dc2 get peeringacceptors
    ```

1. Confirm that the PeeringAcceptor CRD generated a peering token secret.

    ```
    kubectl --context=dc2 get secrets peering-token-dc3
    ```

1. Import the peering token generated in `dc2` into `dc3`.

    ```
    kubectl --context=dc2 get secret peering-token-dc3 -o yaml | kubectl --context=dc3 apply -f -
    ```

1. Configure a `PeeringDialer` role for `dc3`. This will create a peering connection from the third datacenter towards the second one.

    ```
    kubectl --context=dc3 apply -f k8s-yamls/dialer-dc3.yaml
    ```

1. Verify that the two Consul clusters are peered.

    ```
    kubectl exec --namespace=consul -it --context=dc2 consul-server-0 \
    -- curl --cacert /consul/tls/ca/tls.crt --header "X-Consul-Token: $(kubectl --context=dc2 --namespace=consul get secrets consul-bootstrap-acl-token -o go-template='{{.data.token|base64decode}}')" "https://127.0.0.1:8501/v1/peering/dc3" \
    | jq
    ```

1. In `dc3`, apply the `ExportedServices` custom resource file that exports the `products-api` service to `dc2`.

    ```
    kubectl --context=dc3 apply -f k8s-yamls/exportedsvc-products-api.yaml
    ```

1. Confirm that the Consul cluster in `dc2` can access the `products-api` in `dc3`.

    ```
    kubectl \
    --context=dc2 --namespace=consul exec -it consul-server-0 \
    -- curl --cacert /consul/tls/ca/tls.crt \
    --header "X-Consul-Token: $(kubectl --context=dc2 --namespace=consul get secrets consul-bootstrap-acl-token -o go-template='{{.data.token|base64decode}}')" "https://127.0.0.1:8501/v1/health/connect/products-api?peer=dc3" \
    | jq '.[].Service.ID,.[].Service.PeerName'
    ```

1. Apply intentions.

    ```
    kubectl --context=dc3 apply -f k8s-yamls/intention-dc2-public-api-to-dc3-products-api.yaml
    ```

1. Update virtual DNS for products API and apply configuration.

    ```
    kubectl --context=dc2 apply -f ../hashicups-full/public-api.yaml
    ```

1. Apply fail-over `dc2` and `dc3`.

    ```
    kubectl apply -f ../dc3/k8s-yamls/failover.yaml --context=dc2
    ```

1. Scale down `products-api` in `dc2` to test failover.

    ```
    kubectl scale --context=dc2 deploy/products-api --replicas=0
    ```

1. Port forward the nginx service locally to port 8080 to test the products-api successfully failover.

    ```
    kubectl --context=dc2 port-forward deploy/nginx 8080:80
    ```

1. Scale up `products-api` in `dc2`.

    ```
    kubectl scale --context=dc2 deploy/products-api --replicas=1
    ```