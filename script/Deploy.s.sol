// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {NFTMintingPlatform} from "../src/NFTMintingPlatform.sol";

contract DeployScript is Script {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        NFTMintingPlatform nft = new NFTMintingPlatform();

        vm.stopBroadcast();

        console.log("Deployed NFTMintingPlatform at:", address(nft));
    }
}