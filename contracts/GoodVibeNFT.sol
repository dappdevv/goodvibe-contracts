// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract GoodVibeNFT is ERC721, ERC721Enumerable, Ownable, EIP712, ERC721Votes, Pausable {
    address public NFTMinterContract;
    string private _baseTokenURI;
    uint256 public constant SCALE = 1000;

    struct TokenData {
        uint256 id;
        int32 lng; // Используем 32-битный тип для оптимизации
        int32 lat;
        string customMetadata;
    }

    mapping(int32 => mapping(int32 => uint256)) public tokens;
    mapping(uint256 => TokenData) public tokenData;

    event MetadataUpdated(uint256 tokenId);
    event BatchMinted(address to, uint256 count);
    event ContractPaused(bool status);

    constructor(address initialOwner, string memory initialBaseURI)
        ERC721("GoodVibeNFT", "Good Vibe")
        Ownable(initialOwner)
        EIP712("GoodVibeNFT", "1")
    {
        _baseTokenURI = initialBaseURI;
    }

    modifier onlyActive() {
        require(!paused(), "Contract paused");
        _;
    }

    // Добавляем поддержку динамического URI
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    // Оптимизированная функция пакетного минта
    function batchMint(address to, int32[] memory lngs, int32[] memory lats) 
        external 
        onlyNFTMinterContract 
        onlyActive
    {
        require(lngs.length == lats.length, "Array length mismatch");
        
        for(uint256 i = 0; i < lngs.length; i++) {
            _mintSingle(to, lngs[i], lats[i]);
        }
        
        emit BatchMinted(to, lngs.length);
    }

    // Обновленная функция минта с проверкой переполнения
    function mint(address to, int32 lng, int32 lat)
        external
        onlyNFTMinterContract
        onlyActive
    {
        _mintSingle(to, lng, lat);
    }

    function _mintSingle(address to, int32 lng, int32 lat) private {
        require(tokens[lng][lat] == 0, "Token exists");
        
        uint256 tokenId = getTokenId(lng, lat);
        _safeMint(to, tokenId);

        tokens[lng][lat] = tokenId;
        tokenData[tokenId] = TokenData({
            id: tokenId,
            lng: lng,
            lat: lat,
            customMetadata: ""
        });
        
        emit Minted(tokenId, lng, lat);
    }

    // Добавляем кастомные метаданные
    function setTokenMetadata(uint256 tokenId, string memory metadata) external {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        tokenData[tokenId].customMetadata = metadata;
        emit MetadataUpdated(tokenId);
    }

    // Управление контрактом
    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(true);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit ContractPaused(false);
    }

    // Оптимизированные проверки координат
    function getTokenId(int32 lng, int32 lat) public pure returns (uint256) {
        require(lat >= -80 * int32(SCALE) && lat <= 84 * int32(SCALE), "Invalid lat");
        require(lng >= -180 * int32(SCALE) && lng <= 180 * int32(SCALE), "Invalid lng");
        
        return uint256(keccak256(abi.encodePacked(
            uint32(lng + 180 * int32(SCALE)), 
            uint32(lat + 84 * int32(SCALE))
        )));
    }

    // Overrides
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable, ERC721Votes)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable, ERC721Votes)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}