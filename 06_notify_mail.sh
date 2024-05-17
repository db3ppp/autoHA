#!/bin/bash

f_connect_DB(){
DB_USER="readonlyuser"
DB_PASS="readvhxkf!"
DB_HOST="10.220.252.14"
DB_NAME="kcms"

cnode="compute02-1204c04-yd-prod-ktis.media.kt.com"

## OS/AP 담당자 email 출력
#email_query="select distinct sm.oepr_os_mail as os메일, sm.oper_ap_mail as ap메일
#from kcms.sync_itam_host host
#left join (SELECT sm1.id, sm1.unit_code, sm1.oper_ap_name, sm1.oper_ap_mail, sm1.oepr_os_mail, sm1.oper_ap_department FROM  kcms.service_management as sm1 
#left join kcms.service_management as sm2 on sm1.unit_code=sm2.unit_code and sm1.id<sm2.id WHERE sm2.id is null
#) sm on host.service_unit_code=sm.unit_code
#where host.cloud_platform='OPENSTACK' and  host.cnode in ('$cnode') ;"
email_query="select distinct IFNULL(TRIM(sm.oepr_os_mail),'') as os메일, IFNULL(TRIM(sm.oper_ap_mail), '')  as ap메일
from kcms.sync_itam_host host
left join (SELECT sm1.id, sm1.unit_code, sm1.oper_ap_name, sm1.oper_ap_mail, sm1.oepr_os_mail, sm1.oper_ap_department FROM  kcms.service_management as sm1 
left join kcms.service_management as sm2 on sm1.unit_code=sm2.unit_code and sm1.id<sm2.id WHERE sm2.id is null
) sm on host.service_unit_code=sm.unit_code
where host.cloud_platform='OPENSTACK' and  host.cnode in ('$cnode') ;"
# cnode정보 가져오기
# NULL이면 출력하지 않도록 (ok)
# 출력값 사이에 comma(;) 추가(ok)

echo "DB_USER: " $DB_USER "DB_PASS: " $DB_PASS "DB_HOST: " $DB_HOST "DB_NAME:" $DB_NAME
#email=$(mysql -u $DB_USER -p$DB_PASS -h $DB_HOST -D $DB_NAME -se "$email_query")
email=$(mysql -u $DB_USER -p$DB_PASS -h $DB_HOST -D $DB_NAME -sN -e "$email_query" | awk '{print $1","$2","}')
echo $email

#echo "--------------"

#while read -r field1 field2
#do
#  printf "%-10s, %-10s\n" "$field1 $field2"
#done <<< "$email"



info_query="select distinct host.cnode, host.host_name as vm_name, kos.private_ip as vm_ip,
 host.service_name as 서비스명, host.oper_os_name as os담당자,sm.oper_ap_name as AP담당자,
 replace(replace(kos.is_io_operation+0,'0','미위탁'),'1','위탁') as 위탁유무,
 host.service_grade as 서비스등급
from kcms.sync_itam_host host
left join (select private_ip, host_name, max(created), is_io_operation from kcms.os group by host_name) kos
on host.host_name=kos.host_name
left join (SELECT sm1.id, sm1.unit_code, sm1.oper_ap_name, sm1.oper_ap_mail, sm1.oepr_os_mail, sm1.oper_ap_department FROM  kcms.service_management as sm1 
left join kcms.service_management as sm2 on sm1.unit_code=sm2.unit_code and sm1.id<sm2.id WHERE sm2.id is null
) sm
on host.service_unit_code=sm.unit_code
where host.cloud_platform='OPENSTACK' and  host.cnode in ('$cnode');"


total_info=$(mysql -u $DB_USER -p$DB_PASS -h $DB_HOST -D $DB_NAME -se "$info_query")

echo "==VM total_info=="
#compute02-1204c04-yd-prod-ktis.media.kt.com ADID_BAT_01 172.16.49.50 IPTV-ADID 관리 시스템 주민욱 주민욱 미위탁 C
c1="fail node"
c2="VM_name"
c3="VM_ip"
c4="서비스"
c5="OS담당자"
c6="AP담당자"
c7="서비스 등급"
printf "%-15s %-15s %-15s %-15s %-15s %-15s %-15s \n" "$c1 $c2 $c3 $c4 $c5 $c6 $c7"
while read -r f1 f2 f3 f4 f5 f6 f7
do
  printf "%-15s %-15s %-15s %-15s %-15s %-15s %-15s \n" "$f1 $f2 $f3 $f4 $f5 $f6 $f7"
done <<< "$total_info"

#echo $total_info

}



f_send_mail() {

smtp_server="smtp=smtp://10.217.17.252:25"
from_email=COAcenter@kt.com
to_email=hyevery.one@kt.com
#ju.minwook@kt.com,ju.minwook@kt.com, sungsoo1218.moon@kt.com,, junghwan.kim@kt.com,,
#cc_email="ark.park@kt.com,ark.park@kt.com,hyewonn.kim@kt.com,, hyevery.one@kt.com,, "
#bcc_email=ccc@testlab.localhost

now=`date`
subject="[TEST]mail test by hyewon ($now)"
content="Evacuate Start: $now

안녕하세요. kt cloud 입니다.
$cnode 에서 Cnode Down 발생하여 운영부서(IPC서비스운영팀)에서 HA절체 진행중 입니다.

고객님의 VM점검을 부탁드립니다.
문의처: IPC테크센터 1533-1333


================================================================================
$total_info"


echo "$content" | /bin/mail -S $smtp_server -s "$subject" -r $from_email $to_email $cc_email
#echo "cc_mail:" $cc_email

}

f_connect_DB
f_send_mail
