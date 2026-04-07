// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract QIEnergyTokenFixed is ERC20, ERC20Burnable, Ownable, Pausable {
    uint256 public constant MAX_SUPPLY = 333_333_333 * 10**18; // 333.333M tokens
    uint256 public constant INITIAL_SUPPLY = 33_333_333 * 10**18; // 33.333M initial
    
    mapping(address => bool) public authorized;
    bool public tradingEnabled = false;
    
    event TradingEnabled();
    event AuthorizedAdded(address indexed account);
    event AuthorizedRemoved(address indexed account);
    event TokensMinted(address indexed to, uint256 amount);
    
    constructor() ERC20("QI Energy", "QI") Ownable(msg.sender) {
        _mint(msg.sender, INITIAL_SUPPLY);
        authorized[msg.sender] = true;
        emit TokensMinted(msg.sender, INITIAL_SUPPLY);
    }
    
    /**
     * @dev Mint new tokens
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyOwner whenNotPaused {
        require(to != address(0), "Mint to zero address");
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply exceeded");
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }
    
    /**
     * @dev Enable trading for all users
     */
    function enableTrading() public onlyOwner {
        require(!tradingEnabled, "Trading already enabled");
        tradingEnabled = true;
        emit TradingEnabled();
    }
    
    /**
     * @dev Add authorized address (can transfer before trading enabled)
     * @param account Address to authorize
     */
    function addAuthorized(address account) public onlyOwner {
        require(account != address(0), "Zero address");
        require(!authorized[account], "Already authorized");
        authorized[account] = true;
        emit AuthorizedAdded(account);
    }
    
    /**
     * @dev Remove authorized address
     * @param account Address to remove authorization
     */
    function removeAuthorized(address account) public onlyOwner {
        require(account != address(0), "Zero address");
        require(authorized[account], "Not authorized");
        require(account != owner(), "Cannot remove owner");
        authorized[account] = false;
        emit AuthorizedRemoved(account);
    }
    
    /**
     * @dev Pause token transfers (emergency)
     */
    function pause() public onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause token transfers
     */
    function unpause() public onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Override _update to add trading restrictions
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._update(from, to, amount);
        
        // Allow minting and burning without restrictions
        if (from != address(0) && to != address(0)) {
            require(
                tradingEnabled || authorized[from] || authorized[to],
                "Trading not enabled"
            );
        }
    }
    
    /**
     * @dev Get token information
     */
    function getTokenInfo() external view returns (
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 totalSupply,
        uint256 maxSupply,
        bool isTradingEnabled,
        bool isPaused
    ) {
        return (
            name(),
            symbol(),
            decimals(),
            totalSupply(),
            MAX_SUPPLY,
            tradingEnabled,
            paused()
        );
    }
}