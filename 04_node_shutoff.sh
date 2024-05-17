#!/bin/bash

stackrc="stackrc_md_staging_ipc"
API_server="10.4.188.23"
baremetal="compute-md-staging-03"
overcloudrc="overcloudrc_md_staging_ipc"
Cnode="compute03-8a2105c03-md-stag.ipc.kt.com"
inventory="inventory_md_staging_ipc.yml"

f_ForceShutoff(){
        ipmi=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .ipmi" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
	ssh root@$API_server "source /root/overcloudrc/$overcloudrc;ipmitool -I lanplus -H $ipmi -U root -P calvin power status "
#	ssh root@$API_server "source /root/overcloudrc/$stackrc;openstack  baremetal node power off $baremetal"
	echo "== HW Shutoff Compeleted =="
	echo "== HW Shutoff Compeleted ==" >> /var/log/prometheus-am-executor-test.log

	nova_com_s=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack --insecure  compute service list --service nova-compute --host $Cnode -c State -f value"`

	echo "#################[ Check down nova-compute ]##################"
	if [ $nova_com_s != "down" ]
	then
 	while :
 	do
	  timestamp=`date +%Y-%m-%d-%H:%M`
	  echo "$timestamp [check]checking nova-compute down.....(result state:$nova_com_s)"
	  if  [ $nova_com_s = "down" ]; then
	   echo "$timestamp [nova-compute Down]!!!!! nova-compute State: $nova_com_s"
	   echo "$timestamp [nova-compute Down]!!!!! nova-compute State: $nova_com_s" >> /var/log/half-autoHA.log
	   break
	  fi
	  nova_com_s=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack --insecure  compute service list --service nova-compute --host $Cnode -c State -f value"`
	done

	echo "Now Available Evacuation"

	else
	  echo "nova-compute Down"
	fi

	echo "FIN"
}

f_ForceShutoff
