$WarningPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

# Set paths
$Env:LocalBoxDir = "C:\LocalBox"

# Import Configuration Module
$LocalBoxConfig = Import-PowerShellDataFile -Path $Env:LocalBoxConfigFile
Start-Transcript -Path "$($LocalBoxConfig.Paths.LogsDir)\Generate-ARM-Template.log"

# Best-effort install/import of Azure PowerShell modules used by this script
$requiredModules = @("Az.Accounts", "Az.Resources", "Az.ConnectedMachine", "Az.StackHCI")
foreach ($moduleName in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        try {
            Install-Module -Name $moduleName -Scope AllUsers -Force -AllowClobber -ErrorAction SilentlyContinue | Out-Null
            Write-Output "Module installation attempted: $moduleName"
        }
        catch {
            Write-Output "Module installation skipped/failed for $moduleName. Continuing..."
        }
    }

    try {
        Import-Module $moduleName -ErrorAction SilentlyContinue
    }
    catch {
        Write-Output "Module import skipped/failed for $moduleName. Continuing..."
    }
}

if ($null -ne $env:subscriptionId -and $null -ne $env:tenantId) {
    try {
        Connect-AzAccount -Identity -Tenant $env:tenantId -Subscription $env:subscriptionId -ErrorAction Stop | Out-Null
        Set-AzContext -SubscriptionId $env:subscriptionId -TenantId $env:tenantId -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Output "Managed identity Azure login failed in Generate-ARM-Template.ps1. Error: $($_.Exception.Message)"
    }
}

# Add necessary role assignments
# $ErrorActionPreference = "Continue"
# New-AzRoleAssignment -ObjectId $env:spnProviderId -RoleDefinitionName "Azure Connected Machine Resource Manager" -ResourceGroup $env:resourceGroup -ErrorAction Continue
# $ErrorActionPreference = "Stop"

$arcNodes = Get-AzConnectedMachine -SubscriptionId $env:subscriptionId -ResourceGroupName $env:resourceGroup
$arcNodeResourceIds = $arcNodes.Id | ConvertTo-Json -AsArray

# foreach ($machine in $arcNodes) {
#     $ErrorActionPreference = "Continue"
#     New-AzRoleAssignment -ObjectId $machine.IdentityPrincipalId -RoleDefinitionName "Key Vault Secrets User" -ResourceGroup $env:resourceGroup
#     New-AzRoleAssignment -ObjectId $machine.IdentityPrincipalId -RoleDefinitionName "Reader" -ResourceGroup $env:resourceGroup
#     New-AzRoleAssignment -ObjectId $machine.IdentityPrincipalId -RoleDefinitionName "Azure Stack HCI Device Management Role" -ResourceGroup $env:resourceGroup
#     New-AzRoleAssignment -ObjectId $machine.IdentityPrincipalId -RoleDefinitionName "Azure Connected Machine Resource Manager" -ResourceGroup $env:resourceGroup
#     $ErrorActionPreference = "Stop"
# }

# "Insufficient privileges to complete the operation." when using Managed Identity.
#$spnProviderId = Get-AzADServicePrincipal -DisplayName "Microsoft.AzureStackHCI Resource Provider"

# Construct OU path
$domainName = $LocalBoxConfig.SDNDomainFQDN.Split('.')
$ouPath = "OU=$($LocalBoxConfig.LCMADOUName)"
foreach ($name in $domainName) {
    $ouPath += ",DC=$name"
}

# Build DNS value
$dns = "[""" + $LocalBoxConfig.vmDNS + """]"

# Create keyvault name
$guid = ([System.Guid]::NewGuid()).ToString().subString(0,5).ToLower()
$keyVaultName = "localbox-kv-" + $guid

# Set physical nodes
$physicalNodesSettings = "[ "
$storageAIPs = "[ "
$storageBIPs = "[ "
$count = 0
foreach ($node in $LocalBoxConfig.NodeHostConfig) {
    if ($count -gt 0) {
        $physicalNodesSettings += ", "
        $storageAIPs += ", "
        $storageBIPs += ", "
    }
    $physicalNodesSettings += "{ ""name"": ""$($node.Hostname)"", ""ipv4Address"": ""$($node.IP.Split("/")[0])"" }"
    $count = $count + 1
}
$physicalNodesSettings += " ]"
$storageAIPs += " ]"
$storageBIPs += " ]"

# Create diagnostics storage account name
$diagnosticsStorageName = "localboxdiagsa$guid"

# Replace placeholder values in ARM template with real values
$AzLocalParams = "$env:LocalBoxDir\azlocal.parameters.json"
(Get-Content -Path $AzLocalParams) -replace 'clusterName-staging', $LocalBoxConfig.ClusterName | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'arcNodeResourceIds-staging', $arcNodeResourceIds | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'localAdminUserName-staging', 'Administrator' | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'localAdminPassword-staging', $($LocalBoxConfig.SDNAdminPassword) | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'AzureStackLCMAdminUserName-staging', $($LocalBoxConfig.LCMDeployUsername) | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'AzureStackLCMAdminAdminPassword-staging', $($LocalBoxConfig.SDNAdminPassword) | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'hciResourceProviderObjectID-staging', $env:spnProviderId | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'domainFqdn-staging', $($LocalBoxConfig.SDNDomainFQDN) | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'namingPrefix-staging', $($LocalBoxConfig.LCMDeploymentPrefix) | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'adouPath-staging', $ouPath | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'subnetMask-staging', $($LocalBoxConfig.rbSubnetMask) | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'defaultGateway-staging', $LocalBoxConfig.SDNLabRoute | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'startingIp-staging', $LocalBoxConfig.clusterIpRangeStart | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'endingIp-staging', $LocalBoxConfig.clusterIpRangeEnd | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'dnsServers-staging', $dns | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'keyVaultName-staging', $keyVaultName | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'physicalNodesSettings-staging', $physicalNodesSettings | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'ClusterWitnessStorageAccountName-staging', $env:stagingStorageAccountName | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'diagnosticStorageAccountName-staging', $diagnosticsStorageName | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'storageNicAVLAN-staging', $LocalBoxConfig.StorageAVLAN | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'storageNicBVLAN-staging', $LocalBoxConfig.StorageBVLAN | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'customLocation-staging', $LocalBoxConfig.rbCustomLocationName | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'location-staging', $env:azureLocation | Set-Content -Path $AzLocalParams
(Get-Content -Path $AzLocalParams) -replace 'tenantId-staging', $env:tenantId | Set-Content -Path $AzLocalParams