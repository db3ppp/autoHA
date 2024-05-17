#!/bin/bash
Cnode=compute11-0803c25-prod-trans.media.kt.com
#Cnode=compute4-0706c8-devtb-trans.media.kt.com
#Cnode=compute01-8a2105c01-md-stag.ipc.kt.com
#inventory="inventory_md_staging_ipc.yml"
inventory="inventory_yd_prod_dmz.yml"
#inventory="inventory_yd_devtb.yml"

#controller3=$(yq '.hosts[0].controller' /prometheus/prometheus-am-executor/examples/inventory/$inventory)
#baremetal=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .baremetal" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
ipmi=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .ipmi" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
sdc1=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .sdc1" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
sdc2=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .sdc2" /prometheus/prometheus-am-executor/examples/inventory/$inventory)


f_check_ssh_sdc() {
##controller에서 sdc ip의 ssh-keygen 생성 필요함
sdc1_check=$(ssh root@$controller3 "ssh -o BatchMode=yes -o ConnectTimeout=5 root@$sdc1 echo ok 2>&1")
sdc2_check=$(ssh root@$controller3 "ssh -o BatchMode=yes -o ConnectTimeout=5 root@$sdc2 echo ok 2>&1")

echo $sdc1_check
echo $sdc2_check
#ssh_check=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@$SDC_ip echo ok 2>&1)
}


f_check_ping_sdc() {
count=5
#controller에서 prometheus서버에서 keygen되어있어야함
if $(ssh root@$controller3 "ping -c $count $sdc1 &> /dev/null"); then
  sdc_check="ok" #sdc1 ping ok

else 
  if $(ssh root@$controller3 "ping -c $count $sdc2 &> /dev/null"); then
    sdc_check="ok" #sdc1 ping fail & sdc2 ping ok

  ## Both sdc1,2 Ping fail : Service effected  
  else
    sdc_check="fail"
  fi
fi


#if ping -c $count $SDC_ip &> /dev/null; then
#  result="success"
#else
#  result="failure"
#fi

echo "SDC Ping check: $sdc_check"
}


##완성본
f_ping_check_SDC() {

HA=$(yq '.hosts[0].HA' /prometheus/prometheus-am-executor/examples/inventory/$inventory)
echo "HA_ip: " $HA

#controller3=$(yq '.hosts[0].controller' /prometheus/prometheus-am-executor/examples/inventory/$inventory)
cinder1=$(yq '.hosts[0].cinder' /prometheus/prometheus-am-executor/examples/inventory/$inventory)
#baremetal=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .baremetal" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
ipmi=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .ipmi" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
sdc1=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .sdc1" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
sdc2=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .sdc2" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
sdc1="172.17.3.16"

count=5
#if $(sshpass -p "root" ssh -o "StrictHostKeyChecking=no" root@$HA "ping -c $count $sdc1 &> /dev/null"); then >> ./sdc_check.log
if $(sshpass -p "root" ssh -o "StrictHostKeyChecking=no" root@$HA "ping -c $count $sdc1 "  >> ./sdc_check.log); then
  sdc_check="ok" #sdc1 ping ok
  echo "##IF CASE##"

else
  if $(sshpass -p "root" ssh -o "StrictHostKeyChecking=no" root@$HA "ping -c $count $sdc2 " >> ./sdc_check.log); then
#  if $(ssh root@$cinder1 "ping -c $count $sdc2 &> /dev/null"); then
    sdc_check="ok" #sdc1 ping fail & sdc2 ping ok
    echo "## ELIF CASE ##"

  ## Both sdc1,2 Ping fail : Service effected  
  else
    sdc_check="fail"
  fi
fi

echo "SDC Ping check: $sdc_check"  >> ./sdc_check.log

}

f_ping_check_SDC
