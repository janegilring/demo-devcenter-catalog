@description('The name of your Virtual Machine')
param vmName string = 'ArcBox-Client'

@description('The name of the Cluster API workload cluster to be connected as an Azure Arc-enabled Kubernetes cluster')
param k3sArcDataClusterName string = 'ArcBox-K3s-Data'

@description('Username for the Virtual Machine')
param windowsAdminUsername string = 'arcdemo'

@description('Enable automatic logon into ArcBox Virtual Machine')
param vmAutologon bool = false

@description('Override default RDP port using this parameter. Default is 3389. No changes will be made to the client VM.')
param rdpPort string = '3389'

@description('Password for Windows account. Password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. The value must be between 12 and 123 characters long')
@minLength(12)
@maxLength(123)
param windowsAdminPassword string

@description('The Windows version for the VM. This will pick a fully patched image of this given Windows version')
param windowsOSVersion string = '2022-datacenter-g2'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Resource Id of the subnet in the virtual network')
param subnetId string

param resourceTags object = {
  Project: 'jumpstart_arcbox'
}
param spnAuthority string = environment().authentication.loginEndpoint

@description('Your Microsoft Entra tenant Id')
param tenantId string
param azdataUsername string = 'arcdemo'

@secure()
param azdataPassword string
param acceptEula string = 'yes'
param registryUsername string = 'registryUser'

@secure()
param registryPassword string = newGuid()
param arcDcName string = 'arcdatactrl'
param mssqlmiName string = 'arcsqlmidemo'

@description('Name of PostgreSQL server group')
param postgresName string = 'arcpg'

@description('Number of PostgreSQL worker nodes')
param postgresWorkerNodeCount int = 3

@description('Size of data volumes in MB')
param postgresDatasize int = 1024

@description('Choose how PostgreSQL service is accessed through Kubernetes networking interface')
param postgresServiceType string = 'LoadBalancer'

@description('Name for the staging storage account using to hold kubeconfig. This value is passed into the template as an output from mgmtStagingStorage.json')
param stagingStorageAccountName string

@description('Name for the environment Azure Log Analytics workspace')
param workspaceName string

@description('The base URL used for accessing artifacts and automation artifacts.')
param templateBaseUrl string

@description('The flavor of ArcBox you want to deploy. Valid values are: \'Full\', \'ITPro\'')
@allowed([
  'Full'
  'ITPro'
  'DevOps'
  'DataOps'
])
param flavor string = 'Full'

@description('Choice to deploy Bastion to connect to the client VM')
param deployBastion bool = false

@description('User github account where they have forked https://github.com/microsoft/azure-arc-jumpstart-apps')
param githubUser string

@description('The name of the K3s cluster')
param k3sArcClusterName string = 'ArcBox-K3s'

@description('The name of the AKS cluster')
param aksArcClusterName string = 'ArcBox-AKS-Data'

@description('The name of the AKS DR cluster')
param aksdrArcClusterName string = 'ArcBox-AKS-DR-Data'

@description('Domain name for the jumpstart environment')
param addsDomainName string = 'jumpstart.local'

@description('The custom location RPO ID. This parameter is only needed when deploying the DataOps flavor.')
param customLocationRPOID string = ''

@description('The SKU of the VMs disk')
param vmsDiskSku string = 'Premium_LRS'

var bastionName = 'ArcBox-Bastion'
var publicIpAddressName = deployBastion == false ? '${vmName}-PIP' : '${bastionName}-PIP'
var networkInterfaceName = '${vmName}-NIC'
var osDiskType = 'Premium_LRS'
var PublicIPNoBastion = {
  id: publicIpAddress.id
}
resource networkInterface 'Microsoft.Network/networkInterfaces@2022-01-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: deployBastion == false ? PublicIPNoBastion : null
        }
      }
    ]
  }
}

resource publicIpAddress 'Microsoft.Network/publicIpAddresses@2022-01-01' = if (deployBastion == false) {
  name: publicIpAddressName
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
  sku: {
    name: 'Basic'
  }
}

resource vmDisk 'Microsoft.Compute/disks@2023-04-02' = {
  location: location
  name: '${vmName}-VMsDisk'
  sku: {
    name: vmsDiskSku
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: 1024
    burstingEnabled: true
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: vmName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: flavor == 'DevOps' ? 'Standard_B4ms' : flavor == 'DataOps' ? 'Standard_D8s_v5' : 'Standard_D16s_v5'
    }
    storageProfile: {
      osDisk: {
        name: '${vmName}-OSDisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
        diskSizeGB: 1024
      }
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: windowsOSVersion
        version: 'latest'
      }
      dataDisks: [
        {
          createOption: 'Attach'
          lun: 0
          managedDisk: {
            id: vmDisk.id
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: windowsAdminUsername
      adminPassword: windowsAdminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: false
      }
    }
  }
}

resource vmBootstrap 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = {
  parent: vm
  name: 'Bootstrap'
  location: location
  tags: {
    displayName: 'config-bootstrap'
  }
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      fileUris: [
        uri(templateBaseUrl, 'artifacts/Bootstrap.ps1')
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Bypass -File Bootstrap.ps1 -adminUsername ${windowsAdminUsername} -adminPassword ${windowsAdminPassword} -tenantId ${tenantId} -spnAuthority ${spnAuthority} -subscriptionId ${subscription().subscriptionId} -resourceGroup ${resourceGroup().name} -azdataUsername ${azdataUsername} -azdataPassword ${azdataPassword} -acceptEula ${acceptEula} -registryUsername ${registryUsername} -registryPassword ${registryPassword} -arcDcName ${arcDcName} -azureLocation ${location} -mssqlmiName ${mssqlmiName} -POSTGRES_NAME ${postgresName} -POSTGRES_WORKER_NODE_COUNT ${postgresWorkerNodeCount} -POSTGRES_DATASIZE ${postgresDatasize} -POSTGRES_SERVICE_TYPE ${postgresServiceType} -stagingStorageAccountName ${stagingStorageAccountName} -workspaceName ${workspaceName} -templateBaseUrl ${templateBaseUrl} -flavor ${flavor} -k3sArcDataClusterName ${k3sArcDataClusterName} -k3sArcClusterName ${k3sArcClusterName} -aksArcClusterName ${aksArcClusterName} -aksdrArcClusterName ${aksdrArcClusterName} -githubUser ${githubUser} -vmAutologon ${vmAutologon} -rdpPort ${rdpPort} -addsDomainName ${addsDomainName} -customLocationRPOID ${customLocationRPOID}'
    }
  }
}

// Add role assignment for the VM: Azure Key Vault Secret Officer role
resource vmRoleAssignment_KeyVaultAdministrator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vm.id, 'Microsoft.Authorization/roleAssignments', 'Administrator')
  scope: resourceGroup()
  properties: {
    principalId: vm.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalType: 'ServicePrincipal'

  }
}

// Add role assignment for the VM: Owner role
resource vmRoleAssignment_Owner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vm.id, 'Microsoft.Authorization/roleAssignments', 'Owner')
  scope: resourceGroup()
  properties: {
    principalId: vm.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')
    principalType: 'ServicePrincipal'
  }
}

output adminUsername string = windowsAdminUsername
output publicIP string = deployBastion == false ? concat(publicIpAddress.properties.ipAddress) : ''
