Cnode_ip="10.4.188.14"
#Cnode_ip="10.0.207.212"
#check=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@$Cnode_ip "echo ok" >/dev/null 2>&1)

#if ssh -o BatchMode=yes -o ConnectTimeout=5 root@$Cnode_ip "echo ok" >/dev/null 2>&1; then
if ssh -o BatchMode=yes -o ConnectTimeout=5 root@$Cnode_ip "echo ok" 2>&1; then
  ssh_check="ok"
else
  ssh_check="fail"
fi
#echo "ssh_check: " $ssh_check


if [ $ssh_check = 'ok' ] ; then
  echo "ssh ok. Check JUST DOWN $Cnode's node_exporter"

#elif [ $ssh_check = "Permission denied"* ] ; then
#  echo "no_auth.($ssh_check)"

else
  echo "$Cnode Can NOT be connected..HA Check..."
fi
