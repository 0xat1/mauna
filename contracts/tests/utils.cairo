use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;

pub const ADMIN: ContractAddress = 'admin'.try_into().unwrap();

fn deploy_contract(name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

pub fn deploy_usdm() -> ContractAddress {
    let mut calldata = array![];
    ADMIN.serialize(ref calldata);

    deploy_contract("USDm", calldata)
}
