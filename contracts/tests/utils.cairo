use mauna::USDm::USDm::{BURNER_ROLE, MINTER_ROLE};
use openzeppelin_access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

pub const ADMIN: ContractAddress = 'admin'.try_into().unwrap();

pub const PRAGMA_SEPOLIA: ContractAddress =
    0x36031daa264c24520b11d93af622c848b2499b66b41d611bac95e13cfca131a
    .try_into()
    .unwrap();
pub const PRAGMA_MAINNET: ContractAddress =
    0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b
    .try_into()
    .unwrap();

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

pub fn deploy_mock_erc20() -> ContractAddress {
    let mut calldata = array![];

    deploy_contract("MockERC20", calldata)
}

pub fn deploy_mauna_core(
    usdm: ContractAddress, collaterals: Array<ContractAddress>,
) -> ContractAddress {
    let mut calldata = array![];
    ADMIN.serialize(ref calldata);
    usdm.serialize(ref calldata);
    collaterals.serialize(ref calldata);
    PRAGMA_SEPOLIA.serialize(ref calldata);

    deploy_contract("MaunaCore", calldata)
}

pub fn setup() -> (ContractAddress, ContractAddress, ContractAddress) {
    // Deploy USDm token
    let usdm = deploy_usdm();

    // Deploy mock collateral token
    let collateral = deploy_mock_erc20();

    // Deploy MaunaCore
    let mauna = deploy_mauna_core(usdm, array![collateral]);

    // Grant MaunaCore minter and burner roles on USDm
    start_cheat_caller_address(usdm, ADMIN);
    IAccessControlDispatcher { contract_address: usdm }.grant_role(MINTER_ROLE, mauna);
    IAccessControlDispatcher { contract_address: usdm }.grant_role(BURNER_ROLE, mauna);
    stop_cheat_caller_address(usdm);

    (usdm, collateral, mauna)
}
