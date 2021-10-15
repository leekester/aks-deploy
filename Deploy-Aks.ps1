# Variables...

$project='techtuesday'
$location='uksouth'
$rg='rg-' + $project
$acrName=('cr' + $project + (Get-Random -Minimum 10000 -Maximum 99999))
$acrSku='Basic'
$aksClusterName='aks-' + $project
$aksVmSize='Standard_B2s'
$aksDnsIp='10.0.2.10'
$aksServiceCidr='10.0.2.0/24'
$dockerBridgeCidr='172.17.0.1/16'
# $tenantId='26b91b2f-46ba-4513-9d75-d0a90337ce8a'
$vnet='vnet-' + $project
$vnetCidr='10.0.0.0/20'
$subnet='snet-' + $project
$subnetCidr='10.0.0.0/23'

# Deploy Docker VM...
# Thanks to https://blog.scottlowe.org/2018/01/25/using-docker-machine-with-azure/
<#
Write-Host 'Deploying Docker VM...' -ForegroundColor Yellow
docker-machine create -d azure `
  --azure-subscription-id $(az account show --query id -o tsv) `
  --azure-location uksouth `
  --azure-size Standard_B2s `
  --azure-resource-group $rg
  docker-vm
#>
# Use eval $(docker-machine env <name>) to establish a Docker configuration pointing to the remote VM

# Create resource group
Write-Host 'Creating resource group...' -ForegroundColor Yellow
az group create `
  --resource-group $rg `
  --location $location

# Create virtual network

Write-Host 'Creating virtual network...' -ForegroundColor Yellow
az network vnet create `
  --name $vnet `
  --address-prefix $vnetCidr `
  --resource-group $rg `
  --subnet-name $subnet `
  --subnet-prefix $subnetCidr `

# Create container registry...

Write-Host 'Creating container registry...' -ForegroundColor Yellow
az acr create `
  --resource-group $rg `
  --name $acrName `
  --sku $acrSku

# Create AKS cluster...

Write-Host 'Creating AKS cluster...' -ForegroundColor Yellow
az aks create `
  --resource-group $rg `
  --name $aksClusterName `
  --node-count 1 `
  --node-vm-size $aksVmSize `
  --zones 1 `
  --enable-aad `
  --enable-azure-rbac `
  --enable-managed-identity `
  --network-plugin azure `
  --service-cidr $aksServiceCidr `
  --docker-bridge-address $dockerBridgeCidr `
  --dns-service-ip $aksDnsIp `
  --generate-ssh-keys

# Attaching container registry...

Write-Host 'Attaching container registry to cluster...' -ForegroundColor Yellow
az aks update `
  --name $aksClusterName `
  --resource-group $rg `
  --attach-acr $acrName

# Authenticate to the cluster...

Write-Host 'Authenticating to the cluster...' -ForegroundColor Yellow
az aks get-credentials `
  --resource-group $rg `
  --name $aksClusterName `
  --overwrite-existing

# Enable container registry admin...

az acr update `
  --name $acrName `
  --admin-enabled true

# Retrieve and store container registry credentials...

$acrCredentials=(az acr credential show --name $acrName) | ConvertFrom-Json
$acrUser=$acrCredentials.username
$acrPassword=$acrCredentials.passwords.value[0]

# Connect to the container registry...

$acrFqdn=($acrName + '.azurecr.io')
docker login $acrFqdn --username $acrUser --password $acrPassword