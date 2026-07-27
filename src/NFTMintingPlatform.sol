// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721A} from "ERC721A/ERC721A.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NFTMintingPlatform is ERC721A, Ownable, ERC2981, ReentrancyGuard {
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant MINT_PRICE = 0.01 ether;
    bytes32 public merkleRoot;
    bool public allowListMintActive;
    string private baseTokenURI;
    string private unrevealedURI;
    bool public revealed;


    error ExceedMaxSupply( );
    error InsufficientFunds( );
    error NotOnAllowList( );
    error AllowListNotActive();
  

    constructor() ERC721A("MyNFTCollection", "MNFT") Ownable(msg.sender){
        _setDefaultRoyalty(msg.sender, 500); // 5% royalty
    }

    function mint(uint256 quantity) external payable nonReentrant{
        if (totalSupply() + quantity > MAX_SUPPLY) revert ExceedMaxSupply();
        if (msg.value < MINT_PRICE * quantity) revert InsufficientFunds();
        _mint(msg.sender, quantity);
    }
    function toggleAllowListMint() onlyOwner external {
        allowListMintActive = !allowListMintActive;
    }
    function setMerkleRoot(bytes32 root) onlyOwner external{
        merkleRoot = root;
    }

    function allowListMint(uint256 quantity, bytes32[]  calldata proof)external nonReentrant payable{
        if (!allowListMintActive) revert AllowListNotActive();
        if (totalSupply() + quantity > MAX_SUPPLY) revert ExceedMaxSupply();
        if (msg.value < MINT_PRICE * quantity) revert InsufficientFunds();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert NotOnAllowList();
        _mint(msg.sender, quantity);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721A, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    function setBaseURI(string calldata uri) external onlyOwner(){
        baseTokenURI = uri;
    }

    function setUnrevealedURI(string calldata uri) external onlyOwner(){
        unrevealedURI = uri;
    }

    function reveal() external onlyOwner(){
        revealed = true;
    }

    function tokenURI(uint256 tokenId)public view override returns(string memory){
        if(!_exists(tokenId)){
            revert URIQueryForNonexistentToken();
        }
        if(revealed){
            return string(abi.encodePacked(baseTokenURI, _toString(tokenId), ".json"));
        }else{
            return unrevealedURI;
        }
        
    }

    function withdraw()external nonReentrant onlyOwner{
        uint256 balance = address(this).balance;
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }

    receive() external payable {}
}