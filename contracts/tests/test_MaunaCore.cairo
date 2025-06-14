use mauna::MaunaCore::MaunaCore;
use mauna::MaunaCore::MaunaCore::{Event, InternalTrait, Order, TokensMinted};
use mauna::interfaces::IMaunaCore::{IMaunaCoreDispatcher, IMaunaCoreDispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    CustomToken, EventSpyAssertionsTrait, Token, TokenImpl, set_balance, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use starknet::storage::StoragePointerWriteAccess;
use super::utils::{PRAGMA_SEPOLIA, deploy_mock_erc20, setup};

/// TEST MINT FUNTION

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
    let order = Order { collateral, amount_in: collateral_amount, min_amount_out: usdm_amount };

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
// fn test_mint_insufficient_balance() {}

// #[test]
// fn test_mint_insufficient_allowance() {}

// #[test]
// fn test_mint_slippage_exceeded() {}

// #[test]
// fn test_mint_zero_collateral_address() {}

// #[test]
// fn test_mint_zero_collateral_amount() {}

/// TEST REDEEM FUNCTION

// #[test]
// fn test_redeem_success() {}

/// TEST GET ASSET PRICE

#[test]
#[fork(url: "https://starknet-sepolia.public.blastapi.io/rpc/v0_8", block_number: 856892)]
fn test_get_asset_price_and_decimals() {
    // Set up contract state for testing
    let mut state = MaunaCore::contract_state_for_testing();

    // Configure Pragma oracle
    state.pragma_contract.write(PRAGMA_SEPOLIA);

    // Query price and decimals for the asset_id
    let asset_id = 6004514686061859652;
    let (price, decimals) = state._get_asset_price(asset_id);

    // Verify decimals returned by the oracle
    assert(decimals == 8, 'Invalid token decimals');

    // Verify price returned by the oracle
    assert(price == 11_802_075, 'Invalid token price');
}
