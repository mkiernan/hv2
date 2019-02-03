# Procedure to create azure Hv2 image via azure cli // https://shell.azure.com 

az vm create --location southcentralus --authentication-type password --admin-username azureuser --admin-password Azur3Passw0rd --image OpenLogic:CentOS:7.6:latest --resource-group hbgrp --name myhb60rs --size Standard_HB60rs

login to the vm: 

wget https://raw.githubusercontent.com/mkiernan/hv2/master/hb60rs_extension.sh
sudo ./hb60rs_extension.sh
waagent -deprovision+user -force

logout, and back to azure shell / cli: 

az vm deallocate --resource-group hbgrp --name myhb60rs
az vm generalize --resource-group hbgrp --name myhb60rs
az image create --resource-group hbgrp --name hbimpiimg --source myhb60rs
