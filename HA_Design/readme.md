# High availability design for EOS EVM Infrastucture

This document will describe how to setup an EOS EVM infrastucture with high availability.

## Prerequisite: setup a miniumum EOS EVM service infrastructure
This is a minimum EOS EVM infrastructure setup without high availablity support. Follow the steps from https://github.com/eosnetworkfoundation/evm-public-docs/tree/main/deployments_plan_for_CEX#RMS to setup this infrasture step by step.
```
Real-time service:
    +--VM1 (leap VM) -------------------+     +-- VM2 (EVM node VM) -------+                             
    | leap node running in head mode    | <-- | eos-evm-node & eos-evm-rpc | <-- read requests
    | with state_history_plugin enabled |     +----------------------------+             \     +------ VM2 -------+
    +-----------------------------------+                                                 ---- | proxy            |
                              ^                                                          /     | web-socket-proxy |
                              |               +-- VM2 (EVM node VM) ----+               /      +------------------+ 
                              \-- push EOS ---| eos-evm-miner (wrapper) | <-- write requests 
                                transactions  +-------------------------+ 

Periodic Backup service (no need to scale): 
    +--VM3 (Backup VM) ------------------------+        +--VM3 (Backup VM) ----------+
    | leap node running in irreversible mode   | <----- | eos-evm-node & eos-evm-rpc | 
    | with state_history_plugin enabled        |        +----------------------------+
    +------------------------------------------+       
```

## High availability design step 1: deploy leap nodes to multiple VMs
We first scale the leap node (in the real-time service) from 1 leap VM instance into 2 or more leap VM instance in the same region.
```
Real-time service:
    +-- VM11 ----------+
    |  leap node       |  <---
    +------------------+      \                                       +---- VM2 -----------------+
                               select the available leap to connect --| eos-evm-node, rpc, miner |
    +-- VM12 ----------+      /                                       | proxy, web-socket-proxy  |
    |  leap node       |  <---                                        +--------------------------+
    +------------------+
```
We can use the `get_info` request via a script to find out the available leap node to connect/reconnect. 


## High availability design step 2: deploy eos-evm-node, rpc, miner, proxy and other services to multiple VMs
We then scale up the number of eos-evm-node VM instances from 1 to 2 or even more. Each of them will independently detect and select the available leap node to connect with.
```
Real-time service:
                                                                           +----- VM21 -------------+
                                                                          /| eos-evm-node, rpc, ... |
    +-- VM11 ----------+                                                 / +------------------------+ 
    |  leap node       |  <------\                                      /
    +------------------+          \  VM21, VM22, VM23 independently    /   +----- VM22 -------------+
                                   select the available leap to connect ---| eos-evm-node, rpc, ... |
    +-- VM12 ----------+          /                                   \    +------------------------+
    |  leap node       |  <------/                                     \    
    +------------------+                                                \  +----- VM23 -------------+
                                                                         \ | eos-evm-node, rpc, ... |
                                                                           +------------------------+
```


## High availability design step 3: Using script & pm2 service to manage leap node process
In order to make sure all leap node will be running all the time, we need some auto restart & recover script so that it will:

- 1. detect if there's already a running leap (nodeos) process
- 2. try start leap process normally.
- 3. if leap start fails, clean up the state, recover the state via snapshot generated from backup VM, and restart leap process with snapshot

