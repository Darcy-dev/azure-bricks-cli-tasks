param location string
param workspaceName string
param pricingTier string = 'premium'
param vnetId string
param publicSubnetName string
param privateSubnetName string

resource databricksWorkspace 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: workspaceName
  location: location
  sku: {
    name: pricingTier
  }
  properties: {
    managedResourceGroupId: subscriptionResourceId(
      'Microsoft.Resources/resourceGroups',
      'mrg-${workspaceName}'
    )
    parameters: {
      customVirtualNetworkId: {
        value: vnetId
      }
      customPublicSubnetName: {
        value: publicSubnetName
      }
      customPrivateSubnetName: {
        value: privateSubnetName
      }
      enableNoPublicIp: {
        value: true
      }
    }
  }
}

output databricksWorkspaceId string = databricksWorkspace.id
output databricksWorkspaceUrl string = databricksWorkspace.properties.workspaceUrl
