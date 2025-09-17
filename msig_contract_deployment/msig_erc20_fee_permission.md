<h1>Multisig to set up the "fee" permission for account eosio.erc2o</h1>

**Background**

As the ERC20 token bridge will be supporting more tokens, we need an efficient way to control the bridging fee (ingress fee & egress fee) to ensure the fee can always able to cover the gas cost and the CPU cost introduced by the bridge transactions. 

In this multisig proposal, we propose a special "fee" permission (under "active" permissoin) allow ENF to act on the following actions in account eosio.erc2o:
  - eosio.erc2o::setegressfee
  - eosio.erc2o::setingressfee
  - eosio.erc2o::withdrawfee

**list of actions**:
  - Action 1: create the new permission "fee" in account eosio.erc2o, whose parent permission is "active". This permission will be satisfied by enf@active
  - Action 2: set "fee" as permission for eosio.erc2o::setegressfee
  - Action 3: set "fee" as permission for eosio.erc2o::setingressfee
  - Action 4: set "fee" as permission for eosio.erc2o::withdrawfee
