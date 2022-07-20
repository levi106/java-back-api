#!/usr/bin/fish
set rgName "java-back-api"
if test (az group exists --name $rgName) = "false"
    az group create -n $rgName -l japaneast
end

set publicKey (cat ~/.ssh/id_rsa.pub)
az deployment group create -n java-back-api -g $rgName \
    --template-file=main.bicep \
    --parameters publicKey=$publicKey