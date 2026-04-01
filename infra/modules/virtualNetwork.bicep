param location string
param vnetName string
param vnetAddressPrefix string
param publicSubnetName string
param publicSubnetCidr string
param privateSubnetName string
param privateSubnetCidr string
param defaultSubnetName string
param defaultSubnetCidr string
param publicSubnetNsgId string
param privateSubnetNsgId string

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: publicSubnetName
        properties: {
          addressPrefix: publicSubnetCidr
          networkSecurityGroup: {
            id: publicSubnetNsgId
          }
          delegations: [
            {
              name: 'databricks-del-public'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
            }
          ]
          serviceEndpoints: [
            { service: 'Microsoft.Storage.Global' }
            { service: 'Microsoft.Sql' }
            { service: 'Microsoft.EventHub' }
            { service: 'Microsoft.KeyVault' }
            { service: 'Microsoft.AzureActiveDirectory' }
          ]
        }
      }
      {
        name: privateSubnetName
        properties: {
          addressPrefix: privateSubnetCidr
          networkSecurityGroup: {
            id: privateSubnetNsgId
          }
          delegations: [
            {
              name: 'databricks-del-private'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
            }
          ]
          serviceEndpoints: [
            { service: 'Microsoft.Storage.Global' }
            { service: 'Microsoft.Sql' }
            { service: 'Microsoft.EventHub' }
            { service: 'Microsoft.KeyVault' }
            { service: 'Microsoft.AzureActiveDirectory' }
          ]
        }
      }
      {
        name: defaultSubnetName
        properties: {
          addressPrefix: defaultSubnetCidr
          serviceEndpoints: [
            { service: 'Microsoft.Storage.Global' }
            { service: 'Microsoft.Sql' }
            { service: 'Microsoft.EventHub' }
            { service: 'Microsoft.KeyVault' }
            { service: 'Microsoft.AzureActiveDirectory' }
          ]
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output publicSubnetName string = vnet.properties.subnets[0].name
output privateSubnetName string = vnet.properties.subnets[1].name
output defaultSubnetName string = vnet.properties.subnets[2].name
