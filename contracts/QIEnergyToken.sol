// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract QIEnergyToken is ERC20, ERC20Burnable, Ownable {
    uint256 public constant MAX_SUPPLY = 333_333_333 * 10**18; // 333.333M tokens
    uint256 public constant INITIAL_SUPPLY = 33_333_333 * 10**18; // 33.333M initial
    
    mapping(address => bool) public authorized;
    bool public tradingEnabled = false;
    
    event TradingEnabled();
    event AuthorizedAdded(address indexed account);
    
    constructor() ERC20("QI Energy", "QI") Ownable(msg.sender) {
        _mint(msg.sender, INITIAL_SUPPLY);
        authorized[msg.sender] = true;
    }
    
    function mint(address to, uint256 amount) public onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply exceeded");
        _mint(to, amount);
    }
    
    function enableTrading() public onlyOwner {
        tradingEnabled = true;
        emit TradingEnabled();
    }
    
    function addAuthorized(address account) public onlyOwner {
        authorized[account] = true;
        emit AuthorizedAdded(account);
    }
    
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._update(from, to, amount);
        
        if (from != address(0) && to != address(0)) {
            require(
                tradingEnabled || authorized[from] || authorized[to],
                "Trading not enabled"
            );
        }
    }
}