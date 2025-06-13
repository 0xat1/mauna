use mauna::MaunaCore::MaunaCore::Order;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMaunaCore<TContractState> {
    fn mint(ref self: TContractState, order: Order);
    fn redeem(ref self: TContractState, order: Order);
    fn add_supported_asset(ref self: TContractState, asset: ContractAddress);
    fn remove_supported_asset(ref self: TContractState, asset: ContractAddress);
    fn is_supported_asset(self: @TContractState, asset: ContractAddress) -> bool;
    fn get_supported_collaterals(self: @TContractState) -> Array<ContractAddress>;
}
