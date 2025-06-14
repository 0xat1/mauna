#[starknet::contract]
pub mod MaunaCore {
    use core::num::traits::Zero;
    use mauna::interfaces::IMaunaCore::IMaunaCore;
    use mauna::interfaces::IUSDm::{IUSDmDispatcher, IUSDmDispatcherTrait};
    use mauna::utils::errors;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use pragma_lib::abi::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
    use pragma_lib::types::{DataType, PragmaPricesResponse};
    use starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        Vec, VecTrait,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        /// Emitted when USDm tokens are minted
        TokensMinted: TokensMinted,
        /// Emitted when USDm tokens are redeemed
        TokensRedeemed: TokensRedeemed,
        /// Emitted when a collateral asset is added to the whitelist
        CollateralAdded: CollateralAdded,
        /// Emitted when a collateral asset is removed from the whitelist
        CollateralRemoved: CollateralRemoved,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokensMinted {
        pub caller: ContractAddress,
        pub collateral_asset: ContractAddress,
        pub collateral_amount: u256,
        pub usdm_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokensRedeemed {
        pub caller: ContractAddress,
        pub collateral_asset: ContractAddress,
        pub collateral_amount: u256,
        pub usdm_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollateralAdded {
        pub caller: ContractAddress,
        pub asset: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollateralRemoved {
        pub caller: ContractAddress,
        pub asset: ContractAddress,
    }

    #[derive(Copy, Drop, Serde)]
    pub struct Order {
        pub collateral: ContractAddress,
        pub amount_in: u256,
        pub min_amount_out: u256,
    }

    #[storage]
    struct Storage {
        /// Address of the USDm token contract
        usdm: ContractAddress,
        /// Mapping of whitelisted collaterals
        supported_collaterals: Map<ContractAddress, bool>,
        /// List of all whitelisted collateral addresses
        collaterals: Vec<ContractAddress>,
        /// Address of the pragma oracle contract
        pub pragma_contract: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        usdm: ContractAddress,
        default_collaterals: Array<ContractAddress>,
        pragma_contract: ContractAddress,
    ) {
        // Store the USDm token address
        self.usdm.write(usdm);

        assert(default_collaterals.len() > 0, errors::ZERO_COLLATERALS_SET);

        // Register each initial supported collateral asset
        for default_collateral in default_collaterals {
            self.add_supported_asset(default_collateral);
        }

        // Save address of the pragma contract
        self.pragma_contract.write(pragma_contract);
    }

    #[abi(embed_v0)]
    pub impl MaunaCore of IMaunaCore<ContractState> {
        /// Mint USDm tokens for a supported collateral
        fn mint(ref self: ContractState, order: Order) {
            // Verify order parameters
            self._validate_order(order);

            let caller = get_caller_address();
            let contract = get_contract_address();
            let usdm = self.usdm.read();

            // TODO: Verify amount_out >= min_amount_out before transfering collateral

            // Ensure caller has enough collateral
            let balance = IERC20Dispatcher { contract_address: order.collateral }
                .balance_of(caller);
            assert(balance >= order.amount_in, errors::INSUFFICIENT_BALANCE);

            // Ensure caller is approved to pull collateral
            let allowance = IERC20Dispatcher { contract_address: order.collateral }
                .allowance(caller, contract);
            assert(allowance >= order.amount_in, errors::INSUFFICIENT_ALLOWANCE);

            // Transfer collateral
            let success = IERC20Dispatcher { contract_address: order.collateral }
                .transfer_from(caller, contract, order.amount_in);
            assert(success, errors::TRANSFER_FAILED);

            // Mint USDm to the caller
            let usdm_amount = order.min_amount_out; // TODO
            IUSDmDispatcher { contract_address: usdm }.mint(caller, usdm_amount);

            // Emit a TokensMinted event
            self
                .emit(
                    TokensMinted {
                        caller: get_caller_address(),
                        collateral_asset: order.collateral,
                        collateral_amount: order.amount_in,
                        usdm_amount: order.min_amount_out,
                    },
                );
        }

        /// Redeem USDm tokens for a supported collateral
        fn redeem(ref self: ContractState, order: Order) {
            // Verify order parameters
            self._validate_order(order);

            // TODO: Verify amount_out <= min_amount_out before burning the USDm tokens
            // TODO: Verify contract have enough collateral to send before burning

            let caller = get_caller_address();
            let contract = get_contract_address();
            let usdm = self.usdm.read();

            // Ensure caller has enough USDm
            let balance = IERC20Dispatcher { contract_address: usdm }.balance_of(caller);
            assert(balance >= order.amount_in, errors::INSUFFICIENT_BALANCE);

            // Check allowance
            let allowance = IERC20Dispatcher { contract_address: usdm }.allowance(caller, contract);
            assert(allowance >= order.amount_in, errors::INSUFFICIENT_ALLOWANCE);

            // Burn caller USDm tokens
            IUSDmDispatcher { contract_address: usdm }.burn(caller, order.amount_in);

            // Redeem collateral tokens to caller
            let amount_out = order.min_amount_out;
            let success = IERC20Dispatcher { contract_address: order.collateral }
                .transfer(caller, amount_out);
            assert(success, errors::TRANSFER_FAILED);

            // Emit a TokensRedeemed event
            self
                .emit(
                    TokensRedeemed {
                        caller: get_caller_address(),
                        collateral_asset: order.collateral,
                        collateral_amount: order.amount_in,
                        usdm_amount: order.min_amount_out,
                    },
                );
        }

        /// Add a new collateral asset
        fn add_supported_asset(ref self: ContractState, asset: ContractAddress) {
            // TODO: Access-control check
            // Verify asset address is not zero
            assert(asset.is_non_zero(), errors::ZERO_TOKEN_ADDRESS);
            // Verify asset is not already supported as collateral
            assert(
                !self.supported_collaterals.entry(asset).read(), errors::ASSET_ALREADY_SUPPORTED,
            );

            self.supported_collaterals.entry(asset).write(true);
            self.collaterals.push(asset);
            self.emit(CollateralAdded { caller: get_caller_address(), asset });
        }

        /// Remove a supported collateral
        fn remove_supported_asset(ref self: ContractState, asset: ContractAddress) {
            // TODO: Access-control check
            // Verify asset address is not zero
            assert(asset.is_non_zero(), errors::ZERO_TOKEN_ADDRESS);
            // Verify asset is supported as collateral
            assert(self.supported_collaterals.entry(asset).read(), errors::ASSET_NOT_SUPPORTED);

            for i in 0..self.collaterals.len() {
                if (self.collaterals.at(i).read() == asset) {
                    // Pop last element from collaterals list
                    let last_collateral = self.collaterals.pop().unwrap();

                    // If collateral address isn't last element, overwrite with popped element
                    if (i < (self.collaterals.len() - 1)) {
                        self.collaterals.at(i).write(last_collateral);
                    }

                    self.emit(CollateralRemoved { caller: get_caller_address(), asset });

                    return;
                }
            };
        }

        /// Check if an asset is supported as collateral
        fn is_supported_asset(self: @ContractState, asset: ContractAddress) -> bool {
            self.supported_collaterals.entry(asset).read()
        }

        /// Get the list of supported collateral assets
        fn get_supported_assets(self: @ContractState) -> Array<ContractAddress> {
            let mut collaterals = ArrayTrait::new();

            for i in 0..self.collaterals.len() {
                let asset = self.collaterals.at(i).read();
                collaterals.append(asset)
            }

            collaterals
        }
    }

    #[generate_trait]
    pub impl Internal of InternalTrait {
        /// Validate basic fields of an Order struct
        fn _validate_order(self: @ContractState, order: Order) {
            // Collateral address must be non-zero
            assert(order.collateral.is_non_zero(), errors::ZERO_TOKEN_ADDRESS);
            // Collateral must be whitelisted
            assert(self.is_supported_asset(order.collateral), errors::ASSET_NOT_SUPPORTED);
            // Deposit amount must be non-zero
            assert(order.amount_in > 0, errors::ZERO_TOKEN_AMOUNT);
        }

        /// Retrieve spot price and decimals from the Pragma oracle for a given asset ID
        fn _get_asset_price(self: @ContractState, asset_id: felt252) -> (u128, u32) {
            // Read the Pragma oracle address from storage
            let oracle_dispatcher = IPragmaABIDispatcher {
                contract_address: self.pragma_contract.read(),
            };

            // Fetch the spot price and decimals for the asset
            let output: PragmaPricesResponse = oracle_dispatcher
                .get_data_median(DataType::SpotEntry(asset_id));

            (output.price, output.decimals)
        }
    }
}
