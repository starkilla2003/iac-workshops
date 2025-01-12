param location string
param prefix string
param subnetId string
param adminUsername string
@secure()
param adminPassword string
param vmName string
param vmCount int
param isALBPublicIPNeeded bool

var networkInterfaceName = '${vmName}-nic'
var nsgName = '${vmName}-nsg'
var vmSize  = 'Standard_B2ms'

var azureLoadBalancerPublicIpName = '${prefix}-${location}-alb-pip'
var azureLoadBalancerDnsName = '${prefix}-${location}-${uniqueString(subscription().id, resourceGroup().id)}-alb'

resource publicIp 'Microsoft.Network/publicIPAddresses@2022-07-01' = if(isALBPublicIPNeeded) {
  name: azureLoadBalancerPublicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: azureLoadBalancerDnsName
    }
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource nics 'Microsoft.Network/networkInterfaces@2022-07-01' = [for i in range(0, vmCount): {
  name: '${networkInterfaceName}-${i}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          primary: true
          privateIPAddressVersion: 'IPv4'          
        }
      }
    ]
    enableAcceleratedNetworking: false
    enableIPForwarding: false
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}]

resource virtualMachines 'Microsoft.Compute/virtualMachines@2022-11-01' = [for i in range(0, vmCount): {
  name: '${vmName}-${i}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2019-Datacenter'
        version: 'latest'
      }
      osDisk: {
        osType: 'Windows'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        diskSizeGB: 127
      }
    }
    osProfile: {
      computerName: '${vmName}-${i}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
      }
      allowExtensionOperations: true
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[i].id
        }
      ]
    }
  }
}]

resource virtualMachine_IIS 'Microsoft.Compute/virtualMachines/extensions@2022-11-01' = [for i in range(0, vmCount): {
  name: 'IIS'
  parent: virtualMachines[i]
  location: location
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'    
    settings: {      
      fileUris: [
        'https://raw.githubusercontent.com/evgenyb/iac-workshops/main/azure-load-balancing-options/iac/lab-01/scripts/iis-${location}.ps1'
      ]
      commandToExecute: 'powershell -ExecutionPolicy Bypass -File iis-${location}.ps1'
    }
  }
}]

resource windowsAgents 'Microsoft.Compute/virtualMachines/extensions@2022-11-01' = [for i in range(0, vmCount): {
  name: 'AzureMonitorWindowsAgent'
  parent: virtualMachines[i]
  location: location  
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true    
  }
}]
