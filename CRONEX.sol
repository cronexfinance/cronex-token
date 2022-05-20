// SPDX-License-Identifier: MIT

pragma solidity =0.8.7;

interface ICRONEXFactory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface ICRONEXRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IERC20 {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

abstract contract ERC20 is IERC20 {
    mapping(address => uint256) public override balanceOf;

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        balanceOf[from] = balanceOf[from] - amount;
        balanceOf[to] = balanceOf[to] + amount;
        emit Transfer(from, to, amount);
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _transferOwnership(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract CRONEXToken is ERC20, Ownable {
    string public constant override name = "CRONEX";
    string public constant override symbol = "CRONEX";
    uint8 public constant override decimals = 18;
    uint256 public override totalSupply = 100_000 * 1e18;
    mapping(address => mapping(address => uint256)) public override allowance;

    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public automatedMarketMakerPairs;

    address[] public path;

    address public marketingWalletAddress;
    ICRONEXRouter public cronexRouter;
    address public cronexPair;
    bool private swapping;

    uint256 public maxBalance = totalSupply / 100; // 1% or 1000 CRONEX Tokens
    uint256 public maxTxAmount = totalSupply / 4 / 100; // 0.25%
    uint256 public marketingTax = 100; // 1%
    uint256 public totalTax = 200;
    uint256 public autoLp = 100; // 1%
    uint256 public swapTokensAtAmount = totalSupply / 1e6;

    event ExcludeFromFees(address indexed account, bool isExcluded);

    constructor(ICRONEXRouter router, address marketingAddress) {
        cronexRouter = router;
        marketingWalletAddress = marketingAddress;
        cronexPair = ICRONEXFactory(router.factory()).createPair(
            address(this),
            router.WETH()
        );

        setAutomatedMarketMakerPair(cronexPair, true);

        address[] memory swapPath = new address[](2);
        swapPath[0] = address(this);
        swapPath[1] = router.WETH();
        setSwapPath(swapPath);

        execludeFromFees(owner(), true);
        execludeFromFees(address(this), true);

        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function setMarketingAddress(address wallet) external onlyOwner {
        marketingWalletAddress = wallet;
    }

    function setSwapPath(address[] memory _path) public onlyOwner {
        path = _path;
    }
    
    function setmarketingTax(uint256 newMarketingTax) public onlyOwner {
        require(newMarketingTax <=  300, "CRONEX: Marketing Tax cannot be above 3% | Format: 100 for 1%"); // marketingTax can only be 3% or below. Cannot be set exorbitantly high.
        marketingTax = newMarketingTax;
        totalTax = marketingTax + autoLP;
    }
    
    function setautoLP(uint256 newautoLP) public onlyOwner {
        require(newautoLP <=  300, "CRONEX: Liquidity Tax cannot be above 3% | Format: 100 for 1%"); // marketingTax can only be 3% or below. Cannot be set exorbitantly high.
        autoLP = newautoLP;
        totalTax = marketingTax + autoLP;
    }

    function setMaxTxAmount(uint256 maxAmount) public onlyOwner {
        require(maxAmount >=  totalSupply / 4 / 100, "CRONEX: Max Transaction cannot be below 0.25%"); // maxTxAmount can only be 0.25% or above. Cannot be set to 0.
        maxTxAmount = maxAmount;
    }
    
    function setMaxBalanceAmount(uint256 maxBalanceAmount) public onlyOwner {
        require(maxBalanceAmount >=  totalSupply / 100, "CRONEX: Max Wallet cannot be below 1%"); // maxBalance can only be 1% or above. Cannot be set to 1%.
        maxBalance = maxBalanceAmount;
    }

    function execludeFromFees(address account, bool excluded) public onlyOwner {
        isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setSwapTokensAtAmount(uint256 amount) external onlyOwner {
        swapTokensAtAmount = amount;
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        public
        onlyOwner
    {
        require(automatedMarketMakerPairs[pair] != value);
        automatedMarketMakerPairs[pair] = value;
    }

    receive() external payable {}

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] = balanceOf[from] - amount;
        totalSupply = totalSupply - amount;
        emit Transfer(from, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        uint256 contractTokenBalance = balanceOf[address(this)];
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;
        if (
            canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != owner() &&
            to != owner()
        ) {
            swapping = true;
            // swapAndSendToFee(contractTokenBalance * marketingTax / totalTax);
            swapAndLiquidity((contractTokenBalance * autoLp) / totalTax);
            swapping = false;
        }

        if (!(swapping || isExcludedFromFees[from] || isExcludedFromFees[to])) {
            require(amount <= maxTxAmount, "ERC20: Over than MaxTxAmount");
            uint256 feeLp = (amount * autoLp) / 10000;
            uint256 marketingFee = (amount * marketingTax) / 10000;
            amount = amount - feeLp - marketingFee;
            super._transfer(from, address(this), feeLp);
            super._transfer(from, marketingWalletAddress, marketingFee);
        }
        super._transfer(from, to, amount);
    }

    function swapAndSendToFee(uint256 amount) private {
        cronexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            marketingWalletAddress,
            block.timestamp
        );
    }

    function swapAndLiquidity(uint256 amount) private {
        uint256 half = amount / 2;
        uint256 otherHalf = amount - half;
        _approve(address(this), address(cronexRouter), half);
        uint256 initialBalance = address(this).balance;
        cronexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            half,
            0,
            path,
            address(this),
            block.timestamp
        );
        uint256 newBalance = address(this).balance - initialBalance;
        _approve(address(this), address(cronexRouter), otherHalf);
        cronexRouter.addLiquidityETH{value: newBalance}(
            address(this),
            otherHalf,
            0,
            0,
            address(0),
            block.timestamp
        );
    }

    function approve(address spender, uint256 amount)
        external
        override
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        allowance[from][msg.sender] = allowance[from][msg.sender] - amount;
        _transfer(from, to, amount);
        return true;
    }
}
