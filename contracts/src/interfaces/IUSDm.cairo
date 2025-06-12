use starknet::ContractAddress;

#[starknet::interface]
pub trait IUSDm<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, account: ContractAddress, amount: u256);
}
