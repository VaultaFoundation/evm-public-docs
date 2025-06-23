# GAS V3 Multisig Deployment for Vaulta EVM

## This document provide an example of the multisig deployment for gas V3 upgrade for Vaulta EVM

### Step 1. check with the current evm-version:

```
cleos get table eosio.evm eosio.evm config
```
If the version is 0 or unset, goto step 2a<br/>
If the version is 1 or 2, goto step 2b<br/>
If the version is 3 or more, then gas v3 has already applied and no further action is required.


### Step 2a: Update evm runtime contract and set version 1 into a single MSIG transaction

```
cleos set contract eosio.evm ./ evm_runtime.wasm evm_runtime.abi -s -d -j -x 3600 > evm_setcode.json
cleos push action eosio.evm setversion '[1]' -s -d -j -x 3600 > evm_setversion.json

# merge these json file into 1 MSIG, and then push the MSIG to the network

```

### Step 2b: Update evm runtime contract only
```
cleos set contract eosio.evm ./ evm_runtime.wasm evm_runtime.abi -s -d -j -x 3600 > evm_setcode.json

# propose the MSIG to execute evm_setcode.json
```

### Step 3: 
- Wait for BP's approval.
- Execute the MSIG after there are enough approvals.
- Check the evm-version again to ensure version is at least 1 and there is no pending version.


### Step 4: 

Calutate the appropriate RAM price, over price and storage price. Then build up the 2nd MSIG with the following actions:
- setgasprices
- setversion(3)
- updtgasparam

```
price_mb="307.2000 EOS"
overhead_price=5000000000
storage_price=2500000000

cleos push action eosio.evm setgasprices "{\"prices\":{\"overhead_price\":${overhead_price},\"storage_price\":${storage_price}}}" -p eosio.evm -x 3599 -s -d -j > act_setgasprices.json 

cleos push action eosio.evm setversion '[3]' -p eosio.evm -x 3599 -s -d -j > act_setver3.json

cleos push action eosio.evm updtgasparam "[\"${price_mb}\",\"${storage_price}\"]" -p eosio.evm -x 3599 -s -d -j > act_updtgasparam.json

# merge act_setgasprices.json, act_setver3.json, and act_updtgasparam.json into 1 MSIG, and then push the MSIG to the network
```

### Step 5:
- Wait for BP's approval.
- Execute the MSIG after there are enough approvals.
- Wait for at least 3 minutes, then trigger a simple EVM transaction. 
- Check evm config again to ensure evm version is 3 and gas prices are all set.
