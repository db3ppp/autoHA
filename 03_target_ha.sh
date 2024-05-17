#target HA node선정 function
#memory값 가져오는거 resource provider로 조회하는 update version

####################################################
#API_server='10.4.80.214' ##ca13_devtb_ktis director
API_server='10.4.188.23'  ##md_staging_ipc director

#overcloudrc='overcloudrc_yd_prod_central'
overcloudrc='overcloudrc_md_staging_ipc'

#aggHA='YD-PROD-DMZ_PRIV-HA'
aggHA='MD-STAGING-HA'
####################################################


#ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack aggregate show YD-PROD-DMZ_PRIV-HA -c hosts -f yaml --insecure >> /root/halist.yml"


f_checkHA_node() {
	## 1. Save HA_nodes yaml to file
	aggregate=$(ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack aggregate show $aggHA -c hosts -f yaml --insecure")
	echo "$aggregate" > /prometheus/prometheus-am-executor/examples/halist.yml

	## 2. Append HA_list array using yaml format
	HA_list=()
	for i in $(yq '.hosts[$i]' /prometheus/prometheus-am-executor/examples/halist.yml);
	 do 
	  HA_list+=($i);
	 done


	## 3. Check HA node's memory_mb_used => gb
	mem_checklist=()
	for ha_candidate in "${HA_list[@]}"
	 do
          uuid=$(ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack --insecure resource provider list |grep $ha_candidate | cut -d '|' -f 2 ")
          mem_mb=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack --insecure resource provider usage show $uuid |grep -i mem" | awk '{print $4}' `
          echo "mem_mb : " $mem_mb
          reserved_mem_mb=`ssh root@$API_server "source /root/overcloudrc/$overcloudrc;openstack --insecure resource provider inventory list $uuid |grep -i mem" | awk '{print $10}' `
          reserved_mem_gb=$(($reserved_mem_mb/1024))
          echo "reserved_gb : " $reserved_mem_gb


          if [ $mem_mb -eq 0 ]; then
            mem_checklist+=(0)
          else
	    mem_checklist+=($(($mem_mb/1024)))
          fi
	 done

        echo ${HA_list[0]} ": " ${mem_checklist[0]}
        echo ${HA_list[1]} ": " ${mem_checklist[1]}


	## 4. Determine proper HA Target node
	j=0
        HA_target=''
	while [ $j -lt ${#mem_checklist[@]} ]
	 do
	#  echo "while loop start"
#	  if [ ${mem_checklist[$j]} -le 24 ]; then #Reserved memory value : 24
#         if [ ${mem_checklist[$j]} -ge 0 ] && [ ${mem_checklist[$j]} -le 60 ]; then 
         if [ ${mem_checklist[$j]} -ge 0 ] && [ ${mem_checklist[$j]} -le $reserved_mem_gb ]; then
	   echo "if condition(TARGET)"
	   HA_target=${HA_list[$j]}
	   break

	 else
	   echo "else condition(PASS)"
	   j=$(($j+1))
	 fi

	 done

	echo "j: " $j
	echo "proper target HA_node : " $HA_target

#	rm -f halist.yml
}


f_fixHA_node () {
Cnode=compute03-8a2105c03-md-stag.ipc.kt.com
inventory="inventory_md_staging_ipc.yml"

HA_target=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .target" /prometheus/prometheus-am-executor/examples/inventory/$inventory)
echo $HA_target
}

f_checkHA_node
#f_fixHA_node
