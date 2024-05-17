#!/bin/bash

f_check_HAresource() {
          echo "$(date) "  "@f_check_HAresource function Start" >> /var/log/prometheus-am-executor-test.log
          echo "$(date) "  "Try to find the other HA node..." >> /var/log/prometheus-am-executor-test.log


	  ## 1. Append HA_list array using yaml format
          echo "$(date) "  "@f_check_HAresource : 1)Append HA_list array" >> /var/log/prometheus-am-executor-test.log
	  HA_list=()
	  for i in $(yq '.hosts[]' /prometheus/prometheus-am-executor/examples/halist.yml);
	   do 
	    HA_list+=($i);
	   done

	  ## 2. Check HA node's memory_mb_used => gb
          echo "$(date) "  "@f_check_HAresource : 2)Check HA node's memory" >> /var/log/prometheus-am-executor-test.log
	  mem_checklist=()
	  for ha_candidate in "${HA_list[@]}"
	   do
            uuid=$(ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack resource provider list |grep $ha_candidate | cut -d '|' -f 2 ")
            mem_mb=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack resource provider usage show $uuid |grep -i mem" | awk '{print $4}' `
            reserved_mem_mb=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack resource provider inventory list $uuid |grep -i mem" | awk '{print $10}' `
            reserved_mem_gb=$(($reserved_mem_mb/1024))

            if [ $mem_mb -eq 0 ]; then
              mem_checklist+=(0)
            else
	      mem_checklist+=($(($mem_mb/1024)))
            fi
	   done

          echo "$(date) "  "f_check_HAresource : 3)Determine proper HA Target" >> /var/log/prometheus-am-executor-test.log
	  ## 3. Determine proper HA Target node
	  j=0
          HA_target=''
	  while [ $j -lt ${#mem_checklist[@]} ]
	   do
           if [ ${mem_checklist[$j]} -ge 0 ] && [ ${mem_checklist[$j]} -le $reserved_mem_gb ]; then
	     HA_target=${HA_list[$j]}
	     break

	   else
	     j=$(($j+1))
	   fi

	   done

	  echo "** Proper target HA_node : " $HA_target
          echo "$(date) "  "** Proper target HA_node : " $HA_target >> /var/log/prometheus-am-executor-test.log
          echo "$(date) "  "@f_check_HAresource function End" >> /var/log/prometheus-am-executor-test.log 
}

f_select_samePoD_HA() { ## For IPC  HA_targeting logic ##
        echo "$(date) "  "@f_select_samePoD function Start" >> /var/log/prometheus-am-executor-test.log
        pod=$(echo $Cnode | cut -d '-' -f 2)
        pod_info=$(echo $pod | cut -d 'c' -f 1)

        
        echo "$(date) "  "@f_select_samePoD : 1)Save HA_nodes yaml file" >> /var/log/prometheus-am-executor-test.log
	## 1. Save HA_nodes yaml to file
	aggregate=$(ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack aggregate show $aggHA -c hosts -f yaml")
	echo "$aggregate" > /prometheus/prometheus-am-executor/examples/halist.yml
        echo -e "$(date) " "cat halist.yml \n" >>/var/log/prometheus-am-executor-test.log
        cat /prometheus/prometheus-am-executor/examples/halist.yml >>/var/log/prometheus-am-executor-test.log

        echo "$(date) "  "@f_select_samePoD : 2)Select HA target with the samePoD" >> /var/log/prometheus-am-executor-test.log
        ## 2. Select HA target with the same PoD name
        samePod_HA=$(yq eval ".hosts[] | select(contains(\"$pod_info\"))" /prometheus/prometheus-am-executor/examples/halist.yml)
        echo "$(date) "  "samePod_HA: " $samePod_HA >> /var/log/prometheus-am-executor-test.log

        echo "$(date) "  "@f_select_samePoD : 3)Check samePoD HA node's memory " >> /var/log/prometheus-am-executor-test.log
        ## 3. Check samePod HA node's memory resource
        if [ ! -z "${samePod_HA// }" ]; then ## 동일상면에 HA노드 확보되어 있는 경우
          echo "$(date) "  "Checking " $samePod_HA "'s  memory Resource..." >> /var/log/prometheus-am-executor-test.log

          uuid=$(ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack resource provider list |grep $samePod_HA | cut -d '|' -f 2 ")
          mem_mb=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack resource provider usage show $uuid |grep -i mem" | awk '{print $4}' `
          mem_gb=$(($mem_mb/1024))
          reserved_mem_mb=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack resource provider inventory list $uuid |grep -i mem" | awk '{print $10}' `
          reserved_mem_gb=$(($reserved_mem_mb/1024))
          echo "$(date) " "resource provider uuid: " $uuid >> /var/log/prometheus-am-executor-test.log
          echo "$(date) " "mem_mb: " $mem_mb >> /var/log/prometheus-am-executor-test.log
          echo "$(date) " "mem_gb: " $mem_gb >> /var/log/prometheus-am-executor-test.log
          echo "$(date) " "reserved_mem_mb: " $reserved_mem_mb >> /var/log/prometheus-am-executor-test.log
          echo "$(date) " "reserved_mem_gb: " $reserved_mem_gb >> /var/log/prometheus-am-executor-test.log


          if [ $mem_gb -ge 0 ] && [ $mem_gb -le $reserved_mem_gb ]; then
            echo "$(date) "  "samePod_HA  Available Resource" >> /var/log/prometheus-am-executor-test.log
            HA_target=$samePod_HA
            echo "$(date) "  "**Target HA node(same pod): " $HA_target
            echo "$(date) "  "**Target HA node(same pod): " $HA_target >> /var/log/prometheus-am-executor-test.log

          else ##동일상면 HA노드에 리소스가 없는 경우
            echo "$(date) "  "[!] samePod_HA !Not available resource"  >> /var/log/prometheus-am-executor-test.log
            f_check_HAresource
          fi


        else ## 동일상면에 HA노드가 없는 경우 (samePod_HA == ' ')
          echo "$(date) "  "[!] 동일상면에 HA노드가 확보되어있지 않습니다."  >> /var/log/prometheus-am-executor-test.log
          echo "$(date) "  "== 다른 pod의 HA노드로 target을 선정합니다. ==" >> /var/log/prometheus-am-executor-test.log

          f_check_HAresource
        fi
  #	rm -f halist.yml

	echo "$(date) "  "@f_select_samePoD function End" >> /var/log/prometheus-am-executor-test.log
}


f_check_targetHA() { ## For EPC HA_targeting logic ##
	## 1. Save HA_nodes yaml to file
	aggregate=$(ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack aggregate show $aggHA -c hosts -f yaml")
	echo "$aggregate" > halist.yml

	## 2. Append HA_list array using yaml format
	HA_list=()
	for i in $(yq '.hosts[$i]' /prometheus/prometheus-am-executor/halist.yml); ##yaml파일 생성되는 절대경로 위치 주의**
	 do 
	  HA_list+=($i);
	 done

	## 3. Check HA node's memory_mb_used => gb
	mem_checklist=()
	for ha_candidate in "${HA_list[@]}"
	 do
          uuid=$(ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack resource provider list |grep $ha_candidate | cut -d '|' -f 2 ")
          mem_mb=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack resource provider usage show $uuid |grep -i mem" | awk '{print $4}' `
          echo "$(date) "  "mem_mb : " $mem_mb
          reserved_mem_mb=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack resource provider inventory list $uuid |grep -i mem" | awk '{print $10}' `
          reserved_mem_gb=$(($reserved_mem_mb/1024))
          echo "$(date) "  "reserved_gb : " $reserved_mem_gb


          if [ $mem_mb -eq 0 ]; then
            mem_checklist+=(0)
          else
	    mem_checklist+=($(($mem_mb/1024)))
          fi
	 done

	echo "$(date) "  ${HA_list[0]} ": " ${mem_checklist[0]}
	echo "$(date) "  ${HA_list[1]} ": " ${mem_checklist[1]}


	## 4. Determine proper HA Target node
	j=0
        HA_target=' '
	while [ $j -lt ${#mem_checklist[@]} ]
	 do
	#  echo "while loop start"
#	  if [ ${mem_checklist[$j]} -le 24 ]; then #Reserved memory value : 24
#         if [ ${mem_checklist[$j]} -ge 0 ] && [ ${mem_checklist[$j]} -le 60 ]; then 
         if [ ${mem_checklist[$j]} -ge 0 ] && [ ${mem_checklist[$j]} -le $reserved_mem_gb ]; then
	   echo "$(date) "  "if condition"
	   HA_target=${HA_list[$j]}
	   break

	 else
	   echo "$(date) "  "else condition"
	   j=$(($j+1))
	 fi

	 done

	echo "$(date) "  "j: " $j
        echo "$(date) "  "proper target HA_node : " $HA_target
	echo "$(date) "  "proper target HA_node : " $HA_target >> /var/log/prometheus-am-executor-test.log

#	rm -f halist.yml
}

f_fix_targetHA () { ##Old version
	HA_target=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .target" /prometheus/prometheus-am-executor/examples/inventory/$inventory)

	echo "$(date) "  "Target HA node: " $HA_target
}

f_ping_check_SDC() {
echo "$(date) "  "@f_ping check_SDC function Start" >> /var/log/prometheus-am-executor-test.log
#controller3=$(yq '.hosts[0].controller' /prometheus/prometheus-am-executor/examples/inventory/$inventory)
#cinder1=$(yq '.hosts[0].cinder' /prometheus/prometheus-am-executor/examples/inventory/$inventory)
HA=$(yq '.hosts[0].HA' /prometheus/prometheus-am-executor/examples/inventory/$inventory)

#baremetal=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .baremetal" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
ipmi=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .ipmi" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
sdc1=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .sdc1" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
sdc2=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .sdc2" /prometheus/prometheus-am-executor/examples/inventory/$inventory)

echo "$(date) "  "Checking SDC ping..." >> /var/log/prometheus-am-executor-test.log

count=5
#if $(sshpass -p "root" ssh -o "StrictHostKeyChecking=no" root@$HA "ping -c $count $sdc1 &> /dev/null"); then
echo "$(date) " "SDC1 Ping check start.." >> /var/log/prometheus-am-executor-test.log
if $(sshpass -p "root" ssh -o "StrictHostKeyChecking=no" root@$HA "ping -c $count $sdc1 " >> /var/log/prometheus-am-executor-test.log); then
  sdc_check="ok" #sdc1 ping ok
  echo "$(date) "  "SDC1 Ping check OK" >> /var/log/prometheus-am-executor-test.log

else
#  if $(sshpass -p "root" ssh -o "StrictHostKeyChecking=no" root@$HA "ping -c $count $sdc2 &> /dev/null"); then
  echo "$(date) " "SDC2 Ping check start.." >> /var/log/prometheus-am-executor-test.log
  if $(sshpass -p "root" ssh -o "StrictHostKeyChecking=no" root@$HA "ping -c $count $sdc2 " >> /var/log/prometheus-am-executor-test.log); then
    sdc_check="ok" #sdc1 ping fail & sdc2 ping ok
    echo "$(date) "  "SDC2 Ping check OK" >> /var/log/prometheus-am-executor-test.log

  ## Both sdc1,2 Ping fail : Service effected  
  else
    sdc_check="fail"
    echo "$(date) "  "SDC1&2 Both Ping check Fail" >> /var/log/prometheus-am-executor-test.log
  fi
fi

echo "$(date) "  "** SDC Ping check: $sdc_check"
echo "$(date) "  "** SDC Ping check: $sdc_check" >> /var/log/prometheus-am-executor-test.log
echo "$(date) "  "@f_ping check_SDC function End" >> /var/log/prometheus-am-executor-test.log
}

f_Evacuate(){
echo "$(date) "  "@f_Evacuate function Start" >> /var/log/prometheus-am-executor-test.log

### PingCheck SDC ###
f_ping_check_SDC

### Find Target HA Node ##
#f_check_targetHA
#f_fix_targetHA
#f_select_samePoD_HA


if [ $sdc_check = 'ok' ]; then
  echo "$(date) "  "[SDC ping ok] Just Disconnect MGMT network. Not execute Evacuation."
  echo "$(date) "  "[SDC ping ok] Just Disconnect MGMT network. Not execute Evacuation." >> /var/log/prometheus-am-executor-test.log

else
  f_select_samePoD_HA

  ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack compute service set --enable $HA_target nova-compute --os-compute-api-version=2.11"
  echo "$(date) "  "Enable HA node: " $HA_target >> /var/log/prometheus-am-executor-test.log
  echo "$(date) "  "Fail node: $Cnode  Target node: $HA_target" >> /var/log/prometheus-am-executor-test.log

  echo "$(date) "  "[STAGING-TEST] Execute Evacuate!!" >> /var/log/prometheus-am-executor-test.log
  ssh root@$API_server "source /root/overcloudrc/$overcloudrc;nova host-evacuate --target_host $HA_target $Cnode" >> /var/log/prometheus-am-executor-test.log
fi

echo "$(date) "  "@f_Evacuate function End" >> /var/log/prometheus-am-executor-test.log
}

echo "$(date) "  "#################[Start Evacuation]###################" >> /var/log/prometheus-am-executor-test.log
echo "$(date) "  "#################[Start Evacuation]###################"
Cnode=$1
echo $Cnode
Cnode_ip=$2
overcloudrc=$3
aggHA=$4
stackrc=$5
inventory=$6
API_server=$7
echo "$(date) "  "host : $Cnode ($Cnode_ip) ($overcloudrc) ($aggHA) ($stackrc) ($inventory) ($API_server)" >> /var/log/prometheus-am-executor-test.log

#API_server='10.4.80.214'
#API_server='10.4.188.23'

#f_check_targetHA
#HA_target=ipc-staging-dev-compute-2.ipc.kt.com


#evacuate_host() {
echo -e "$(date) "  "#################[1. Check SSH DOWN Host]################## \n" >> /var/log/prometheus-am-executor-test.log
echo "$(date) "  "#################[1. Check SSH DOWN Host]##################"

echo -e "$(date) "  "#### Check $Cnode ssh_connect.. \n" >> /var/log/prometheus-am-executor-test.log
#if ssh -o BatchMode=yes -o ConnectTimeout=5 root@$Cnode_ip "echo ok" >/dev/null 2>&1; then
ssh_check=$(ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$Cnode_ip "echo ok" 2>&1)


#if ssh -o BatchMode=yes -o ConnectTimeout=5 root@$Cnode_ip "echo ok" 2>&1; then
#  ssh_check="ok"
#else
#  ssh_check="fail"
#fi

if [ "$ssh_check" = "ok" ] ; then
  echo "$(date) "  "ssh ok. Check JUST DOWN $Cnode's node_exporter" >> /var/log/prometheus-am-executor-test.log
  echo "$(date) "  "ssh ok. Check JUST DOWN $Cnode's node_exporter"

elif [[ "$ssh_check" = "Permission denied"* ]] || [[ "$ssh_check" = Host\ key* ]] ; then
  echo "$(date) "  "no_auth. ssh ok. ($ssh_check)" >> /var/log/prometheus-am-executor-test.log
  echo "$(date) "  "no_auth. ssh ok. ($ssh_check)"

else
  echo "$(date) "  "$Cnode Can NOT be connected..HA Check..." >> /var/log/prometheus-am-executor-test.log
  echo "$(date) "  "$Cnode Can NOT be connected..HA Check..."


  echo -e "$(date) "  "#################[2. Check down VM]################## \n" >> /var/log/prometheus-am-executor-test.log
  echo "$(date) "  "#################[2. Check down VM]##################"
  ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack server list --all-projects --host $Cnode" >> /var/log/prometheus-am-executor-test.log
  ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack server list --all-projects --host $Cnode"
  IFS=$'\n' ALL_vm=(`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack server list --all-projects --host $Cnode -c ID -c Status -f value"`)
  IFS=$'\n' Running_vm=(`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack server list --all-projects --host $Cnode --status ACTIVE -c ID -f value"`)


  ## ALL_vm[@] == 0
  if [ ${#ALL_vm[@]} -eq 0 ]; then
    echo "$(date) "  "$Cnode has no VM, not execute HA.." >> /var/log/prometheus-am-executor-test.log
    echo "$(date) "  "$Cnode has no VM, not execute HA.."

  ## 0 < Running_vm[@] <= ALL_vm[@]
  elif [ ${#ALL_vm[@]} -ge ${#Running_vm[@]} ]; then
#  elif [ ${#ALL_vm[@]} -ge ${#Running_vm[@]} ] && [ ${#Running_vm[@]} -gt 0 ]; then
    nova_com_s=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack compute service list --service nova-compute --host $Cnode -c State -f value"`

    echo -e "$(date) "  "#################[3. Check down nova-compute]################## \n" >> /var/log/prometheus-am-executor-test.log
    echo "$(date) "  "#################[3. Check down nova-compute]##################"
    echo "$(date) " "nova_compute status: $nova_com_s" >> /var/log/prometheus-am-executor-test.log

    if [ $nova_com_s != "down" ]
    then
     while :
     do
          timestamp=`date +%Y-%m-%d-%H:%M`
          echo "$timestamp [check]checking nova-compute down.....(result state:$nova_com_s)"
          echo "$timestamp [check]checking nova-compute down.....(result state:$nova_com_s)" >> /var/log/prometheus-am-executor-test.log
	  if  [ $nova_com_s = "down" ]; then
           echo "$timestamp [nova-compute Down]!!!!! nova-compute State: $nova_com_s"
           echo "$timestamp [nova-compute Down]!!!!! nova-compute State: $nova_com_s" >> /var/log/prometheus-am-executor-test.log
	   break
          fi
	  nova_com_s=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack compute service list --service nova-compute --host $Cnode -c State -f value"`
     done


      ##Changed nova_com_s "up" => "down"
      echo -e "$(date) "  "#################[4. Evacuate VM(changed nova-compute state,)]################## \n" >> /var/log/prometheus-am-executor-test.log
      echo "$(date) "  "#################[4. Evacuate VM(changed nova-compute state,)]##################"
      f_Evacuate


    ## nova_com_s == "down"
    else

      echo -e "$(date) "  "#################[5. Evacuate VM(nova-compute state down,)]################## \n" >> /var/log/prometheus-am-executor-test.log
      echo "$(date) "  "#################[5. Evacuate VM(nova-compute state down,)]##################"
      f_Evacuate
    fi


#  # Running_vm[@] == 0
#  else
#    echo "$Cnode has No Running VM.. Skip Evacuate.." >> /var/log/prometheus-am-executor-test.log
#    echo "$Cnode has No Running VM.. Skip Evacuate.."
#    echo  "${ALL_vm[@]}" >> /var/log/prometheus-am-executor-test.log
#    echo  "${ALL_vm[@]}"
  fi


fi   
#} evacuate_host

echo "$(date) "  "***** FIN autoHA Script *****" >> /var/log/prometheus-am-executor-test.log
echo "$(date) "  "***** FIN autoHA Script *****"
