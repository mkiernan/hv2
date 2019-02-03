## Procedure to create azure Hv2 image via azure cli // https://shell.azure.com <br/>

az vm create --location southcentralus --authentication-type password --admin-username azureuser --admin-password Azur3Passw0rd --image OpenLogic:CentOS:7.6:latest --resource-group hbgrp --name myhb60rs --size Standard_HB60rs <br/>

login to the vm:  <br/>

wget https://raw.githubusercontent.com/mkiernan/hv2/master/hb60rs_extension.sh <br/>
chmod +x ./hb60rs_extension.sh <br/>
sudo su - <br/>
sudo ./hb60rs_extension.sh <br/>
waagent -deprovision+user -force <br/>

logout, and back to azure shell / cli: <br/> 

az vm deallocate --resource-group hbgrp --name myhb60rs <br/>
az vm generalize --resource-group hbgrp --name myhb60rs <br/>
az image create --resource-group hbgrp --name hbimpiimg --source myhb60rs <br/>

Record the image string output from the json from the az image create, eg:  

/subscriptions/<subscription id>/resourceGroups/hbgrp/providers/Microsoft.Compute/images/hbimpiimg  

Plug this into the scaleset template https://github.com/mkiernan/hv2
