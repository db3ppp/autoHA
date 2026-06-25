#!/bin/bash

# ── 동시 실행 방지 Lock ─────────────────────────────────────
# [ADD] 같은 Cnode에 대한 alert 중복 실행 방지
LOCKFILE="/tmp/autoHA_${1}.lock"
HALIST_FILE="/tmp/autoHA_halist_${1}.yml"
exec 200>"$LOCKFILE"
flock -n 200 || {
  echo "$(date) [warn] $1 이미 처리 중인 프로세스 존재. 종료."
  echo "$(date) [warn] $1 이미 처리 중인 프로세스 존재. 종료." >> /var/log/autoHA-2026.log
  exit 0
}
trap 'rm -f "$LOCKFILE" "$HALIST_FILE"' EXIT
# ───────────────────────────────────────────────────────────

# ── [ADD] 동일 alert(fingerprint) 반복 실행 방지 Cooldown ──────
# 같은 Cnode라도 같은 alert가 짧은 시간 내 resolve→refire 등으로
# 반복 들어오는 경우, 직전 처리가 끝난 직후라도 중복 실행을 막는다.
# (위 Lock은 "동시 실행"만 막고, "순차적으로 빠르게 반복되는 실행"은 못 막음)
COOLDOWN_SEC=300   # 5분. 환경에 맞게 조정 (한 번의 evacuate 처리 시간보다 충분히 길게)
FP="${AMX_ALERT_1_FINGERPRINT:-unknown}"
COOLDOWN_FILE="/tmp/autoHA_fp_${FP}.lastrun"

if [ "$FP" != "unknown" ] && [ -f "$COOLDOWN_FILE" ]; then
  last_run=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
  now=$(date +%s)
  diff=$(( now - last_run ))

  if [ "$diff" -lt "$COOLDOWN_SEC" ]; then
    echo "$(date) [skip] alert($FP) 최근 ${diff}초 전에 이미 처리됨 (cooldown ${COOLDOWN_SEC}초). 종료." \
      >> /var/log/autoHA-2026.log
    echo "$(date) [skip] alert($FP) 최근 ${diff}초 전에 이미 처리됨 (cooldown ${COOLDOWN_SEC}초). 종료."
    exit 0
  fi
fi

# 이번 실행 시각 기록 (성공/실패 여부와 무관하게 "처리 시도"를 기록)
date +%s > "$COOLDOWN_FILE"
# ───────────────────────────────────────────────────────────

