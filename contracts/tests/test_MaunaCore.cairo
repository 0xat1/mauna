use mauna::MaunaCore::MaunaCore::{Event, Order, TokensMinted};
use mauna::interfaces::IMaunaCore::{IMaunaCoreDispatcher, IMaunaCoreDispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    CustomToken, EventSpyAssertionsTrait, Token, TokenImpl, set_balance, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use super::utils::{deploy_mock_erc20, setup};

#[test]
fn test_mint_success() {
    let (usdm, collateral, mauna) = setup();

    let user: ContractAddress = 'user'.try_into().unwrap();
    let collateral_amount = 10_u256;
    let usdm_amount = 10_u256;

    // Fund user wallet with collateral
    let token = Token::Custom(
        CustomToken {
            contract_address: collateral, balances_variable_selector: selector!("ERC20_balances"),
        },
    );
    set_balance(user, collateral_amount, token);

    // Init order
    let order = Order {
        benefactor: user,
        beneficiary: user,
        collateral,
        amount_in: collateral_amount,
        min_amount_out: usdm_amount,
    };

    // Approve MaunaCore to spend collateral
    start_cheat_caller_address(collateral, user);
    IERC20Dispatcher { contract_address: collateral }.approve(mauna, collateral_amount);
    stop_cheat_caller_address(collateral);

    // Place mint order
    start_cheat_caller_address(mauna, user);
    let mut spy = spy_events();

    IMaunaCoreDispatcher { contract_address: mauna }.mint(order);
    stop_cheat_caller_address(mauna);

    // Verify collateral spending
    let remaining = IERC20Dispatcher { contract_address: collateral }.balance_of(user);
    assert(remaining == 0, 'Collaterals are not spent');

    // Verify USDm received
    let balance = IERC20Dispatcher { contract_address: usdm }.balance_of(user);
    assert(balance == usdm_amount, 'USDm token not received');

    // Check that an event has been emitted
    let event = Event::TokensMinted(
        TokensMinted {
            caller: user,
            benefactor: user,
            beneficiary: user,
            collateral_asset: collateral,
            collateral_amount: collateral_amount,
            usdm_amount: usdm_amount,
        },
    );
    spy.assert_emitted(@array![(mauna, event)]);
}

#[test]
#[should_panic(expected: 'Asset is not supported')]
fn test_mint_non_supported_collateral() {
    let (_, _, mauna) = setup();

    let user: ContractAddress = 'user'.try_into().unwrap();
    let unsupported_collateral = deploy_mock_erc20();
    let collateral_amount = 10_u256;
    let usdm_amount = 10_u256;

    // Fund user wallet with an unsupported collateral token
    let token = Token::Custom(
        CustomToken {
            contract_address: unsupported_collateral,
            balances_variable_selector: selector!("ERC20_balances"),
        },
    );
    set_balance(user, collateral_amount, token);

    // Init order
    let order = Order {
        benefactor: user,
        beneficiary: user,
        collateral: unsupported_collateral,
        amount_in: collateral_amount,
        min_amount_out: usdm_amount,
    };

    // Approve MaunaCore to spend the unsupported collateral
    start_cheat_caller_address(unsupported_collateral, user);
    IERC20Dispatcher { contract_address: unsupported_collateral }.approve(mauna, collateral_amount);
    stop_cheat_caller_address(unsupported_collateral);

    // Attempt to mint should panic due to unsupported asset used as collateral
    start_cheat_caller_address(mauna, user);
    IMaunaCoreDispatcher { contract_address: mauna }.mint(order);
    stop_cheat_caller_address(mauna);
}
// #[test]
// fn test_mint_zero_benefactor() {}

// #[test]
// fn test_mint_zero_beneficiary() {}

// #[test]
// fn test_mint_zero_collateral() {}

// #[test]
// fn test_mint_zero_collateral_amount() {}

// #[test]
// fn test_mint_insufficient_balance_panics() {}

// #[test]
// fn test_mint_insufficient_allowance_panics() {}

// #[test]
// fn test_mint_slippage_exceeded_panics() {}

#[test]
fn test_redeem_success() {}
