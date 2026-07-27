 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {NFTMintingPlatform} from "../src/NFTMintingPlatform.sol";


contract Handler is Test {
    NFTMintingPlatform public nft;

    constructor(NFTMintingPlatform _nft) {
        nft = _nft;
    }

    function mint(uint256 quantity) public {
        quantity = bound(quantity, 1, 20);
        uint256 cost = nft.MINT_PRICE() * quantity;
        vm.deal(address(this), cost);
        if (nft.totalSupply() + quantity > nft.MAX_SUPPLY()) return;
        nft.mint{value: cost}(quantity);
    }
}
contract NFTMintingPlatformInvariantTest is Test{

    NFTMintingPlatform public nft;
    Handler public handler;

    function setUp() public {
        nft = new NFTMintingPlatform();
        handler = new Handler(nft);
        targetContract(address(handler));
    }

    function invariant_SupplyNeverExceedsMax() public view {
        assertLe(nft.totalSupply(), nft.MAX_SUPPLY());
    }


}
