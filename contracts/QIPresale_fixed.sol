// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IERC20.sol";
import "./interfaces/AggregatorV3Interface.sol";

/**
 * @title QI Energy Presale Contract (Fixed Version)
 * @dev Presale contract for QI Energy token with multiple currency support
 * @notice Target: $200M USD through sale of 20M QI tokens at $10 each
 */
contract QIPresaleFixed {
    // === CONSTANTS ===
    uint256 public constant QI_PRICE_USD = 10 * 10**6; // $10.00 per QI (6 decimals)
    uint256 public constant MIN_PURCHASE_USD = 10 * 10**6; // $10 minimum purchase
    uint256 public constant PRESALE_TARGET = 20_000_000 * 10**18; // 20M QI tokens
    uint256 public constant PRICE_FEED_PRECISION = 10**8; // Chainlink precision
    uint256 public constant USD_PRECISION = 10**6; // USD precision (6 decimals)
    
    // === CONTRACT STATE ===
    address public owner;
    address public immutable qiToken;
    bool public presaleActive;
    bool public paused; // Emergency pause
    uint256 public totalQISold;
    uint256 public totalUSDRaised;
    
    // === SUPPORTED TOKENS ===
    enum PaymentToken { ETH, USDT, USDC, WBTC }
    
    struct TokenInfo {
        address tokenAddress;
        AggregatorV3Interface priceFeed;
        uint8 decimals;
        bool enabled;
    }
    
    mapping(PaymentToken => TokenInfo) public supportedTokens;
    mapping(address => uint256) public userPurchases; // Track user purchases
    
    // === EVENTS ===
    event QIPurchased(
        address indexed buyer,
        PaymentToken paymentToken,
        uint256 paymentAmount,
        uint256 qiAmount,
        uint256 usdValue
    );
    event PresaleStatusChanged(bool active);
    event EmergencyPause(bool paused);
    event TokenAdded(PaymentToken token, address tokenAddress, address priceFeed);
    event EmergencyWithdraw(address token, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TokensDeposited(uint256 amount);
    
    // === MODIFIERS ===
    bool private _reentrancyLock;
    
    modifier nonReentrant() {
        require(!_reentrancyLock, "ReentrancyGuard: reentrant call");
        _reentrancyLock = true;
        _;
        _reentrancyLock = false;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier presaleIsActive() {
        require(presaleActive, "Presale not active");
        require(!paused, "Contract is paused");
        _;
    }
    
    modifier validPurchase(uint256 qiAmount) {
        require(qiAmount > 0, "QI amount must be > 0");
        require(totalQISold + qiAmount <= PRESALE_TARGET, "Exceeds presale target");
        require(
            (qiAmount * QI_PRICE_USD) / 10**18 >= MIN_PURCHASE_USD,
            "Below minimum purchase"
        );
        
        // Check contract has enough QI tokens
        uint256 contractBalance = IERC20(qiToken).balanceOf(address(this));
        require(contractBalance >= qiAmount, "Insufficient QI in contract");
        _;
    }
    
    /**
     * @dev Constructor - initialize presale contract
     * @param _qiToken Address of QI Energy token contract
     */
    constructor(address _qiToken) {
        require(_qiToken != address(0), "Invalid QI token address");
        
        owner = msg.sender;
        qiToken = _qiToken;
        presaleActive = false; // Start inactive until tokens are deposited
        paused = false;
        
        // Initialize supported tokens on Base mainnet
        _addToken(PaymentToken.ETH, address(0), 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70, 18);
        _addToken(PaymentToken.USDT, 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2, address(0), 6);
        _addToken(PaymentToken.USDC, 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, address(0), 6);
        _addToken(PaymentToken.WBTC, 0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b, 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F, 8);
    }
    
    /**
     * @dev Deposit QI tokens to the contract for presale
     * @param amount Amount of QI tokens to deposit
     */
    function depositTokens(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        require(
            IERC20(qiToken).transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );
        emit TokensDeposited(amount);
    }
    
    /**
     * @dev Add supported token
     */
    function _addToken(
        PaymentToken token,
        address tokenAddress,
        address priceFeedAddress,
        uint8 decimals
    ) internal {
        supportedTokens[token] = TokenInfo({
            tokenAddress: tokenAddress,
            priceFeed: priceFeedAddress != address(0) ? AggregatorV3Interface(priceFeedAddress) : AggregatorV3Interface(address(0)),
            decimals: decimals,
            enabled: true
        });
        
        emit TokenAdded(token, tokenAddress, priceFeedAddress);
    }
    
    /**
     * @dev Purchase QI with payment token
     */
    function buyWithToken(PaymentToken paymentToken, uint256 amount) 
        external 
        payable 
        presaleIsActive 
        nonReentrant 
    {
        TokenInfo memory token = supportedTokens[paymentToken];
        require(token.enabled, "Token not supported");
        
        if (paymentToken == PaymentToken.ETH) {
            require(msg.value == amount && msg.value > 0, "Invalid ETH amount");
        } else {
            require(amount > 0, "Amount must be > 0");
            require(msg.value == 0, "ETH not required for token payment");
        }
        
        uint256 qiAmount = calculateQIAmount(paymentToken, amount);
        _processPurchase(msg.sender, paymentToken, amount, qiAmount);
        
        // Handle payment
        if (paymentToken == PaymentToken.ETH) {
            (bool success, ) = payable(owner).call{value: msg.value}("");
            require(success, "ETH transfer failed");
        } else {
            require(
                IERC20(token.tokenAddress).transferFrom(msg.sender, owner, amount),
                "Token transfer failed"
            );
        }
    }
    
    /**
     * @dev Process purchase
     */
    function _processPurchase(
        address buyer,
        PaymentToken paymentToken,
        uint256 paymentAmount,
        uint256 qiAmount
    ) internal validPurchase(qiAmount) {
        // Calculate USD value
        uint256 usdValue = (qiAmount * QI_PRICE_USD) / 10**18;
        
        // Update statistics
        totalQISold += qiAmount;
        totalUSDRaised += usdValue;
        userPurchases[buyer] += qiAmount;
        
        // Transfer QI tokens to buyer from contract
        require(IERC20(qiToken).transfer(buyer, qiAmount), "QI transfer failed");
        
        emit QIPurchased(buyer, paymentToken, paymentAmount, qiAmount, usdValue);
    }
    
    /**
     * @dev Calculate QI token amount for given payment amount
     */
    function calculateQIAmount(PaymentToken paymentToken, uint256 amount) 
        public 
        view 
        returns (uint256) 
    {
        TokenInfo memory token = supportedTokens[paymentToken];
        require(token.enabled, "Token not supported");
        
        uint256 usdValue;
        
        if (paymentToken == PaymentToken.USDT || paymentToken == PaymentToken.USDC) {
            // For stablecoins: direct conversion
            usdValue = amount; // USDT/USDC already in USD with 6 decimals
        } else {
            // For other tokens: use price feeds
            require(address(token.priceFeed) != address(0), "Price feed not available");
            
            (, int256 price, , , ) = token.priceFeed.latestRoundData();
            require(price > 0, "Invalid price");
            
            // Convert to USD (accounting for decimals)
            usdValue = (amount * uint256(price) * USD_PRECISION) / 
                      (PRICE_FEED_PRECISION * (10 ** token.decimals));
        }
        
        // Calculate QI amount: usdValue / QI_PRICE_USD * 10^18
        return (usdValue * 10**18) / QI_PRICE_USD;
    }
    
    /**
     * @dev Get current price of a payment token
     */
    function getTokenPrice(PaymentToken paymentToken) external view returns (uint256) {
        TokenInfo memory token = supportedTokens[paymentToken];
        
        if (paymentToken == PaymentToken.USDT || paymentToken == PaymentToken.USDC) {
            return 1 * USD_PRECISION; // $1.00
        } else if (address(token.priceFeed) != address(0)) {
            (, int256 price, , , ) = token.priceFeed.latestRoundData();
            return price > 0 ? uint256(price) : 0;
        } else {
            return 0;
        }
    }
    
    /**
     * @dev Get presale statistics
     */
    function getPresaleStats() external view returns (
        uint256 sold,
        uint256 raised,
        uint256 target,
        bool active,
        uint256 remaining,
        uint256 contractBalance
    ) {
        return (
            totalQISold,
            totalUSDRaised,
            PRESALE_TARGET,
            presaleActive && !paused,
            PRESALE_TARGET - totalQISold,
            IERC20(qiToken).balanceOf(address(this))
        );
    }
    
    // === ADMIN FUNCTIONS ===
    
    /**
     * @dev Change presale status
     */
    function setPresaleStatus(bool _active) external onlyOwner {
        presaleActive = _active;
        emit PresaleStatusChanged(_active);
    }
    
    /**
     * @dev Emergency pause
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit EmergencyPause(_paused);
    }
    
    /**
     * @dev Transfer contract ownership to a new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    /**
     * @dev Emergency withdraw function
     */
    function emergencyWithdraw(address token) external onlyOwner nonReentrant {
        if (token == address(0)) {
            // Withdraw ETH
            uint256 balance = address(this).balance;
            if (balance > 0) {
                (bool success, ) = payable(owner).call{value: balance}("");
                require(success, "ETH withdraw failed");
                emit EmergencyWithdraw(address(0), balance);
            }
        } else {
            // Withdraw ERC20
            IERC20 erc20 = IERC20(token);
            uint256 balance = erc20.balanceOf(address(this));
            if (balance > 0) {
                require(erc20.transfer(owner, balance), "Token withdraw failed");
                emit EmergencyWithdraw(token, balance);
            }
        }
    }
    
    /**
     * @dev Get user purchase amount
     */
    function getUserPurchase(address user) external view returns (uint256) {
        return userPurchases[user];
    }
    
    // Prevent accidental ETH transfers
    receive() external payable {
        revert("Use buyWithToken function");
    }
}