$resourceGroup = "rg-aks"
$location = "uksouth"
$clusterName = "aks"
$nodesize = "Standard_B4ms"
$nodeCount = "1"
$installFlux = $true
$subscriptionId = (az account show --query id --output tsv)

# Create AKS cluster
Write-Host "Creating AKS cluster $clusterName in resource group $resourceGroup" -ForegroundColor Yellow
az group create `
  --name $resourceGroup `
  --location $location
az aks create `
  --resource-group $resourceGroup `
  --name $clusterName `
  --node-vm-size $nodesize `
  --node-count $nodeCount `
  --network-plugin kubenet `
  --pod-cidr 192.168.0.0/16 `
  --zones 1 `
  --generate-ssh-keys `
  --enable-aad `
  --enable-azure-rbac `
  --disable-local-accounts

# Register the service mesh feature and wait until registration completes
$startTime = (Get-Date)
Do {
    $serviceMeshPreviewState = (az feature show --namespace "Microsoft.ContainerService" --name "AzureServiceMeshPreview" | ConvertFrom-Json).properties.state
    If ($serviceMeshPreviewState -eq "Not Registered") {
        az feature register --namespace "Microsoft.ContainerService" --name "AzureServiceMeshPreview"
    }
    $elapsedSeconds = ((Get-Date) - $startTime).Seconds
    Write-Host ("Feature is in a `"" + $serviceMeshPreviewState + "`" state. Registration started " + $elapsedSeconds + " seconds ago.") -ForegroundColor Yellow
    Sleep 10
} Until ($serviceMeshPreviewState -eq "Registered")

# Register/re-register the provider
Write-Host "Registering/re-registering the Microsoft.ContainerService provider" -ForegroundColor Yellow
az provider register --namespace Microsoft.ContainerService

Write-Host "Enabling service mesh..." -ForegroundColor Yellow
az aks mesh enable --resource-group $resourceGroup --name $clusterName

If ($installFlux) {
    Write-Host "Enabling Flux extension..." -ForegroundColor Yellow
    az k8s-extension create --resource-group $resourceGroup --cluster-name $clusterName --cluster-type managedClusters --name flux --extension-type microsoft.flux --config useKubeletIdentity=true
}

# Retrieve AKS admin credentials
Write-Host "Retrieving AKS credentials" -ForegroundColor Yellow
az aks get-credentials --name $clusterName --resource-group $resourceGroup --overwrite-existing

# Label the default namespace, if that's where pods will be deployed
kubectl label namespace default istio.io/rev=asm-1-17

# Run up a sample app in the default namespace
kubectl run nginx --image=nginx
kubectl get pods