[This is the template for leap's start.sh script](start_leap.sh) <br/>

we also need to use pm2 service to run the above script as a service.<br/>


## High availability design step 4: Using script & pm2 service to manage eos-evm-node, rpc, miner, proxy..
We also need to use a script `start_evm_node.sh` to auto restart & recover eos-evm-node. The script will do:<br/>

- 1. detect which leap node is avaiable
- 2. try to start eos-evm-node normally, connecting to the state-history-plugin endpoint of the avaiable leap node
- 3. if eos-evm-node start fails, clean up evm-node database, download the evm backup from backup VM, try step 2 one more time.

[This is the template for start_evm_node.sh script](start_evm_node.sh) <br/>


we also need to use pm2 service to run the script as a service. for example:<br/>
`cd eos-evm && pm2 start start_evm_node.sh -l node.log --name evm_node --kill-timeout 10000`

use pm2 to run eos-evm-rpc. for example:<br/>
`cd eos-evm && pm2 start start_rpc.sh -l rpc.log --name evm_rpc1 --kill-timeout 10000`<br/>
in which start_rpc.sh is:<br/>
`./eos-evm-rpc --api-spec=eth,debug,net,trace --chain-id=17777 --http-port=0.0.0.0:8881 --eos-evm-node=127.0.0.1:8080 --chaindata=./chain-data`

use pm2 to run miner. for example:<br/>
`cd tx_wrapper && pm2 start index.js -l wrapper.log --name tx_wrapper --kill-timeout 10000`

use docker to run proxy when VM starts.
```
cd tx_proxy
sudo mkdir -p logs
sudo mkdir -p logs/error
sudo docker run --add-host=host.docker.internal:host-gateway -p 80:80 -v ${PWD}/logs:/var/log/nginx -d --restart=always --name=tx_proxy evm/tx_proxy
sudo docker restart tx_proxy
```
see https://github.com/eosnetworkfoundation/eos-evm-node/tree/main/peripherals/proxy for more details.<br/>


use pm2 to run web-socket-proxy. for example:<br/>
```
cd eos-evm-ws-proxy
WS_LISTENING_HOST=0.0.0.0 pm2 start main.js -l ws_proxy.log --name ws_proxy --kill-timeout 10000 --update-env
```
see https://github.com/eosnetworkfoundation/eos-evm-node/tree/main/peripherals/eos-evm-ws-proxy for more details.<br/>


<br/>

## High availability design step 5 (Optional): scale up multiple miners in each EVM VM:
To further scale up transactions per second, we may also consider scale up multiple miners in each evm machine:
```
Real-time service:
    +--VM1 (leap VM) -------------------+     +-- VM2 (EVM node VM) -------+                             
    | leap node running in head mode    | <-- | eos-evm-node & eos-evm-rpc | <-- read requests
    | with state_history_plugin enabled |     +----------------------------+             \     +------ VM2 -------+
    +-----------------------------------+                                                 ---- | proxy            |
                              ^                                                          /     | web-socket-proxy |
                              |               +-- VM2 (EVM node VM) ----+               /      +------------------+ 
                              \-- push EOS ---| eos-evm-miner1          | <-- write requests 
                                transactions  | eos-evm-miner2          |
                                              | eos-evm-miner3          |
                                              | eos-evm-miner4          |
                                              +-------------------------+											  
```
This can be easily done by appending `-i 4` into the pm2 command:
```
pm2 start ./dist/index.js --name evm-miner -l miner.log --name evm-miner --kill-timeout 10000 -i 4
```

## High availability design step 6: setup the same infrastructure on a second region
We further scale the infrastructure from 1 region to 2 or multiple regions.<br/>
In each region, we can setup a target group for load balancing the traffice between multiple evm-nodes.<br/>
And finally, setup a global DNS load balancer to split the traffic between different region according to their geographical locations.<br/>

However, the backup service is not required to be scaled. 
```
   +---- Region 1 (Real-time service) -------------------------- +
   |  VM11 (leap)                                                |
   |  VM12 (leap)                                                |
   |  VM21 (evm-node, rpc, miners, proxy,...)-\                  | 
   |                                           - target group1   |  <----\
   |  VM22 (evm-node, rpc, miners, proxy,...)-/                  |        \
   +-------------------------------------------------------------+         \--- Global DNS Load balancer      
                                                                           /
   +---- Region 2 (Real-time service) ---------------------------+        /
   |  VM11 (leap)                                                |  <----/
   |  VM12 (leap)                                                |
   |  VM21 (evm-node, rpc, miners, proxy,...)-\                  |
   |                                           - target group1   |
   |  VM22 (evm-node, rpc, miners, proxy,...)-/                  |  
   +-------------------------------------------------------------+
   
   +--- Backup VM in region 1 --------+
   | leap (backup, irreversible mode) |
   | evm-node, rpc                    |
   +----------------------------------+
```


 
## Generate leap & evm backup periodically
Here are the steps to generate leap backup and EVM backup:<br/>

- 1. ensure leap & eos-evm-node is up
- 2. gracefully stop eos-evm-node & eos-evm-rpc
- 3. create leap snapshot
- 4. gracefully stop leap
- 5. backup evm chain-data folder
- 6. backup leap's snapshot, state_history, block logs
- 7. bring up leap
- 8. bring up eos-evm
- 9. remove old backups

[This sample script can be used in backup VM to create leap & evm backup](create_backup.sh) Each time when a backup is generated, both leap node and evm node need to be gracefully shutted down.



