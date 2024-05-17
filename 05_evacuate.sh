#!/bin/bash
Cnode=compute01-8a2105c01-md-stag.ipc.kt.com
inventory="inventory_md_staging_ipc.yml"

f_fix_targetHA() {
HA_target=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .target" /prometheus/prometheus-am-executor/examples/inventory/$inventory)

echo "Target HA node: " $HA_target
#echo "Target HA_node : " $HA_target >> /var/log/prometheus-am-executor-test.log
}

f_ping_check_SDC() {
#controller3=$(yq '.hosts[0].controller' /prometheus/prometheus-am-executor/examples/inventory/$inventory)
cinder1=$(yq '.hosts[0].cinder' /prometheus/prometheus-am-executor/examples/inventory/$inventory)
baremetal=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .baremetal" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
ipmi=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .ipmi" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
sdc1=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .sdc1" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
sdc2=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .sdc2" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
#sdc2="172.17.3.14"
#sdc1="172.17.3.14"

count=5
if $(sshpass -p "root" ssh -o "StrictHostKeyChecking=no" root@$cinder1 "ping -c $count $sdc1 &> /dev/null"); then
  sdc_check="ok" #sdc1 ping ok
  echo "##IF CASE##"

else
  if $(sshpass -p "root" ssh -o "StrictHostKeyChecking=no" root@$cinder1 "ping -c $count $sdc2 &> /dev/null"); then
    sdc_check="ok" #sdc1 ping fail & sdc2 ping ok
    echo "## ELIF CASE ##"

  ## Both sdc1,2 Ping fail : Service effected  
  else
    sdc_check="fail"
  fi
fi
echo "SDC Ping check: $sdc_check"
}

f_Evacuate(){
### PingCheck SDC ###
f_ping_check_SDC
### Find Target HA Node ##
#      f_check_targetHA
f_fix_targetHA


##Changed nova_com_s "up" => "down"
if [ $sdc_check = 'ok' ]; then
  echo "[SDC ping ok] Just Disconnection MGMT network. Not execute Evacuation."

else
  #echo "#################[4. Evacuate VM(changed nova-compute state,)]##################" >> /var/log/prometheus-am-executor-test.log
  echo "#################[4. Evacuate VM(changed nova-compute state,)]##################"

  #ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack --insecure compute service set --enable $HA_target nova-compute --os-compute-api-version=2.11"
  #echo "Enable HA node: " $HA_target >> /var/log/prometheus-am-executor-test.log
  #ssh root@$API_server "source /root/overcloudrc/$overcloudrc;nova --insecure host-evacuate --target_host $HA_target $Cnode" >> /var/log/prometheus-am-executor-test.log
fi
}
f_Evacuate
