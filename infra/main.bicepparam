using 'main.bicep'

param location = 'brazilsouth'
param resourceGroupName = 'rg-test-br-ifrisk'
param vnetName = 'vn-test-br-ifrisk'
param vnetAddressPrefix = '172.24.58.0/23'
param publicSubnetCidr = '172.24.58.0/24'
param privateSubnetCidr = '172.24.59.0/24'
param databricksWorkspaceName = 'adb-test-br-ifrisk'

// Service principal: umi-worker-southbr-dev-0001
param servicePrincipalApplicationId = '08423185-e12b-491f-81bc-35bdc0c2a6a2'
param servicePrincipalDisplayName = 'umi-worker-southbr-dev-0001'
// Object ID (principal ID) of the service principal — retrieve with:
//   az ad sp show --id 08423185-e12b-491f-81bc-35bdc0c2a6a2 --query id -o tsv
param servicePrincipalObjectId = '<REPLACE_WITH_OBJECT_ID>'
// Resource ID of a User Assigned Managed Identity with Contributor on the resource group
// (required to run the SCIM deployment script). Example:
//   /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<name>
param deploymentScriptIdentityId = '<REPLACE_WITH_DEPLOYER_UMI_RESOURCE_ID>'
