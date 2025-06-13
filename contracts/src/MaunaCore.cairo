#[starknet::contract]
pub mod MaunaCore {
    use core::num::traits::Zero;
    use mauna::interfaces::IMaunaCore::IMaunaCore;
    use mauna::interfaces::IUSDm::{IUSDmDispatcher, IUSDmDispatcherTrait};
    use mauna::utils::errors;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
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
        CollateralAdded: CollateralAdded,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokensMinted {
        pub caller: ContractAddress,
        pub benefactor: ContractAddress,
        pub beneficiary: ContractAddress,
        pub collateral_asset: ContractAddress,
        pub collateral_amount: u256,
        pub usdm_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollateralAdded {
        pub caller: ContractAddress,
        pub asset: ContractAddress,
    }

    #[derive(Copy, Drop, Serde)]
    pub struct Order {
        pub benefactor: ContractAddress,
        pub beneficiary: ContractAddress,
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
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        usdm: ContractAddress,
        default_collaterals: Array<ContractAddress>,
    ) {
        // Store the USDm token address
        self.usdm.write(usdm);

        assert(default_collaterals.len() > 0, errors::ZERO_COLLATERALS_SET);

        // Register each initial supported collateral asset
        for default_collateral in default_collaterals {
            self.add_supported_asset(default_collateral);
        };
    }

    #[abi(embed_v0)]
    pub impl MaunaCore of IMaunaCore<ContractState> {
        /// Mint USDm tokens for a supported collateral
        fn mint(ref self: ContractState, order: Order) {
            let caller = get_caller_address();
            let contract = get_contract_address();

            // Verify order parameters
            self._validate_order(order);

            // Ensure benefactor has enough collateral
            let balance = IERC20Dispatcher { contract_address: order.collateral }
                .balance_of(order.benefactor);
            assert(balance >= order.amount_in, errors::INSUFFICIENT_BALANCE);

            // Ensure contract is approved to pull collateral
            let allowance = IERC20Dispatcher { contract_address: order.collateral }
                .allowance(order.benefactor, contract);
            assert(allowance >= order.amount_in, errors::INSUFFICIENT_ALLOWANCE);

            // Transfer collateral
            let success = IERC20Dispatcher { contract_address: order.collateral }
                .transfer_from(order.benefactor, contract, order.amount_in);
            assert(success, errors::TRANSFER_FAILED);

            // Mint USDm to the beneficiary
            let usdm = self.usdm.read();
            let usdm_amount = order.min_amount_out; // TODO
            IUSDmDispatcher { contract_address: usdm }.mint(order.beneficiary, usdm_amount);

            // Emit a TokensMinted event
            self
                .emit(
                    TokensMinted {
                        caller,
                        benefactor: order.benefactor,
                        beneficiary: order.beneficiary,
                        collateral_asset: order.collateral,
                        collateral_amount: order.amount_in,
                        usdm_amount: order.min_amount_out,
                    },
                );
        }

        /// Redeem USDm tokens for a supported collateral
        fn redeem(ref self: ContractState, order: Order) {}

        /// Add a new collateral asset
        fn add_supported_asset(ref self: ContractState, asset: ContractAddress) {
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
        fn remove_supported_asset(ref self: ContractState, asset: ContractAddress) {}

        /// Check if an asset is supported as collateral
        fn is_supported_asset(self: @ContractState, asset: ContractAddress) -> bool {
            self.supported_collaterals.entry(asset).read()
        }

        /// Get the list of supported collateral assets
        fn get_supported_collaterals(self: @ContractState) -> Array<ContractAddress> {
            ArrayTrait::new()
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        /// Validate basic fields of an Order struct
        fn _validate_order(self: @ContractState, order: Order) {
            // Benefactor must be non-zero
            assert(order.benefactor.is_non_zero(), errors::ZERO_TOKEN_ADDRESS);
            // Beneficiary must be non-zero
            assert(order.beneficiary.is_non_zero(), errors::ZERO_TOKEN_ADDRESS);
            // Collateral address must be non-zero
            assert(order.collateral.is_non_zero(), errors::ZERO_TOKEN_ADDRESS);
            // Collateral must be whitelisted
            assert(self.is_supported_asset(order.collateral), errors::ASSET_NOT_SUPPORTED);
            // Deposit amount must be non-zero
            assert(order.amount_in > 0, errors::ZERO_TOKEN_AMOUNT);
        }
    }
}
