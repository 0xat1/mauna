use mauna::USDm::USDm::{BURNER_ROLE, MINTER_ROLE};
use mauna::interfaces::IUSDm::{IUSDmDispatcher, IUSDmDispatcherTrait};
use openzeppelin_access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin_token::erc20::interface::{
    IERC20Dispatcher, IERC20DispatcherTrait, IERC20MetadataDispatcher,
    IERC20MetadataDispatcherTrait,
};
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::ContractAddress;
use super::utils::{ADMIN, deploy_usdm};

#[test]
fn test_token_metadata_initialization() {
    let usdm = deploy_usdm();

    // Verify name, symbol, and decimals
    let name = IERC20MetadataDispatcher { contract_address: usdm }.name();
    let symbol = IERC20MetadataDispatcher { contract_address: usdm }.symbol();
    let decimals = IERC20MetadataDispatcher { contract_address: usdm }.decimals();

    assert!(name == "USDm", "Token name: expected \"USDm\", got {}", name);
    assert!(symbol == "USDm", "Token symbol: expected \"USDm\", got {}", symbol);
    assert!(decimals == 18, "Decimals: expected 18, got {}", decimals);
}

#[test]
fn test_mint_with_minter_role() {
    let usdm = deploy_usdm();
    let minter: ContractAddress = 'minter'.try_into().unwrap();
    let recipient: ContractAddress = 'recipient'.try_into().unwrap();
    let amount = 10_u256;

    // Grant MINTER_ROLE to minter
    start_cheat_caller_address(usdm, ADMIN);
    IAccessControlDispatcher { contract_address: usdm }.grant_role(MINTER_ROLE, minter);
    stop_cheat_caller_address(usdm);

    // Mint tokens as minter
    start_cheat_caller_address(usdm, minter);
    IUSDmDispatcher { contract_address: usdm }.mint(recipient, amount);
    stop_cheat_caller_address(usdm);

    // Verify recipient balance
    let balance = IERC20Dispatcher { contract_address: usdm }.balance_of(recipient);
    assert!(balance == amount, "Balance after mint: expected {}, got {}", amount, balance);
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_mint_without_minter_role() {
    let usdm = deploy_usdm();
    let recipient: ContractAddress = 'recipient'.try_into().unwrap();
    let amount = 10_u256;

    // Attempt mint without MINTER_ROLE (should panic)
    start_cheat_caller_address(usdm, recipient);
    IUSDmDispatcher { contract_address: usdm }.mint(recipient, amount);
    stop_cheat_caller_address(usdm);
}

#[test]
fn test_burn_with_burner_role() {
    let usdm = deploy_usdm();
    let minter: ContractAddress = 'minter'.try_into().unwrap();
    let burner: ContractAddress = 'burner'.try_into().unwrap();
    let recipient: ContractAddress = 'recipient'.try_into().unwrap();
    let amount = 10_u256;

    // Grant MINTER_ROLE and mint tokens
    start_cheat_caller_address(usdm, ADMIN);
    IAccessControlDispatcher { contract_address: usdm }.grant_role(MINTER_ROLE, minter);
    stop_cheat_caller_address(usdm);

    start_cheat_caller_address(usdm, minter);
    IUSDmDispatcher { contract_address: usdm }.mint(recipient, amount);
    stop_cheat_caller_address(usdm);

    // Grant BURNER_ROLE to burner
    start_cheat_caller_address(usdm, ADMIN);
    IAccessControlDispatcher { contract_address: usdm }.grant_role(BURNER_ROLE, burner);
    stop_cheat_caller_address(usdm);

    // Burn tokens as burner
    start_cheat_caller_address(usdm, burner);
    IUSDmDispatcher { contract_address: usdm }.burn(recipient, amount);
    stop_cheat_caller_address(usdm);

    // Verify recipient balance
    let balance = IERC20Dispatcher { contract_address: usdm }.balance_of(recipient);
    assert!(balance == 0, "Balance after burn: expected 0, got {}", balance);
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_burn_without_burner_role() {
    let usdm = deploy_usdm();
    let recipient: ContractAddress = 'recipient'.try_into().unwrap();
    let amount = 10_u256;

    // Attempt burn without BURNER_ROLE (should panic)
    start_cheat_caller_address(usdm, recipient);
    IUSDmDispatcher { contract_address: usdm }.burn(recipient, amount);
    stop_cheat_caller_address(usdm);
}
