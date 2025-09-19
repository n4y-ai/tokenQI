// SPDX-License-Identifier: MIT


pragma solidity ^0.8.19;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// File: contracts/interfaces/AggregatorV3Interface.sol


pragma solidity ^0.8.19;

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

// File: contracts/QIPresale.sol


pragma solidity ^0.8.19;



/**
 * @title QI Energy Presale Contract
 * @dev Presale contract for QI Energy token with multiple currency support
 * @notice Target: $200M USD through sale of 20M QI tokens at $10 each
 */
contract QIPresale {
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
    uint256 public totalQISold;
    uint256 public totalUSDRaised;
    
    // === SUPPORTED TOKENS ===
    struct TokenInfo {
        address tokenAddress;
        AggregatorV3Interface priceFeed;
        uint8 decimals;
        bool enabled;
    }
    
    mapping(string => TokenInfo) public supportedTokens;
    string[] public tokenSymbols;
    
    // === EVENTS ===
    event QIPurchased(
        address indexed buyer,
        string paymentToken,
        uint256 paymentAmount,
        uint256 qiAmount,
        uint256 usdValue
    );
    event PresaleStatusChanged(bool active);
    event TokenAdded(string symbol, address tokenAddress, address priceFeed);
    event EmergencyWithdraw(address token, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
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
        _;
    }
    
    modifier validPurchase(uint256 qiAmount) {
        require(qiAmount > 0, "QI amount must be > 0");
        require(totalQISold + qiAmount <= PRESALE_TARGET, "Exceeds presale target");
        require(
            (qiAmount * QI_PRICE_USD) / 10**18 >= MIN_PURCHASE_USD,
            "Below minimum purchase"
        );
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
        presaleActive = true;
        
        // Initialize supported tokens on Base mainnet
        _addToken("ETH", address(0), 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70, 18);
        _addToken("USDT", 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2, address(0), 6);
        _addToken("USDC", 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, address(0), 6);
        _addToken("WBTC", 0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b, 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F, 8);
    }
    
    /**
     * @dev Add supported token
     */
    function _addToken(
        string memory symbol,
        address tokenAddress,
        address priceFeedAddress,
        uint8 decimals
    ) internal {
        supportedTokens[symbol] = TokenInfo({
            tokenAddress: tokenAddress,
            priceFeed: priceFeedAddress != address(0) ? AggregatorV3Interface(priceFeedAddress) : AggregatorV3Interface(address(0)),
            decimals: decimals,
            enabled: true
        });
        tokenSymbols.push(symbol);
        
        emit TokenAdded(symbol, tokenAddress, priceFeedAddress);
    }
    
    /**
     * @dev Purchase QI with ETH
     */
    function buyWithETH() external payable presaleIsActive nonReentrant {
        require(msg.value > 0, "ETH amount must be > 0");
        
        uint256 qiAmount = calculateQIAmount("ETH", msg.value);
        require(qiAmount > 0, "Invalid QI amount");
        
        _processPurchase(msg.sender, "ETH", msg.value, qiAmount);
        
        // Transfer ETH to owner
        (bool success, ) = payable(owner).call{value: msg.value}("");
        require(success, "ETH transfer failed");
    }
    
    /**
     * @dev Purchase QI with USDT
     */
    function buyWithUSDT(uint256 usdtAmount) external presaleIsActive nonReentrant {
        require(usdtAmount > 0, "USDT amount must be > 0");
        
        uint256 qiAmount = calculateQIAmount("USDT", usdtAmount);
        require(qiAmount > 0, "Invalid QI amount");
        
        _processPurchase(msg.sender, "USDT", usdtAmount, qiAmount);
        
        // Transfer USDT from buyer to owner
        IERC20 usdt = IERC20(supportedTokens["USDT"].tokenAddress);
        require(
            usdt.transferFrom(msg.sender, owner, usdtAmount),
            "USDT transfer failed"
        );
    }
    
    /**
     * @dev Purchase QI with USDC
     */
    function buyWithUSDC(uint256 usdcAmount) external presaleIsActive nonReentrant {
        require(usdcAmount > 0, "USDC amount must be > 0");
        
        uint256 qiAmount = calculateQIAmount("USDC", usdcAmount);
        require(qiAmount > 0, "Invalid QI amount");
        
        _processPurchase(msg.sender, "USDC", usdcAmount, qiAmount);
        
        // Transfer USDC from buyer to owner
        IERC20 usdc = IERC20(supportedTokens["USDC"].tokenAddress);
        require(
            usdc.transferFrom(msg.sender, owner, usdcAmount),
            "USDC transfer failed"
        );
    }
    
    /**
     * @dev Purchase QI with WBTC
     */
    function buyWithWBTC(uint256 wbtcAmount) external presaleIsActive nonReentrant {
        require(wbtcAmount > 0, "WBTC amount must be > 0");
        
        uint256 qiAmount = calculateQIAmount("WBTC", wbtcAmount);
        require(qiAmount > 0, "Invalid QI amount");
        
        _processPurchase(msg.sender, "WBTC", wbtcAmount, qiAmount);
        
        // Transfer WBTC from buyer to owner
        IERC20 wbtc = IERC20(supportedTokens["WBTC"].tokenAddress);
        require(
            wbtc.transferFrom(msg.sender, owner, wbtcAmount),
            "WBTC transfer failed"
        );
    }
    
    /**
     * @dev Universal purchase function
     */
    function buyWithToken(string memory tokenSymbol, uint256 amount) external payable presaleIsActive nonReentrant {
        TokenInfo memory token = supportedTokens[tokenSymbol];
        require(token.enabled, "Token not supported");
        
        if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("ETH"))) {
            require(msg.value == amount, "ETH amount mismatch");
            require(msg.value > 0, "ETH amount must be > 0");
            
            uint256 qiAmount = calculateQIAmount("ETH", msg.value);
            require(qiAmount > 0, "Invalid QI amount");
            
            _processPurchase(msg.sender, "ETH", msg.value, qiAmount);
            
            // Transfer ETH to owner
            (bool success, ) = payable(owner).call{value: msg.value}("");
            require(success, "ETH transfer failed");
        } else if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("USDT"))) {
            require(amount > 0, "USDT amount must be > 0");
            
            uint256 qiAmount = calculateQIAmount("USDT", amount);
            require(qiAmount > 0, "Invalid QI amount");
            
            _processPurchase(msg.sender, "USDT", amount, qiAmount);
            
            // Transfer USDT from buyer to owner
            IERC20 usdt = IERC20(supportedTokens["USDT"].tokenAddress);
            require(
                usdt.transferFrom(msg.sender, owner, amount),
                "USDT transfer failed"
            );
        } else if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("USDC"))) {
            require(amount > 0, "USDC amount must be > 0");
            
            uint256 qiAmount = calculateQIAmount("USDC", amount);
            require(qiAmount > 0, "Invalid QI amount");
            
            _processPurchase(msg.sender, "USDC", amount, qiAmount);
            
            // Transfer USDC from buyer to owner
            IERC20 usdc = IERC20(supportedTokens["USDC"].tokenAddress);
            require(
                usdc.transferFrom(msg.sender, owner, amount),
                "USDC transfer failed"
            );
        } else if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("WBTC"))) {
            require(amount > 0, "WBTC amount must be > 0");
            
            uint256 qiAmount = calculateQIAmount("WBTC", amount);
            require(qiAmount > 0, "Invalid QI amount");
            
            _processPurchase(msg.sender, "WBTC", amount, qiAmount);
            
            // Transfer WBTC from buyer to owner
            IERC20 wbtc = IERC20(supportedTokens["WBTC"].tokenAddress);
            require(
                wbtc.transferFrom(msg.sender, owner, amount),
                "WBTC transfer failed"
            );
        } else {
            revert("Token not implemented");
        }
    }
    
    /**
     * @dev Process purchase
     */
    function _processPurchase(
        address buyer,
        string memory paymentToken,
        uint256 paymentAmount,
        uint256 qiAmount
    ) internal validPurchase(qiAmount) {
        // Calculate USD value
        uint256 usdValue = (qiAmount * QI_PRICE_USD) / 10**18;
        
        // Update statistics
        totalQISold += qiAmount;
        totalUSDRaised += usdValue;
        
        // Transfer QI tokens to buyer
        IERC20 qi = IERC20(qiToken);
        require(qi.transferFrom(owner, buyer, qiAmount), "QI transfer failed");
        
        emit QIPurchased(buyer, paymentToken, paymentAmount, qiAmount, usdValue);
    }
    
    /**
     * @dev Calculate QI token amount for given payment amount
     */
    function calculateQIAmount(string memory tokenSymbol, uint256 amount) 
        public 
        view 
        returns (uint256) 
    {
        TokenInfo memory token = supportedTokens[tokenSymbol];
        require(token.enabled, "Token not supported");
        
        uint256 usdValue;
        
        if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("USDT")) || 
            keccak256(bytes(tokenSymbol)) == keccak256(bytes("USDC"))) {
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
     * @dev Get current prices of all supported tokens
     */
    function getCurrentPrices() external view returns (uint256[] memory prices, string[] memory symbols) {
        prices = new uint256[](tokenSymbols.length);
        symbols = new string[](tokenSymbols.length);
        
        for (uint256 i = 0; i < tokenSymbols.length; i++) {
            symbols[i] = tokenSymbols[i];
            TokenInfo memory token = supportedTokens[tokenSymbols[i]];
            
            if (keccak256(bytes(tokenSymbols[i])) == keccak256(bytes("USDT")) || 
                keccak256(bytes(tokenSymbols[i])) == keccak256(bytes("USDC"))) {
                prices[i] = 1 * USD_PRECISION; // $1.00
            } else if (address(token.priceFeed) != address(0)) {
                (, int256 price, , , ) = token.priceFeed.latestRoundData();
                prices[i] = price > 0 ? uint256(price) : 0;
            } else {
                prices[i] = 0;
            }
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
        uint256 remaining
    ) {
        return (
            totalQISold,
            totalUSDRaised,
            PRESALE_TARGET,
            presaleActive,
            PRESALE_TARGET - totalQISold
        );
    }
    
    /**
     * @dev Get information about supported tokens
     */
    function getSupportedTokens() external view returns (
        string[] memory symbols,
        address[] memory addresses,
        bool[] memory enabled
    ) {
        symbols = tokenSymbols;
        addresses = new address[](tokenSymbols.length);
        enabled = new bool[](tokenSymbols.length);
        
        for (uint256 i = 0; i < tokenSymbols.length; i++) {
            TokenInfo memory token = supportedTokens[tokenSymbols[i]];
            addresses[i] = token.tokenAddress;
            enabled[i] = token.enabled;
        }
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
     * @dev Get contract balance
     */
    function getContractBalance(address token) external view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }
    
    // === FALLBACK ===
    receive() external payable nonReentrant {
        if (msg.value > 0 && presaleActive) {
            uint256 qiAmount = calculateQIAmount("ETH", msg.value);
            require(qiAmount > 0, "Invalid QI amount");
            
            _processPurchase(msg.sender, "ETH", msg.value, qiAmount);
            
            // Transfer ETH to owner
            (bool success, ) = payable(owner).call{value: msg.value}("");
            require(success, "ETH transfer failed");
        }
    }
}
