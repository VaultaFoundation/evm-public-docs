# Deploy and Support Vaulta EVM Network for Centralized Exchanges and Vaulta EVM Node operators

This document will describes the minimum requirements to deploy and support Vaulta EVM Network for Centralized Cryptocurrency Exchanges.

<!-- contents box begin -->
<table>
<tr/>
<tr>
<td>
<p/>
<div align="center">
<b>Contents</b>
</div>
<p/>
<!-- contents markdown begin -->

1. [Minimum Architecture](#MA)
2. [Building necessary components](#BNC)
3. [Running the Vaulta (spring) nodes with state_history_plugin](#REN)
4. [Running the evm-node & evm-rpc](#REE)
5. [Backup & Recovery of spring & evm-node](#BR)
6. [Running the evm-miner service](#RMS)
7. [[Exchanges Only]: Calculate the irreversible block number from Vaulta chain to Vaulta-EVM Chain](#CRB)
8. [[EVM-Node operators Only]: Setting up the read-write proxy and explorer](#RWP)
9. [Replay the EVM chain for major version upgrades](#REPLAY)
10. [Known Limitations](#KL)

<!-- contents markdown end -->
<p/>
</td>
</tr>
</table>
<!-- contents box end -->

<a name="MA"></a>
## Minimum Architecture 
This is the minimum setup to run a Vaulta EVM service. It does not contain the high availability setup. Exchanges can duplicate the real-time service part for high availability purpose if necessary. 
```
Real-time service:
    +--VM1 (Vaulta spring node) ---+     +--VM2 (Vaulta-EVM node)-+
    | main node process with       | <-- | evm-node & evm-rpc     | <-- eth compatible read requests 
    | state_history_plugin enabled |     +------------------------+     (e.g. eth_getBlockByNumber, eth_call ...)
    +------------------------------+               \
                   ^                                \    +-- VM2 (Vaulta-EVM node)--+
                   |                                 <-- | proxy to separate read & |
                   |                                /    | write requests (optional)| 
                   |                               /     +--------------------------+
                   |                              /
                   |                            +--VM2 (Vaulta-EVM node)--+
                   \- push Vaulta transactions -| evm-miner (wrapper)     | <-- eth_gasPrice 
                                                +-------------------------+     eth_sendRawTransaction

Periodic Backup service: 
    +--VM3 (Backup VM) ------------------------+        +-- VM3 (Backup VM) -+
    | spring node running in irreversible mode | <----- | evm-node & evm-rpc | 
    | with state_history_plugin enabled        |        +--------------------+
    +------------------------------------------+
```
spring node stands for the Vaulta (Level 1) blockchain, and evm-node stands for the Vaulta-EVM (Level 2) blockchain. evm-rpc talk to evm-node 
 in the same VM and it is used for providing read-only ETH APIs (such as eth_getBlockByNumber, eth_call, eth_blockNumber, ... ) which is compatible with standard ETH API. For ETH write requests eth_sendRawTransaction, and eth_gasPrice, they will be served via evm-miner instead of evm-rpc.
 
- VM1: this VM will run Vaulta spring node with state_history_plugin enabled. A high end CPU with good single threaded performance is recommended. RAM: 128GB+, SSD 2TB+ (for storing block logs & state history from the EVM genesis time (2023-04-05T02:18:09 UTC) up to now)
- VM2: this VM will run evm-node, evm-rpc & evm-miner. Recommend to use 8 vCPU, 32GB+ RAM, and 1TB+ SSD
- VM3: this VM will run spring (in irrversible mode), evm-node & evm-rpc and mainly for backup purpose. Recommend to use 8 vCPU, 128GB+ RAM, 3TB+ SSD (backup files can be large).


<a name="BNC"></a>
## Building necessary components:
OS: Recommend to use ubuntu 22.04 or later versions

- Vaulta (spring) Node: the main process for Vaulta chain
please refer to https://github.com/AntelopeIO/spring
The latest pre-built stable version can be downloaded from https://github.com/AntelopeIO/spring/releases


- Vaulta evm-node & evm-rpc: the main process for Vaulta-EVM chain
Please build the latest stable version in https://github.com/VaultaFoundation/evm-node

for example, the latest stable version is v1.0.1 up to the time of writing this doc.
```
git clone https://github.com/VaultaFoundation/evm-node.git
cd evm-node
git checkout release/2.0
git submodule update --init --recursive
mkdir build; cd build;
cmake .. && make -j8
```

- Vaulta Evm Miner: please refer to https://github.com/VaultaFoundation/evm-miner
```
git clone https://github.com/VaultaFoundation/evm-miner.git
cd evm-miner
yarn
```
Copy the .env.example file to .env and fill in the environment variables.
```
yarn start
```

- Proxy to separate read requests & write requests: please refer to https://github.com/VaultaFoundation/evm-node/tree/main/peripherals/proxy



<a name="REN"></a>
## Running the Vaulta (spring) nodes with state_history_plugin (with trace-history=true)

- For the first time: You need a snapshot file whose timestamp is before the EVM genesis timestamp 2023-04-05T02:18:09 UTC.
- The block log and state history logs need to be replayed from the snapshot time and need to be saved together in the periodic backup.
- You need to keep the block logs, state-history logs starting from the snapshot point. This is because evm-node may ask for old blocks for replaying the EVM chain. 
- You can download the snapshot from any public Vaulta snapshot service providers (such as https://snapshots.eosnation.io/), or use your own snapshot.
- Supported version: spring 1.0 or newer versions
  
example data-dir/config.ini
```
chain-state-db-size-mb = 184320

access-control-allow-credentials = false

allowed-connection = any
p2p-listen-endpoint = 0.0.0.0:9876
p2p-max-nodes-per-host = 10
http-server-address = 0.0.0.0:8888
state-history-endpoint = 0.0.0.0:8999

trace-history = true
chain-state-history = false

http-max-response-time-ms = 1000

# add or remove peers if needed
p2p-peer-address=eos.p2p.eosusa.io:9882
p2p-peer-address=p2p.eos.cryptolions.io:9876
p2p-peer-address=p2p.eossweden.se:9876
p2p-peer-address=fullnode.eoslaomao.com:443
p2p-peer-address=mainnet.eosamsterdam.net:9876

# Plugin(s) to enable, may be specified multiple times
plugin = eosio::producer_plugin
plugin = eosio::chain_api_plugin
plugin = eosio::http_plugin
plugin = eosio::producer_api_plugin
plugin = eosio::state_history_plugin
plugin = eosio::net_plugin
plugin = eosio::net_api_plugin
plugin = eosio::db_size_api_plugin
```
example run command (VM1, head or speculative mode):
```
./nodeos --p2p-accept-transactions=0 --data-dir=./data-dir  --config-dir=./data-dir --http-max-response-time-ms=200 --disable-replay-opts --max-body-size=10000000
```
example run command (VM3, irreversible mode):
```
./nodeos --read-mode=irreversible --p2p-accept-transactions=0 --data-dir=./data-dir  --config-dir=./data-dir --http-max-response-time-ms=200 --disable-replay-opts --max-body-size=10000000
```
Notes:
- To boost performance, it is important to set "--p2p-accept-transactions=0" to disallow executing transactions (which are not yet included in a blocks) received from other peers.
- for the 1st time, run it also with `--snapshot=SNAPSHOT_FILE` to begin with the snapshot state.


### Verify the native chain node.
use `./cleos get info` to check if the node the in-sync with the native network (via the head_block_time), for example:
```
./cleos get info
{
  "server_version": "57465074",
  "chain_id": "aca376f206b8fc25a6ed44dbdc66547c36c6c33e3a119ffbeaef943642f0e906",
  "head_block_num": 399277762,
  "last_irreversible_block_num": 399277760,
  "last_irreversible_block_id": "17cc7ec09ef0f9d50c7a7da3751f370ae215912d1f4588b968f4e1d14a257858",
  "head_block_id": "17cc7ec2498e4dae12046843502ec8c88bfdbee801b96aa1ba58ea6e3f2508d6",
  "head_block_time": "2024-10-14T02:30:34.000",
  "head_block_producer": "big.one",
  "virtual_block_cpu_limit": 200000,
  "virtual_block_net_limit": 1048576000,
  "block_cpu_limit": 200000,
  "block_net_limit": 1048576,
  "server_version_string": "v1.0.1",
  "fork_db_head_block_num": 399277762,
  "fork_db_head_block_id": "17cc7ec2498e4dae12046843502ec8c88bfdbee801b96aa1ba58ea6e3f2508d6",
  "server_full_version_string": "v1.0.1-574650744460373f635d48cac9aa6dee67dcbfdb",
  "total_cpu_weight": "382730335491165",
  "total_net_weight": "95742723072332",
  "earliest_available_block_num": 399104422,
  "last_irreversible_block_time": "2024-10-14T02:30:33.000"
}
```

### verify the chain-state (database) size usage: 
use `curl http://127.0.0.1:8888/v1/db_size/get`, for example
```
curl http://127.0.0.1:8888/v1/db_size/get 2>/dev/null | jq
{
  "free_bytes": "92051578720",
  "used_bytes": "101221948576",
  "reclaimable_bytes": 157837488,
  "size": "193273527296",
```


<a name="REE"></a>
## Running the evm-node & evm-rpc

- Copy the mainnet Vaulta-EVM genesis from https://github.com/VaultaFoundation/evm-public-docs/blob/main/mainnet-genesis.json
```
{
    "alloc": {
        "0000000000000000000000000000000000000000": {
            "balance": "0x0000000000000000000000000000000000000000000000000000000000000000" 
        }
    },
    "coinbase": "0x0000000000000000000000000000000000000000",
    "config": {
        "chainId": 17777,
        "homesteadBlock": 0,
        "eip150Block": 0,
        "eip155Block": 0,
        "byzantiumBlock": 0,
        "constantinopleBlock": 0,
        "petersburgBlock": 0,
        "istanbulBlock": 0,
        "trust": {}
    },
    "difficulty": "0x01",
    "extraData": "TrustEVM",
    "gasLimit": "0x7ffffffffff",
    "mixHash": "0x120eb7a4e6a75f1ae89e9da3bd979c263b14b8b2ccdf1892962cbad6bc650c93",
    "nonce": "0x5530ea015b900000",
    "timestamp": "0x642cda61"
}
```


- run the evm-node
```
mkdir ./chain-data
./evm-node --ship-endpoint=<NODEOS_IP_ADDRESS>:8999 --ship-core-account eosio.evm --chain-data ./chain-data --plugin block_conversion_plugin --plugin blockchain_plugin --nocolor 1  --verbosity=4 --genesis-json=./genesis.json
```
- run the evm-rpc (must be in the same VM as evm-node)
```
./evm-rpc --api-spec=eth,debug,net,trace --http-port=0.0.0.0:8881 --evm-node=127.0.0.1:8080 --chaindata=./chain-data
```
- The EVM state, logs will be stored in ./chain-data directory

The evm-rpc will talk to evm-node and provide the eth compatible RPC services, for example, you can check the current block number of evm-node via:
```
curl --location --request POST '127.0.0.1:8881/' --header 'Content-Type: application/json' --data-raw '{"method":"eth_blockNumber","params":["0x1",false],"id":0}'
```
example output:
```
{"id":0,"jsonrpc":"2.0","result":"0xa4e03"}
```
- if either spring or evm-node can't start, follow the recovery process in the next session.

<a name="BR"></a>
## Backup & Recovery of spring & evm-node
- It is quite important for node operator to backup all the state periodically (for example, once per day).
- backup must be done on the spring node running in irreversible mode. And because of such, all the blocks in evm-node has been finialized and it will never has a fork.
- create the nodeos (spring) snapshot:
  ```
  curl http://127.0.0.1:8888/v1/producer/create_snapshot
  ```
- gracefull kill all processes:
```
pkill evm-node
sleep 2.0
pkill evm-rpc
sleep 2.0
pkill nodeos
```
- backup spring's data-dir folder and evm-node's chain-data
- restart nodeos wait until the nodeos sync-up (use ```./cleos get info``` to verify)
- restart evm-node & evm-rpc

Recover process:
- for spring recovery, please restore the data-dir folder of the last backup and use the spring's snapshot
- for evm-node recovery, please restore the chain-data folder of the last backup.



<a name="RMS"></a>
## Running the evm-miner service 
The miner service will help to package the EVM transaction into Vaulta transaction and set to the Vaulta network. It will provide the following 2 eth API:
- eth_gasPrice: retrieve the currect gas price from Vaulta Network
- eth_sendRawTransaction: package the ETH transaction into Vaulta transaction and push into the Vaulta Network.
clone the https://github.com/VaultaFoundation/evm-miner repo

- create your miner account (for example: a123) on Vaulta Network
- open account balance on EVM side:
  ```
  ./cleos push action eosio.evm open '{"owner":"a123"}' -p a123
  ```
- powerup the miner account with enough CPU & NET resource (for example: 1min CPU. 10 MB net per day). You can use some existing auto powerup service such as https://eospowerup.io/auto or push the powerup transaction (eosio::powerup) via cleos.

- prepare the .env file with the correct information
```
PRIVATE_KEY=5KQwrPxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
MINER_ACCOUNT=a123
RPC_ENDPOINTS=http://127.0.0.1:8888|http://192.168.1.1:8888
PORT=18888
LOCK_GAS_PRICE=false
MINER_PERMISSION=active
EXPIRE_SEC=300
```
- build and start the miner
```
npm install
yarn build
yarn start
```
- test if the miner is working
```
curl http://127.0.0.1:18888 -X POST -H "Accept: application/json" -H "Content-Type: application/json" --data '{"method":"eth_gasPrice","params":[],"id":1,"jsonrpc":"2.0"}'
{"jsonrpc":"2.0","id":1,"result":"0x22ecb25c00"}
```


<a name="CRB"></a>
## [For centralized exchanges] Calculate the irreversible block number from Vaulta (L1) chain to Vaulta-EVM (L2) Chain
For centralized exchanges it is important to know up to which block number the chain is irreversible. The `mixHash` field in an EVM(L2) block is associated with the block ID in the Vaulta(L1) chain. Here is the way to calculate the irreversible time of Vaulta-EVM:
- ensure the spring node & evm-node are fully sync-up.
- do a get_info request to spring node.
```
{
  "server_version": "943d1134",
  "chain_id": "aca376f206b8fc25a6ed44dbdc66547c36c6c33e3a119ffbeaef943642f0e906",
  "head_block_num": 316609050,
...
  "earliest_available_block_num": 302853021,
  "last_irreversible_block_time": "2023-06-23T03:10:35.500"
}
```
- in the above example all EVM blocks before `"last_irreversible_block_time": "2023-06-23T03:10:35.500"` are irreversible. Use the time conversion script:
`
python3 -c 'from datetime import datetime; print(hex(int((datetime.strptime("2023-06-23T03:10:35.500","%Y-%m-%dT%H:%M:%S.%f")-datetime(1970,1,1)).total_seconds())))'
`
to get the EVM irreversible blocktime in hex `0x64950d2b`. As EVM block time is 1 second most of the time, exchanges or node operators can easily estimate the EVM block number given the block time. By locating the recent (around 180) EVM blocks, we found out that the EVM blocks up to ```6828746``` are irreversible, because its timestamp is `0x64950d2b`:

`
curl --location --request POST '127.0.0.1:8881/' --header 'Content-Type: application/json' --data-raw '{"method":"eth_getBlockByNumber","params":["6828746",false],"id":0}'
{"id":0,"jsonrpc":"2.0","result":{"difficulty":"0x1","extraData":"0x","gasLimit":"0x7ffffffffff","gasUsed":"0x0","hash":"0x563fe6290cf38d55e4c4d2c86886032a1734ad1e467b7ce06ff52f12ee378b0d","logsBloom":"0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000","miner":"0xbbbbbbbbbbbbbbbbbbbbbbbb5530ea015b900000","mixHash":"0x12df121840088703a9fe2f305eefe25dbe97bc57f7e127d922ffa8d005aceea6","nonce":"0x0000000000000000","number":"0x6832ca","parentHash":"0xafebdcf129bd506cee25892b2f20703e5ae98bd95557a04b91ac0f56a3433824","receiptsRoot":"0x0000000000000000000000000000000000000000000000000000000000000000","sha3Uncles":"0x0000000000000000000000000000000000000000000000000000000000000000","size":"0x202","stateRoot":"0x0000000000000000000000000000000000000000000000000000000000000000","timestamp":"0x64950d2b","totalDifficulty":"0x6832cb","transactions":[],"transactionsRoot":"0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421","uncles":[]}}
`

- please ensure the evm block has a non-empty "mixHash" field, which is important because it corresponds to the block ID of the Vaulta (L1) chain. If not, then go for the earlier EVM block until the block with mixHash is found, or simply wait sometime and do it again from the beginning.
- take the first 4 bytes of mixHash. In the above example it is 0x12df1218, convert to decimal number 316609048, which is the block number of the Vaulta (L1) chain.
- send a "get_block" request to nodeos and make sure the mixHash is equal to the block id:
```
./cleos get block 316609048
{
  "timestamp": "2023-06-23T03:10:34.500",
  "producer": "atticlabeosb",
  "confirmed": 0,
  "previous": "12df121796cd96182814f42440afe5d77924f53619bdd92c5855042a3df59516",
...
...
  "id": "12df121840088703a9fe2f305eefe25dbe97bc57f7e127d922ffa8d005aceea6",
  "block_num": 316609048,
  "ref_block_prefix": 808451753
}
```
- If yes (which is in the above example), it means that the EVM chain is irreversible up to block 6828746 (where Vaulta block is 316609048 at 2023-06-23T03:10:34.500). If not, wait sometime until the EVM chain sync up and check again.

### Monitor funds deposits into exchanges:
- For Vaulta tokens on Vaulta-EVM: Since this is the native token, similar to other ETH compatible networks, exchanges can use similar way to query EVM blocks (such as using eth_getBlockByNumber) up to the last irreversible EVM blocks as explained above. Or query the account balance using eth_getBalance if needed.
- For ERC20 tokens on Vaulta-EVM: Also similar to other ETH networks, exchanges can execute the ETH view action (eth_call) to extract the balance of any EVM account, or monitor each EVM blocks.
 
### Confirm if a fund withdrawal is successful or fail:
In order to monitoring fund withdrawal, exchanges need to consider:
- The ```EXPIRE_SEC``` value set in the evm-miner. This value will control how long will the Vaulta trasaction expires in such a way that it will never be included in the blockchain after expiration.
- The irreversible EVM block number.

For example:
- 1. At 9:00:00AM UTC, the upstream signed the ETH transaction with ETH compatible private key and then call eth_sendRawTransaction
- 2. The evm-miner packages the EVM transaction into Vaulta transaction and signed it with Vaulta private key, and push to native Vaulta network.
- 3. If `EXPIRE_SEC` is set to 60, the Vaulta transaction will expire at 9:01:00AM. So we need to wait until the result of `cleos get info` shows that the last_irreversible_block_time > 9:01:00AM. At most cases, thanks to Savanna consesus, the Vaulta Network will have just 1 second finality time, so we ususally need to wait until 9:01:02AM.
- 4. Since all transactions up 9:01:00AM are irreversible, we scan each EVM block between 9:00:00AM and 9:01:01AM (1 sec max timestamp difference between Vaulta and Vaulta-EVM blocks) to confirm whether the transaction is included in the EVM blockchain (so as the native Vaulta blockchain). We can confirm the withdrawal is successfull if we find the transaction in this range. Otherwise, the transaction is already expired and can not be included in the blockchain.
- 5. Alternative to 4, instead of scanning all blocks in the time range, we can get the nonce number of the EVM account to confirm if the withdrawal is successful. But this method only works if there is only one withdrawal pending under that EVM account.



<a name="RWP"></a>
## [Optional] For EVM-Node operators Only: Setting up the read-write proxy and explorer

Follow the build process in https://github.com/VaultaFoundation/evm-node/tree/main/peripherals/proxy

The proxy program will separate Ethereum's write requests (such as eth_sendRawTransaction,eth_gasPrice) from other requests (treated as read requests). The write requests should go to Transaction Wrapper (which wrap the ETH transaction into Antelope transaction and sign it and push to the Antelope blockchain). The read requests should go to evm-rpc.

In order to get it working, docker is required. To install docker in Linux, see https://docs.docker.com/engine/install/ubuntu/

```shell
cd evm-node/peripherals/proxy/
```

- Edit the file `nginx.conf`, find the follow settings:

```json
  upstream write {
    server 192.168.56.101:18888;
  }
  
  upstream read {
    server 192.168.56.101:8881;
  }
```

- Change the IP and port of the write session to your Transaction Wrapper server endpoint.
- Change the IP and port of the read session to your evm-rpc server endpoint
- Build the docker image for the proxy program:

```shell
sudo docker build .
```

- Check the image ID after building the image

```shell
sudo docker image ls
```

Example output:

```txt
REPOSITORY   TAG       IMAGE ID       CREATED         SIZE
<none>       <none>    49564d312df7   2 hours ago     393MB
debian       jessie    3aaeab7a4777   19 months ago   129MB
```

- Run the proxy in docker:

```shell
sudo docker run -p 81:80 -v ${PWD}/nginx.conf:/etc/nginx.conf 49564d312df7
```

In the commmand above we map the host port 81 to the port 80 inside the docker.

- Check if the proxy is responding:

```shell
echo "=== test 8881 rpc ==="
curl --location --request POST '127.0.0.1:8881/' --header 'Content-Type: application/json' --data-raw '{"method":"eth_blockNumber","params":["0x1",false],"id":0}'
echo "=== test 80 proxy->rpc ==="
curl --location --request POST '127.0.0.1:80/' --header 'Content-Type: application/json' --data-raw '{"method":"eth_blockNumber","params":["0x1",false],"id":0,"jsonrpc":"2.0"}'
echo "=== test 18888 wrapper ==="
curl http://127.0.0.1:18888 -X POST -H "Accept: application/json" -H "Content-Type: application/json" --data '{"method":"eth_gasPrice","params":[],"id":1,"jsonrpc":"2.0"}'
echo ""
echo "=== test 80 proxy->wrapper ==="
curl http://127.0.0.1:80 -X POST -H "Accept: application/json" -H "Content-Type: application/json" --data '{"method":"eth_gasPrice","params":[],"id":1,"jsonrpc":"2.0"}'
echo ""
```

Example response:
```
=== test 8881 rpc ===
{"id":0,"jsonrpc":"2.0","result":"0x2f0d68f"}
=== test 80 proxy->rpc ===
{"id":0,"jsonrpc":"2.0","result":"0x2f0d68f"}
=== test 18888 wrapper ===
{"jsonrpc":"2.0","id":1,"result":"0x45d964b800"}
=== test 80 proxy->wrapper ===
{"jsonrpc":"2.0","id":1,"result":"0x45d964b800"}
```

You can now use endpoint `http://127.0.0.1:80` in metamask for your own exSat EVM account operations.


<a name="RWP2"></a>
## [Optional] An alternative way to setting up the read write proxy:
The following python program provides a simple way for the proxy (change the READ_RPC_ENDPOINT, WRITE_RPC_ENDPOINT and SERVER_PORT if necessary):

```
#!/usr/bin/env python3
import random
import os
import json
import time
import calendar
from datetime import datetime

from flask import Flask, request, jsonify
from flask_cors import CORS
from eth_hash.auto import keccak
import requests
import json

from binascii import unhexlify

readEndpoint = os.getenv("READ_RPC_ENDPOINT","http://127.0.0.1:8881")
writeEndpoint = os.getenv("WRITE_RPC_ENDPOINT", "http://127.0.0.1:18888")
listenPort = os.getenv("SERVER_PORT", 5000)
ssl_cert = os.getenv("SSL_CERT","")
ssl_keyfile = os.getenv("SSL_KEYFILE","")

writemethods = {"eth_sendRawTransaction","eth_gasPrice"}

try:
    app = Flask(__name__)
    CORS(app)

    @app.route("/", methods=["POST"])
    def default():
        def forward_request(req):
            if type(req) == dict and ("method" in req) and (req["method"] in writemethods):
                print("write req:" + str(req))
                resp = requests.post(writeEndpoint, json.dumps(req), headers={"Accept":"application/json","Content-Type":"application/json"}).json()
                print("write resp:" + str(resp))
                return resp
            else:
                resp = requests.post(readEndpoint, json.dumps(req), headers={"Accept":"application/json","Content-Type":"application/json"}).json()
                print("resp is:" + str(resp))
                return resp;

        request_data = request.get_json()
        if type(request_data) == dict:
            print("req is:" + str(request_data));
            return jsonify(forward_request(request_data))

        res = []
        for r in request_data:
            res.append(forward_request(r))

        return jsonify(res)

    if len(ssl_cert) > 0 and len(ssl_keyfile) > 0:
        print("Running in SSL mode")
        app.run(host='0.0.0.0',port=listenPort,ssl_context=(ssl_cert, ssl_keyfile))
    else:
        print("Running in non-SSL mode")
        app.run(host='0.0.0.0', port=listenPort)
finally:
    exit(0)
```


### Setup explorer:
Please refer to https://github.com/VaultaFoundation/evm-contract/blob/main/docs/local_testnet_deployment_plan.md & https://github.com/VaultaFoundation/blockscout to setup your own Vaulta-EVM Explorer



<a name="REPLAY"></a>
## Replay the EVM chain for major version upgrades
Sometime full EVM chain is required if there's a major version upgrade of evm-node. This is the suggested replay process:
- 1. Use the backup VM (in which spring node is running in irreversible mode so that it won't be any forks) for replaying
- 2. Gracefully shutdown evm-rpc & evm-node, keep spring node running.
- 3. Backup the evm-node data folder (specified in --chain-data parameter).
- 4. Delete everything in the --chain-data folder, but keep the folder itself
- 5. Replace the evm-node & evm-rpc to the new version
- 6. Start evm-node & evm-rpc again. Replay will be started automatically.
- 7. Query the current replay process, normally replay will finished within hours:
```
curl --location --request POST '127.0.0.1:8881/' --header 'Content-Type: application/json' --data-raw '{"method":"eth_blockNumber","params":["0x1",false],"id":0}'
```
- 8. After replay finishes, gracefully shutdown evm-rpc & evm-node. Make the evm backup of data-dir folder
- 9. Apply the new binaries & the backup to other eos-evm node.


<a name="KL"></a>
## Known Limitations
- evm-node will gracefully stop if the state-history-plugin connection in spring node is dropped. Exchanges or node operators need to have auto-restart script to restart evm-node (and choose the available spring end-point if high availability setup exist)

- In some rare case, evm-node can not handle forks happened in Native Vaulta (L1) chain. Exchanges or node operators may need to run the recovery process.

- If evm-node crashes, in some case it may not able to start due to database error. Exchanges or node operators may need to run the recovery process.
