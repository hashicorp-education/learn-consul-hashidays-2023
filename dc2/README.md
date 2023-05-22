## Consul dc2

This directory contains the Terraform configuration for the third datacenter (`dc2`).  It deploys a VPC and an EKS cluster onto AWS.

### Truncated runbook

1. Configure `kubectl`.

    ```
    aws eks update-kubeconfig --region $(terraform output -raw region) --name $(terraform output -raw cluster_name) --alias=dc2
    ```

1. Install API Gateway CRDs.

    ```
    kubectl apply --kustomize="github.com/hashicorp/consul-api-gateway/config/crd?ref=v0.5.4" --context=dc2
    ```

1. Deploy Consul.

    ```
    secret=$(cat ../k8s-yamls/consul.hclic)
    kubectl create namespace consul --context=dc2
    kubectl create secret generic consul-ent-license --from-literal="key=${secret}" -n consul --context=dc2
    consul-k8s install -config-file values.yaml --context=dc2
    ```

1. Deploy HashiCups.

    ```
    kubectl apply --filename ../hashicups-full --context=dc2
    ```

1. Verify pods are up and running.

    ```
    kubectl get pods --all-namespaces --context=dc2
    ```

1. Deploy API Gateway.

    ```
    kubectl apply --filename api-gw/consul-api-gateway.yaml --context=dc2 && \
        kubectl wait --for=condition=ready gateway/api-gateway --timeout=90s --context=dc2 && \
        kubectl apply --filename api-gw/routes.yaml --context=dc2
    ```