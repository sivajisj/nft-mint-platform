// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NFTMintingPlatform} from "../src/NFTMintingPlatform.sol";
contract NFTMintingPlatformTest is Test {
    NFTMintingPlatform public nft;

    address public alice = address(0x1);

    function setUp() public {
        nft = new NFTMintingPlatform();
        vm.deal(alice, 10 ether); // give 10 ether to alice to mint the NFT
    }
    receive() external payable {}  

    function testMintSuccess() public {
        vm.prank(alice);
        nft.mint{value: 0.01 ether}(1);

        assertEq(nft.ownerOf(0), alice);
        assertEq(nft.totalSupply(), 1);
    }

    function test_RevertWhen_InsufficientPayment() public {
        vm.prank(alice);
        vm.expectRevert(NFTMintingPlatform.InsufficientFunds.selector);
        nft.mint{value: 0.001 ether}(1);
    }

    function test_AnyoneCanSetMerkleRoot() public {
        address randomUser = address(0x2);
        bytes32 fakeRoot = keccak256("fake");
        vm.prank(randomUser);
        vm.expectRevert();
        nft.setMerkleRoot(fakeRoot);
    }

    function test_RoyaltyInfo() public view {
        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(0, 5 ether);

        assertEq(receiver, address(this));
        assertEq(royaltyAmount, 0.25 ether);
    }

    function test_TokenURI_BeforeAndAfterReveal() public {
        vm.prank(alice);
        nft.mint{value: 0.01 ether}(1);
        nft.setUnrevealedURI("ipfs://mystery-box.json");
        nft.setBaseURI("ipfs://real-metadata/");
        assertEq(nft.tokenURI(0), "ipfs://mystery-box.json");
        nft.reveal();
        assertEq(nft.tokenURI(0), "ipfs://real-metadata/0.json");
    }

    function test_WithdrawSuccess() public {
        vm.prank(alice);
        nft.mint{value: 0.01 ether}(1);
        uint256 ownerBalanceBefore = address(this).balance;

        nft.withdraw();
        assertEq(address(nft).balance, 0); // contract balance drained
        assertEq(address(this).balance, ownerBalanceBefore + 0.01 ether);
    }

    function testFuzz_MintRespectsPaymentAndSupply(uint256 quantity, uint256 payment) public{
       quantity = bound(quantity, 1, 100);
       payment = bound(payment, 0, 100 ether);
       vm.deal(alice, 100 ether);

       vm.prank(alice);
       if(payment < nft.MINT_PRICE() * quantity){
        vm.expectRevert(NFTMintingPlatform.InsufficientFunds.selector);
        nft.mint{value: payment}(quantity);

       } else if(totalSupply_after(quantity) > nft.MAX_SUPPLY()){

       vm.expectRevert(NFTMintingPlatform.ExceedMaxSupply.selector);
        nft.mint{value: payment}(quantity);
    } else {
        nft.mint{value: payment}(quantity);
        assertEq(nft.totalSupply(), quantity);
    }

    }
    function totalSupply_after(uint256 quantity) internal view returns (uint256) {
    return nft.totalSupply() + quantity;
}
}