f_check_targetHA() {
  echo "$(date)  @f_check_targetHA function Start" >> /var/log/autoHA-2026.log

  ## 1. HA aggregate추가된 노드 정보를 halist.yml로 저장 
  echo "$(date)  @f_check_HAresource : 1)Save HA_nodes yaml to file" >> /var/log/autoHA-2026.log
  aggregate=$(ssh root@"$API_server" \
    "source /home/stack/overcloudrc; openstack aggregate show $aggHA -c hosts -f yaml")
  echo "$aggregate" > "$HALIST_FILE"
  echo "$(date)  cat halist.yml" >> /var/log/autoHA-2026.log
  cat "$HALIST_FILE" >> /var/log/autoHA-2026.log

  ## 2. halist.yml에서 HA aggregate에 속한 노드 목록을 배열에 저장 
  echo "$(date)  @f_check_HAresource : 2)Append HA_list array" >> /var/log/autoHA-2026.log
  HA_list=()

  # [FIX] yq '.hosts[$i]' → yq '.hosts[]' 로 수정
  #       기존 방식은 $i가 yq 내부에서 쉘 변수로 치환되지 않아 전체 배열이 잘못 출력됨
  mapfile -t HA_list < <(yq '.hosts[]' "$HALIST_FILE")

  ## 3. HA노드별 메모리 사용량 확인 (mem_mb) 
  echo "$(date)  @f_check_HAresource : 3)Check HA node's memory" >> /var/log/autoHA-2026.log

  mem_checklist=()
  reserved_checklist=()

  for ha_candidate in "${HA_list[@]}"; do
    uuid=$(ssh root@"$API_server" \
      "source /home/stack/overcloudrc; openstack resource provider list | grep $ha_candidate | cut -d '|' -f 2")
    mem_mb=$(ssh root@"$API_server" \
      "source /home/stack/overcloudrc; openstack resource provider usage show $uuid | grep -i mem" \
      | awk '{print $4}')
#    reserved_mem_mb=$(ssh root@"$API_server" \
#      "source /home/stack/overcloudrc; openstack resource provider inventory list $uuid | grep -i mem" \
#      | awk '{print $10}')
#    reserved_mem_gb=$(( reserved_mem_mb / 1024 ))

    echo "$(date)  HA_candidate     : $ha_candidate" >> /var/log/autoHA-2026.log
#    echo "$(date)  resource provider uuid : $uuid" >> /var/log/autoHA-2026.log
    echo "$(date)  mem_mb           : $mem_mb" >> /var/log/autoHA-2026.log
#    echo "$(date)  reserved_mem_mb  : $reserved_mem_mb" >> /var/log/autoHA-2026.log
#    echo "$(date)  reserved_mem_gb  : $reserved_mem_gb" >> /var/log/autoHA-2026.log

    if [ "$mem_mb" -eq 0 ]; then
      mem_checklist+=(0)
    else
      mem_checklist+=("$(( mem_mb / 1024 ))")
    fi

#    # [FIX] reserved_mem_gb를 노드별로 배열에 저장 (기존: 마지막 노드 값으로 덮어써짐)
#    reserved_checklist+=("$reserved_mem_gb")
  done

  ## 4. HA 타겟 선정: mem_mb=0 (VM 없는 빈 노드) 
  echo "$(date)  f_check_HAresource : 4)Determine proper HA Target" >> /var/log/autoHA-2026.log

  j=0
  HA_target=''
  while [ $j -lt ${#mem_checklist[@]} ]; do
    if [ "${mem_checklist[$j]}" -eq 0 ]; then
 #      [ "${mem_checklist[$j]}" -le "${reserved_checklist[$j]}" ]; then
      HA_target="${HA_list[$j]}"
      break
    else
      j=$(( j + 1 ))
    fi
  done


# 5. HA 타겟 선정 실패 시 에러 처리 
  if [ -z "$HA_target" ]; then
    echo "$(date)  [ERROR] No proper HA target found among: ${HA_list[*]}" >> /var/log/autoHA-2026.log
    echo "$(date)  [ERROR] No proper HA target found" 
    return 1
  fi
  
  echo "$(date)  Proper target HA_node : $HA_target"
  echo "$(date)  [info] Proper target HA_node : $HA_target" >> /var/log/autoHA-2026.log
  echo "$(date)  @f_check_HAresource function End" >> /var/log/autoHA-2026.log  
}


f_ping_check_SDC() {
  echo "$(date)  @f_ping check_SDC function start" >> /var/log/autoHA-2026.log

  controller=$(yq '.hosts[0].controller' \
    /home/prometheus/prometheus-am-executor/examples/inventory/"$inventory")
  bond1=$(yq e ".hosts[] | select(.name == \"$Cnode\") | .bond1" \
    /home/prometheus/prometheus-am-executor/examples/inventory/"$inventory")

  echo "$(date)  Checking SDC ping..." >> /var/log/autoHA-2026.log

  count=5
  echo "$(date)  Bond1 Ping check start.." >> /var/log/autoHA-2026.log

  # [NOTE] sshpass 평문 패스워드 사용 중 → SSH 키 인증 전환 권장
  if sshpass -p "root" ssh -o "StrictHostKeyChecking=no" root@"$controller" \
     "ping -c $count $bond1" >> /var/log/autoHA-2026.log; then
    sdc_check="ok"
    echo "$(date)  [info] Bond1 Ping check OK" >> /var/log/autoHA-2026.log
  else
    sdc_check="fail"
    echo "$(date)  [err] SDC Ping check Fail" >> /var/log/autoHA-2026.log
  fi

  echo "$(date)  [info] SDC Ping check: $sdc_check"
  echo "$(date)  [info] SDC Ping check: $sdc_check" >> /var/log/autoHA-2026.log
  echo "$(date)  @f_ping check_SDC function End" >> /var/log/autoHA-2026.log
}


f_Evacuate() {
  echo "$(date)  @f_Evacuate function Start" >> /var/log/autoHA-2026.log

  ### PingCheck SDC ###
  f_ping_check_SDC

  if [ "$sdc_check" = 'ok' ]; then
    echo "$(date)  [SDC ping ok] Just Disconnect MGMT network. Not execute Evacuation."
    echo "$(date)  [SDC ping ok] Just Disconnect MGMT network. Not execute Evacuation." >> /var/log/autoHA-2026.log

  else
    # 타겟 선정 ~ evacuate 실행을 글로벌 lock으로 보호 (다른 Cnode 동시 실행 시 중복 타겟 선정 방지)
    GLOBAL_LOCKFILE="/tmp/autoHA_evacuate.lock"
    exec 201>"$GLOBAL_LOCKFILE"
    flock 201

    ### Find Target HA Node ###
    f_check_targetHA

    # [ADD] HA 타겟 선정 실패 시 Evacuate 중단
    if [ -z "${HA_target// /}" ]; then
      echo "$(date)  [err] HA 타겟 노드 선정 실패. Evacuate 중단."
      echo "$(date)  [err] HA 타겟 노드 선정 실패. Evacuate 중단." >> /var/log/autoHA-2026.log
      flock -u 201
      exit 1
    fi

    ssh root@"$API_server" \
      "source /home/stack/overcloudrc; openstack compute service set --enable $HA_target nova-compute" \
      >> /var/log/autoHA-2026.log
    echo "$(date)  [info] Enable HA node: $HA_target" >> /var/log/autoHA-2026.log
    echo "$(date)  Fail node: $Cnode  Target node: $HA_target" >> /var/log/autoHA-2026.log

    echo "$(date)  [TEST] Execute Evacuate!!" >> /var/log/autoHA-2026.log
    ssh root@"$API_server" \
      "source /home/stack/overcloudrc; nova host-evacuate --target_host $HA_target $Cnode" \
      >> /var/log/autoHA-2026.log

    flock -u 201

    # [ADD] evacuate 성공 시 cooldown 파일 제거
    # 노드 문제가 해소(evacuate 완료)되었으므로, 같은 fingerprint의 다음 alert(있다면)는
    # cooldown 없이 바로 정상 처리되도록 함.
    rm -f "$COOLDOWN_FILE"
  fi

  echo "$(date)  @f_Evacuate function End" >> /var/log/autoHA-2026.log
}


# ── 메인 ────────────────────────────────────────────────────
echo "$(date)  #################[ Start auto HA Logic ]###################" >> /var/log/autoHA-2026.log
echo "$(date)  #################[ Start auto HA Logic ]###################"

Cnode=$1
Cnode_ip=$2
aggHA=$3
inventory=$4
API_server=$5

echo "$(date)  host : $Cnode ($Cnode_ip)($aggHA) ($inventory) ($API_server)"
echo "$(date)  [info] host : $Cnode ($Cnode_ip)($aggHA) ($inventory) ($API_server)" >> /var/log/autoHA-2026.log


# ── 1. SSH Check ─────────────────────────────────────────────
echo "$(date)  #################[ 1. Check SSH DOWN Host ]##################" >> /var/log/autoHA-2026.log
echo "$(date)  #################[ 1. Check SSH DOWN Host ]##################"

ssh_check=$(ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@"$Cnode_ip" "echo ok" 2>&1)

if [ "$ssh_check" = "ok" ]; then
  echo "$(date)  [trace] ssh ok. Check JUST DOWN $Cnode's node_exporter" >> /var/log/autoHA-2026.log
  echo "$(date)  [trace] ssh ok. Check JUST DOWN $Cnode's node_exporter"

elif [[ "$ssh_check" = "Permission denied"* ]] || [[ "$ssh_check" = "Host key"* ]]; then
  echo "$(date)  [trace] no_auth. ssh ok. ($ssh_check)" >> /var/log/autoHA-2026.log
  echo "$(date)  [trace] no_auth. ssh ok. ($ssh_check)"

else
  echo "$(date)  [err] $Cnode Can NOT be connected..HA Logic Check..." >> /var/log/autoHA-2026.log
  echo "$(date)  [err] $Cnode Can NOT be connected..HA Logic Check..."


  # ── 2. Check Down VM ───────────────────────────────────────
  echo "$(date)  #################[ 2. Check down VM ]##################" >> /var/log/autoHA-2026.log
  echo "$(date)  #################[ 2. Check down VM ]##################"

  ssh root@"$API_server" \
    "source /home/stack/overcloudrc; openstack server list --all-projects --host $Cnode" \
    >> /var/log/autoHA-2026.log
  ssh root@"$API_server" \
    "source /home/stack/overcloudrc; openstack server list --all-projects --host $Cnode"

  mapfile -t ALL_vm < <(ssh root@"$API_server" \
    "source /home/stack/overcloudrc; \
     openstack server list --all-projects --host $Cnode -c ID -c Status -f value")
  mapfile -t Running_vm < <(ssh root@"$API_server" \
    "source /home/stack/overcloudrc; \
     openstack server list --all-projects --host $Cnode --status ACTIVE -c ID -f value")

  if [ "${#ALL_vm[@]}" -eq 0 ]; then
    echo "$(date)  $Cnode has no VM, not execute HA.." >> /var/log/autoHA-2026.log
    echo "$(date)  $Cnode has no VM, not execute HA.."

  elif [ "${#ALL_vm[@]}" -ge "${#Running_vm[@]}" ]; then
    nova_com_s=$(ssh root@"$API_server" \
      "source /home/stack/overcloudrc; \
       openstack compute service list --service nova-compute --host $Cnode -c State -f value")

    echo "$(date)  #################[ 3. Check down nova-compute ]##################" >> /var/log/autoHA-2026.log
    echo "$(date)  #################[ 3. Check down nova-compute ]##################"
    echo "$(date)  [info] nova_compute status: $nova_com_s" >> /var/log/autoHA-2026.log


    # nova_compute가 up 상태일 경우, down 상태가 될 때까지 대기 후 evacuate 수행 
    if [ "$nova_com_s" != "down" ]; then

      # [FIX] 무한루프 → 타임아웃(120초) 추가, service_down_time=60초 
      max_wait=120
      elapsed=0
      while [ $elapsed -lt $max_wait ]; do
        timestamp=$(date +%Y-%m-%d-%H:%M)
        echo "$timestamp [check] checking nova-compute down.....(result state: $nova_com_s)"
        echo "$timestamp [check] checking nova-compute down.....(result state: $nova_com_s)" >> /var/log/autoHA-2026.log

        if [ "$nova_com_s" = "down" ]; then
          echo "$timestamp [nova-compute Down] nova-compute State: $nova_com_s"
          echo "$timestamp [nova-compute Down] nova-compute State: $nova_com_s" >> /var/log/autoHA-2026.log
          break
        fi

        sleep 10
        elapsed=$(( elapsed + 10 ))
        nova_com_s=$(ssh root@"$API_server" \
          "source /home/stack/overcloudrc; \
           openstack compute service list --service nova-compute --host $Cnode -c State -f value")
      done

      # [ADD] 타임아웃 초과 시 종료
      if [ "$nova_com_s" != "down" ]; then
        echo "$(date)  [err] ${max_wait}초 내 nova-compute down 미확인. 종료." >> /var/log/autoHA-2026.log
        echo "$(date)  [err] ${max_wait}초 내 nova-compute down 미확인. 종료."
        exit 1
      fi

      echo "$(date)  #################[ 4. Evacuate VM(changed nova-compute state) ]##################" >> /var/log/autoHA-2026.log
      echo "$(date)  #################[ 4. Evacuate VM(changed nova-compute state)]##################"
      f_Evacuate

    # nova_compute가 down 상태일 경우, 바로 evacuate 수행 
    else
      echo "$(date)  #################[ 5. Evacuate VM(nova-compute state down) ]##################" >> /var/log/autoHA-2026.log
      echo "$(date)  #################[ 5. Evacuate VM(nova-compute state down) ]##################"
      f_Evacuate
    fi
  fi
fi

echo "$(date)  *****[info] FIN autoHA Script *****" >> /var/log/autoHA-2026.log
echo "$(date)  *****[info] FIN autoHA Script *****"