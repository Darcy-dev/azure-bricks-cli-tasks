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
param servicePrincipalObjectId string
param servicePrincipalApplicationId string
param servicePrincipalDisplayName string
param deploymentScriptIdentityId string

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
// Module: Databricks Service Principal & Entitlements
// ──────────────────────────────────────────────
module databricksSp 'modules/databricksServicePrincipal.bicep' = {
  name: 'deploy-databricks-sp'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    databricksWorkspaceName: databricksWorkspaceName
    servicePrincipalObjectId: servicePrincipalObjectId
    servicePrincipalApplicationId: servicePrincipalApplicationId
    servicePrincipalDisplayName: servicePrincipalDisplayName
    deploymentScriptIdentityId: deploymentScriptIdentityId
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
