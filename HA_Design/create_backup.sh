#!/bin/sh

PATH=/usr/bin:/sbin:; export PATH

date=$(date '+%Y_%m_%d_%H_%M_%S')

echo "=== starting backup: now is $date ==="

name="backup_$date.tgz"
tmp_name="backup_$date.tmp.tgz"
name2="backup_$date.evm.tgz"
tmp_name2="backup_$date.evm.tmp.tgz"

curl --location --request POST "127.0.0.1:8881/" --header "Content-Type: application/json" --data-raw "{\"method\":\"eth_blockNumber\",\"params\":[\"0x1\",false],\"id\":0}"
r=$?

if [ $r -eq 0 ]
then
  echo "rpc seems responding"
else
  echo "OH! rpc not working!!!"
  exit 1
fi

echo "=== try to grep error from rpc response ==="
r=`curl --location --request POST "127.0.0.1:8881/" --header "Content-Type: application/json" --data-raw "{\"method\":\"eth_blockNumber\",\"params\":[\"0x1\",false],\"id\":0}" | grep error | wc -l`

if [ $r -eq 0 ]
then
  echo "rpc seems working fine without error"
else
  echo "OH! rpc response has error!!!"
  exit 1
fi

LEAP_BASE=/home/ubuntu/leap
${LEAP_BASE}/cleos get info
r=$?

if [ $r -eq 0 ]
then
  echo "cleos get info seems working fine"
else 
  echo "OH! cleos get info not working!!!"
  exit 2
fi

echo "stop eos-evm node & rpc"
pkill eos-evm-node
pkill eos-evm-rpc
sleep 2.0

echo "create leap snapshot..."
rm -rf ${LEAP_BASE}/data-dir/snapshots/*
curl http://127.0.0.1:8888/v1/producer/create_snapshot

echo "snapshot created.. stop nodeos"
pkill nodeos
sleep 30.0

curl --location --request POST "127.0.0.1:8881/" --header "Content-Type: application/json" --data-raw "{\"method\":\"eth_blockNumber\",\"params\":[\"0x1\",false],\"id\":0}"
r=$?

if [ $r -eq 0 ]
then
  echo "rpc not killed!!!"
  exit 2
fi

${LEAP_BASE}/cleos get info
r=$?
if [ $r -eq 0 ]
then
  echo "nodeos not killed!!!" 
  exit 3
fi

cd /home/ubuntu
r=`ls ./backups/ -ltr | wc -l`
if [ $r -gt 6 ]
then
  # remove old backups first to save space
  find ./backups/ -mtime +1 -type f -delete
  echo "removed old backups"
fi
rm ${LEAP_BASE}/nodeos.log
rm /home/ubuntu/node/eos-evm/node.log

mkdir backups
tar zcvf backups/$tmp_name2 ./node/eos-evm/chain-data
tar zcvf backups/$tmp_name ./leap/data-dir/state-history ./leap/data-dir/blocks ./leap/data-dir/snapshots ./leap/data-dir/protocol_features

echo "now bring back nodeos"
cd ${LEAP_BASE}
./start.sh > nodeos.log 2>&1 &
sleep 30.0

echo "now bring back eos-evm"
cd /home/ubuntu/node/eos-evm
./start_evm_node.sh > node.log 2>&1 &
./start_rpc.sh > rpc.log 2>&1 &

cd /home/ubuntu
mv backups/$tmp_name backups/$name
mv backups/$tmp_name2 backups/$name2

ln -sf backups/$name ./last_full_backup.tgz
ln -sf backups/$name2 ./last_evm_backup.tgz

echo "backup files $name & $name2 created successfully!"

r=`ls ./backups/ -ltr | wc -l`
if [ $r -gt 6 ]
then
  find ./backups/ -mtime +1 -type f -delete
  echo "removed old backups"
fi

if [ -z "$(ls -A ${LEAP_BASE}/data-dir/snapshots)" ]; then
  echo "snapshot dir ${LEAP_BASE}/data-dir/snapshots contain no files, please fix snapshot"
  exit 4
else
  rm -rf /home/ubuntu/snapshots.old
  mv /home/ubuntu/snapshots /home/ubuntu/snapshots.old
  mv ${LEAP_BASE}/data-dir/snapshots /home/ubuntu/snapshots
  ln -sf ./snapshots/* last_snapshot.bin
  echo "snapshot created at /home/ubuntu/snapshots"
fi
exit 0

