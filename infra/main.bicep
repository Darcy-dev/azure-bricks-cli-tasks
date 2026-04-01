targetScope = 'subscription'

// ──────────────────────────────────────────────
// Parameters
// ──────────────────────────────────────────────
param location string
param resourceGroupName string
param vnetName string
param vnetAddressPrefix string
param publicSubnetName string = 'sn-public-databricks'
param publicSubnetCidr string
param privateSubnetName string = 'sn-private-databricks'
param privateSubnetCidr string
param databricksWorkspaceName string
param databricksPricingTier string = 'premium'
param publicSubnetNsgName string = 'nsg-public-databricks'
param privateSubnetNsgName string = 'nsg-private-databricks'
param workerIdentityName string

// ──────────────────────────────────────────────
// Module: Resource Group
// ──────────────────────────────────────────────
module rg 'modules/resourceGroup.bicep' = {
  name: 'deploy-resource-group'
  params: {
    resourceGroupName: resourceGroupName
    location: location
  }
}

// ──────────────────────────────────────────────
// Module: Network Security Groups
// ──────────────────────────────────────────────
module nsg 'modules/networkSecurityGroups.bicep' = {
  name: 'deploy-nsgs'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    publicSubnetNsgName: publicSubnetNsgName
    privateSubnetNsgName: privateSubnetNsgName
  }
  dependsOn: [
    rg
  ]
}

// ──────────────────────────────────────────────
// Module: Virtual Network & Subnets
// ──────────────────────────────────────────────
module vnet 'modules/virtualNetwork.bicep' = {
  name: 'deploy-vnet'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    publicSubnetName: publicSubnetName
    publicSubnetCidr: publicSubnetCidr
    privateSubnetName: privateSubnetName
    privateSubnetCidr: privateSubnetCidr
    publicSubnetNsgId: nsg.outputs.publicSubnetNsgId
    privateSubnetNsgId: nsg.outputs.privateSubnetNsgId
  }
}

// ──────────────────────────────────────────────
// Module: User Assigned Managed Identity (worker)
// ──────────────────────────────────────────────
module workerIdentity 'modules/userAssignedIdentity.bicep' = {
  name: 'deploy-worker-identity'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    identityName: workerIdentityName
  }
  dependsOn: [
    rg
  ]
}

// ──────────────────────────────────────────────
// Module: Azure Databricks Workspace
// ──────────────────────────────────────────────
module databricks 'modules/databricks.bicep' = {
  name: 'deploy-databricks'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    workspaceName: databricksWorkspaceName
    pricingTier: databricksPricingTier
    vnetId: vnet.outputs.vnetId
    publicSubnetName: vnet.outputs.publicSubnetName
    privateSubnetName: vnet.outputs.privateSubnetName
  }
}

// ──────────────────────────────────────────────
// Module: Databricks Service Principal RBAC
// ──────────────────────────────────────────────
module databricksSp 'modules/databricksServicePrincipal.bicep' = {
  name: 'deploy-databricks-sp'
  scope: resourceGroup(resourceGroupName)
  params: {
    databricksWorkspaceName: databricksWorkspaceName
    servicePrincipalObjectId: workerIdentity.outputs.principalId
  }
  dependsOn: [
    databricks
  ]
}

// ──────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────
output resourceGroupName string = rg.outputs.resourceGroupName
output vnetName string = vnet.outputs.vnetName
output databricksWorkspaceUrl string = databricks.outputs.databricksWorkspaceUrl
output workerIdentityClientId string = workerIdentity.outputs.clientId
output workerIdentityPrincipalId string = workerIdentity.outputs.principalId
output workerIdentityResourceId string = workerIdentity.outputs.identityId
