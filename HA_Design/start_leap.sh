#!/bin/sh

# modify the following parameters if necessary
backupip=<FILL IN THE IP OF BACKUP VM>
backup_sshkeyfile=<FILL IN THE PATH OF SSH_KEY>

sysctl -w kernel.core_pattern=core.leap

cd /home/ubuntu/leap/

./cleos get info
r=$?
if [ $r -eq 0 ]
then
  echo "=== seems nodeos is running already ==="
  # avoid this script frequently being called
  sleep 30
  exit 1
fi

sec1=`date +%s`

sudo sh -c "ulimit -c unlimited && ulimit -n 30000 && ulimit -s 64000 && ./nodeos --p2p-accept-transactions=0 --database-map-mode=locked --data-dir=./data-dir  --config-dir=./data-dir --http-max-response-time-ms=1000 --disable-replay-opts --max-body-size=10000000 $@"

sec2=`date +%s`
diff=$((sec2-sec1))

if [ $diff -lt 60 ]
then
  echo "=== failed to start nodeos, try to recover from snapshot file ==="
  sudo pkill -9 nodeos
  sleep 10
  scp -i $backup_sshkeyfile -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$backupip:~/last_snapshot.bin ~/last_snapshot.bin
  sudo rm -rf ./data-dir/state/*
  sudo sh -c "ulimit -c unlimited && ulimit -n 30000 && ulimit -s 64000 && ./nodeos --p2p-accept-transactions=0 --database-map-mode=locked --data-dir=./data-dir  --config-dir=./data-dir --http-max-response-time-ms=1000 --disable-replay-opts --max-body-size=10000000 --snapshot /home/ubuntu/last_snapshot.bin $@"
fi

