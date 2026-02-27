#requires -Version 7.0

<#
.SYNOPSIS
    Connects to an AKS workload cluster running on Azure Local (Azure Stack HCI)
    and retrieves credentials to the local kubeconfig.

.DESCRIPTION
    - Installs/updates required Azure CLI extensions (aksarc, customlocation)
    - Gets credentials for the AKS workload cluster via 'az aksarc get-credentials'
    - Verifies connectivity with kubectl
    - Optionally switches the current kubectl context to the cluster

.NOTES
    Prerequisites:
        - Azure CLI installed and on PATH
        - kubectl installed and on PATH
        - Managed identity or service principal with Contributor access to the resource group
        - AKS workload cluster already provisioned (run Configure-AKSWorkloadCluster.ps1 first)
#>

$WarningPreference  = "SilentlyContinue"
$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

# -----------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------
$Env:LocalBoxDir    = "C:\LocalBox"
$LocalBoxConfig     = Import-PowerShellDataFile -Path $Env:LocalBoxConfigFile
Start-Transcript -Path "$($LocalBoxConfig.Paths.LogsDir)\Connect-AzureLocalAKSCluster.log"

$subId           = $env:subscriptionId
$rg              = $env:resourceGroup
$location        = $env:azureLocation
$clusterName     = $LocalBoxConfig.AKSworkloadClusterName   # e.g. "aks-26feb"
$customLocName   = $LocalBoxConfig.rbCustomLocationName     # e.g. "customloc-26feb"

# -----------------------------------------------------------------------
# 1. Authenticate
# -----------------------------------------------------------------------
Write-Host "[Step 1/5] Authenticating to Azure..." -ForegroundColor Cyan
az login --identity --allow-no-subscriptions --only-show-errors | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Non-interactive Azure CLI login failed. Managed identity is unavailable or lacks permissions."
}

az account set --subscription $subId --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set Azure CLI subscription context to '$subId'."
}

az config set extension.use_dynamic_install=yes_without_prompt | Out-Null

# -----------------------------------------------------------------------
# 2. Ensure required CLI extensions are present and up-to-date
# -----------------------------------------------------------------------
Write-Host "[Step 2/5] Installing / updating required Azure CLI extensions..." -ForegroundColor Cyan

foreach ($ext in @("aksarc", "customlocation", "connectedk8s", "k8s-configuration")) {
    $existing = az extension show --name $ext 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  Updating extension: $ext"
        az extension update --name $ext | Out-Null
    } else {
        Write-Host "  Installing extension: $ext"
        az extension add --name $ext | Out-Null
    }
}

# -----------------------------------------------------------------------
# 3. Validate the AKS cluster is provisioned and Running
# -----------------------------------------------------------------------
Write-Host "[Step 3/5] Validating AKS workload cluster '$clusterName' in resource group '$rg'..." -ForegroundColor Cyan

$cluster = az aksarc show `
    --name $clusterName `
    --resource-group $rg `
    --subscription $subId `
    --output json 2>$null | ConvertFrom-Json

if (-not $cluster) {
    Write-Error "AKS workload cluster '$clusterName' not found in resource group '$rg'. " +
                "Run Configure-AKSWorkloadCluster.ps1 first to provision the cluster."
    Stop-Transcript
    exit 1
}

$provState = $cluster.provisioningState
Write-Host "  Cluster provisioning state: $provState"

if ($provState -ne "Succeeded") {
    Write-Warning "Cluster '$clusterName' is in state '$provState'. " +
                  "Wait for provisioning to complete before connecting."
    Stop-Transcript
    exit 1
}

Write-Host "  Cluster ID   : $($cluster.id)"
Write-Host "  Location     : $($cluster.location)"
Write-Host "  K8s version  : $($cluster.kubernetesVersion)"

# -----------------------------------------------------------------------
# 4. Retrieve kubeconfig credentials
# -----------------------------------------------------------------------
Write-Host "[Step 4/5] Retrieving kubeconfig for cluster '$clusterName'..." -ForegroundColor Cyan

az aksarc get-credentials `
    --name $clusterName `
    --resource-group $rg `
    --subscription $subId `
    --overwrite-existing

# Switch kubectl context to the newly connected cluster
kubectl config use-context $clusterName
Write-Host "  kubectl context set to: $clusterName"

# -----------------------------------------------------------------------
# 5. Verify connectivity
# -----------------------------------------------------------------------
Write-Host "[Step 5/5] Verifying cluster connectivity..." -ForegroundColor Cyan

try {
    $nodes = kubectl get nodes --output wide 2>&1
    Write-Host $nodes
} catch {
    Write-Warning "kubectl get nodes failed. Ensure the cluster API server is reachable from this host."
}

# Display Arc-connected resource details
Write-Host ""
Write-Host "Arc-connected cluster details:" -ForegroundColor Green
az connectedk8s show `
    --name $clusterName `
    --resource-group $rg `
    --subscription $subId `
    --output table 2>$null

Write-Host ""
Write-Host "Successfully connected to Azure Local AKS cluster '$clusterName'." -ForegroundColor Green
Write-Host "Use 'kubectl' commands with context '$clusterName' to manage the cluster." -ForegroundColor Green

Stop-Transcript
