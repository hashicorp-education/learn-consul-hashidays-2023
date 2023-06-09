## Runbook

```
$ az login
The default web browser has been opened at https://login.microsoftonline.com/common/oauth2/authorize. Please continue the login in the web browser. If no web browser is available or if the web browser fails to open, use device code flow with `az login --use-device-code`.
You have logged in. Now let us find all the subscriptions to which you have access...

#...
```

```
az ad sp create-for-rbac --skip-assignment
Option '--skip-assignment' has been deprecated and will be removed in a future release.
The output includes credentials that you must protect. Be sure that you do not include these credentials in your code or check the credentials into your source control. For more information, see https://aka.ms/azadsp-cli
{
  "appId": "8334fa9a-b446-4e9e-9e73-9135d6845322",
  "displayName": "azure-cli-2023-06-09-10-22-42",
  "password": ".hU8Q~slC5NE8V1hGw8rwV6.V4foiZGhCYGA~bcN",
  "tenant": "0e3e2e88-8caf-41ca-b4da-e3b33b6c52ec"
}
```

```
edit terraform.tfvars
appId    = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
password = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
```

```
terraform init
terraform apply
```

```
az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw kubernetes_cluster_name) --context dc2

wait a few mins if error:
(ResourceGroupNotFound) Resource group 'CLUSTERNAME-aks' could not be found.
Code: ResourceGroupNotFound
Message: Resource group 'CLUSTERNAME-aks' could not be found.
```

