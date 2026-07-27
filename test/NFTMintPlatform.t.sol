// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NFTMintingPlatform} from "../src/NFTMintingPlatform.sol";
contract NFTMintingPlatformTest is Test {
    NFTMintingPlatform public nft;

    address public alice = address(0x1);

    function setUp()public{
        nft = new NFTMintingPlatform();
        vm.deal(alice, 10 ether); // give 10 ether to alice to mint the NFT

    }

    function testMintSuccess()public{
        vm.prank(alice);
        nft.mint{value: 0.01 ether}(1);

        assertEq(nft.ownerOf(0), alice);
        assertEq(nft.totalSupply(), 1);
    }

    function test_RevertWhen_InsufficientPayment()public{
        vm.prank(alice);
        vm.expectRevert(NFTMintingPlatform.InsufficientFunds.selector );
        nft.mint{value: 0.001 ether}(1);
    }

    function test_AnyoneCanSetMerkleRoot() public {
        address randomUser = address(0x2);
        bytes32 fakeRoot = keccak256("fake");
        vm.prank(randomUser);
        vm.expectRevert();
        nft.setMerkleRoot(fakeRoot);
       

    
        
    }

    function test_RoyaltyInfo() view public{
        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(0, 5 ether);

        assertEq(receiver, address(this));
        assertEq(royaltyAmount, 0.25 ether);
    }

    function test_TokenURI_BeforeAndAfterReveal()public {
        vm.prank(alice);
        nft.mint{value: 0.01 ether}(1);
        nft.setUnrevealedURI("ipfs://mystery-box.json");
        nft.setBaseURI("ipfs://real-metadata/");
        assertEq(nft.tokenURI(0),"ipfs://mystery-box.json" );
        nft.reveal();
        assertEq(nft.tokenURI(0),"ipfs://real-metadata/0.json");




    }
}
