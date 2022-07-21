
param location string = resourceGroup().location
param baseName string = 'apitest-${uniqueString(resourceGroup().id)}'
param adminEmail string
param organization string = 'Contoso'
param adminUserName string = 'azureuser'
param publicKey string

var vnetName = toLower('vnet-${baseName}')
var laName = toLower('la-${baseName}')
var aiName = toLower('ai-${baseName}')
var aksName = toLower('aks-${baseName}')
var aksVersion = '1.22.11'
var nodeCount = 3
var nodeVmSize = 'Standard_D2s_v3'
var apimName = toLower('apim-${baseName}')
var apimSku = 'Developer'
var apimCapacity = 1
var vmName = toLower('vm-${baseName}')
var vmSize = 'Standard_B1ms'
var tags = {}


resource apimNsg 'Microsoft.Network/networkSecurityGroups@2020-06-01' = {
  name: 'nsg-${apimName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowClientCommunication'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
          destinationPortRanges: [
            '80'
            '443'
          ]
        }
      }
      {
        name: 'AllowManagementEndpoint'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
          destinationPortRange: '3443'
        }
      }
      {
        name: 'AllowLoadBalancer'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
          destinationPortRange: '6390'
        }
      }
      {
        name: 'AllowStorage'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowSQL'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
          access: 'Allow'
          priority: 140
          direction: 'Outbound'
          destinationPortRange: '1433'
        }
      }
    ]
  }
}

resource vmNsg 'Microsoft.Network/networkSecurityGroups@2020-06-01' = {
  name: 'nsg-${vmName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2019-12-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '192.168.4.0/22'
      ]
    }
    subnets: [
      {
        name: 'nodes-subnet'
        properties: {
          addressPrefix: '192.168.4.0/23'
        }
      }
      {
        name: 'apim-subnet'
        properties: {
          addressPrefix: '192.168.6.0/24'
          networkSecurityGroup: {
            id: apimNsg.id
          }
        }
      }
      {
        name: 'vm-subnet'
        properties: {
          addressPrefix: '192.168.7.0/24'
          networkSecurityGroup: {
            id: vmNsg.id
          }
        }
      }
    ]
  }
}

resource nodesSubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' existing = {
  name: '${vnet.name}/nodes-subnet'
}

resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' existing = {
  name: '${vnet.name}/apim-subnet'
}

resource vmSubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' existing = {
  name: '${vnet.name}/vm-subnet'
}

resource la 'Microsoft.OperationalInsights/workspaces@2020-08-01' = {
  name: laName
  location: location
  tags: tags
}

resource ai 'Microsoft.Insights/components@2020-02-02' = {
  name: aiName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: la.id
  }
}

resource apimAi 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${apimName}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: la.id
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2020-09-01' = {
  name: aksName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: aksVersion
    enableRBAC: true
    dnsPrefix: aksName
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        mode: 'System'
        vmSize: nodeVmSize
        type: 'VirtualMachineScaleSets'
        osType: 'Linux'
        enableAutoScaling: false
        vnetSubnetID: nodesSubnet.id
      }
    ]
    apiServerAccessProfile: {
      enablePrivateCluster: false
    }
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: 'standard'
      dockerBridgeCidr: '172.17.0.1/16'
      dnsServiceIP: '10.0.0.10'
      serviceCidr: '10.0.0.0/16'
    }
    addonProfiles: {
      omsagent: {
        config: {
          logAnalyticsWorkspaceResourceID: la.id
        }
        enabled: true
      }
    }
  }
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(nodesSubnet.id, 'Network Contributor')
  scope: nodesSubnet
  properties: {
    principalId: aks.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
  }
}

resource apimPip 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name: 'pip-${apimName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: apimName
    }
  }
}

resource apimDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'azure-api.net'
  location: 'global'
  tags: tags
}

resource apimVNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${apimDnsZone.name}/${apimDnsZone.name}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource recordApim 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: apim.name
  parent: apimDnsZone
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: apim.properties.privateIPAddresses[0]
      }
    ]
  }
}

resource recordApimPortal 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: '${apim.name}.portal'
  parent: apimDnsZone
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: apim.properties.privateIPAddresses[0]
      }
    ]
  } 
}

resource recordApimDeveloper 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: '${apim.name}.developer'
  parent: apimDnsZone
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: apim.properties.privateIPAddresses[0]
      }
    ]
  } 
}

resource recordApimManagement 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: '${apim.name}.management'
  parent: apimDnsZone
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: apim.properties.privateIPAddresses[0]
      }
    ]
  } 
}

resource recordApimScm 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: '${apim.name}.scm'
  parent: apimDnsZone
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: apim.properties.privateIPAddresses[0]
      }
    ]
  } 
}

resource apim 'Microsoft.ApiManagement/service@2021-01-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: apimSku
    capacity: apimCapacity
  }
  properties: {
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnet.id
    }
    publicIpAddressId: apimPip.id
    publisherEmail: adminEmail
    publisherName: organization
  }
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2021-12-01-preview' = {
  name: 'apimlogger'
  parent: apim
  properties: {
    resourceId: apimAi.id
    loggerType: 'applicationInsights'
    credentials: {
      instrumentationKey: apimAi.properties.InstrumentationKey
    }
  }
}

resource apimDiag 'Microsoft.ApiManagement/service/diagnostics@2021-12-01-preview' = {
  name: 'applicationinsights'
  parent: apim
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    logClientIp: true
    loggerId: apimLogger.id
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
  }
}

resource api1 'Microsoft.ApiManagement/service/apis@2021-12-01-preview' = {
  name: 'api1'
  parent: apim
  properties: {
    displayName: 'api1'
    serviceUrl: 'http://192.168.4.253'
    path: 'api'
    apiRevision: '1'
    subscriptionRequired: false
    protocols: [
      'HTTP'
      'HTTPS'
    ]
    isCurrent: true
  }
}

resource reactor 'Microsoft.ApiManagement/service/apis/operations@2021-12-01-preview' = {
  name: 'reactor'
  parent: api1
  properties: {
    displayName: 'reactor'
    method:  'GET'
    urlTemplate: '/reactor/{value}'
    templateParameters: [
      {
        name: 'value'
        type: 'Number'
        defaultValue: '42'
        required: false
        values: [
          '42'
        ]
      }
    ]
  }
}

resource vmPip 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name: 'pip-${vmName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: vmName
    }
  }
}

resource vmNic 'Microsoft.Network/networkInterfaces@2021-02-01' = {
  name: 'nic-${vmName}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vmSubnet.id
          }
          publicIPAddress: {
            id: vmPip.id
            properties: {
              deleteOption: 'Delete'
            }
          }
          privateIPAddress: '192.168.7.10'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2021-03-01' = {
  name: vmName
  location: location
  tags: tags
  properties: {
    osProfile: {
      computerName: vmName
      adminUsername: adminUserName
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: publicKey
            }
          ]
        }
      }
    }
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
      imageReference: {
        publisher: 'canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: vmNic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}
