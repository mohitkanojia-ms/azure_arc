using './main.bicep'

param tenantId = '16b3c013-d300-468d-ac64-7eda0820b6d3'
param spnProviderId = 'f22c1f67-c9e6-4b1f-b4cb-4d3ec1f229e1'
param windowsAdminUsername = 'arcdemo'
param windowsAdminPassword = 'Mohit@007007'
param logAnalyticsWorkspaceName = 'Workspace-26feb'
param natDNS = '8.8.8.8'
param githubAccount = 'mohitkanojia-ms'
param githubBranch = 'main'
param deployBastion = false
param location = 'westeurope'
param azureLocalInstanceLocation = 'westeurope'
param rdpPort = '3389'
param autoDeployClusterResource = true
param autoUpgradeClusterResource = false
param vmAutologon = true
param vmSize = 'Standard_E8s_v5'
param enableAzureSpotPricing = false
param governResourceTags = true
param tags = {
  Project: 'jumpstart_SFF_26feb'
}
