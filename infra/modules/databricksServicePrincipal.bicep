param databricksWorkspaceName string
param servicePrincipalObjectId string

resource workspace 'Microsoft.Databricks/workspaces@2024-05-01' existing = {
  name: databricksWorkspaceName
}

// Contributor role on the Databricks workspace
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource spRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspace.id, servicePrincipalObjectId, contributorRoleId)
  scope: workspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: servicePrincipalObjectId
    principalType: 'ServicePrincipal'
  }
}
