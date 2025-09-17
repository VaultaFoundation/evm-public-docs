#!/bin/sh
PATH=/usr/bin:/sbin:; export PATH

curpwd=${PWD}

leap1=<FILL IN FIRST LEAP ENDPOINT>
leap2=<FILL IN SECOND LEAP ENDPOINT>
backupip=<FILL IN IP OF BACKUP VM>
backup_sshkeyfile=<FILL IN FILE PATH OF SSH_KEY>

url=$leap1
date=$(date '+%Y_%m_%d_%H_%M_%S')
sec=`date +%s`

curl http://$leap1:8888/v1/chain/get_info
r1=$?
curl http://$leap2:8888/v1/chain/get_info
r2=$?

if [ $r1 -eq 0 ]
then
  url=$leap1
else
  if [ $r2 -eq 0 ]
  then
    url=$leap2
  else
    echo "no leap connection available!!!"
    exit 1
  fi
fi

sleep 5.0

sec1=`date +%s`
./eos-evm-node --ship-endpoint=$url:8999 --ship-core-account eosio.evm --chain-data ./chain-data --plugin block_conversion_plugin --plugin blockchain_plugin --nocolor 1  --verbosity=4 --genesis-json=./genesis.json

sec2=`date +%s`
diff=$((sec2-sec1))

if [ $diff -lt 5 ]
then
  echo "=== failed to start eos-evm-node, try to restore from backup from $backupip==="
  # wait for port 8080 released
  sleep 60.0
  scp -i $backup_sshkeyfile -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$backupip:~/last_evm_backup.tgz ~/
  mv ./chain-data ./chain-data.$date
  mkdir ./chain-data
  cd ~/
  tar zxvf ~/last_evm_backup.tgz
  echo "=== killing eos-evm-rpc process & start eos-evm-node again ==="
  pkill eos-evm-rpc
  cd $curpwd
  ./eos-evm-node --ship-endpoint=$url:8999 --ship-core-account eosio.evm --chain-data ./chain-data --plugin block_conversion_plugin --plugin blockchain_plugin --nocolor 1  --verbosity=4 --genesis-json=./genesis.json
fi

