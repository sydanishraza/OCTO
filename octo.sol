// SPDX-License-Identifier: MIT
/**
Website: https://octo-labs.io/
Twitter: https://twitter.com/LabsOcto
Telegram: https://t.me/LabsOcto
*/
/**
 ██████╗   ██████╗ ████████╗ ██████╗     ██╗      █████╗ ██████╗ ███████╗
██╔══ ██╗ ██╔═══   ╚══██╔══╝██╔═══██╗    ██║     ██╔══██╗██╔══██╗██╔════╝
██║   ██╗ ██║         ██║   ██║   ██║    ██║     ███████║██████╔╝███████╗
██║   ██║ ██║         ██║   ██║   ██║    ██║     ██╔══██║██╔══██╗╚════██║
╚██████╔╝ ╚██████╔    ██║   ╚██████╔╝    ███████╗██║  ██║██████╔╝███████║
 ╚═════╝   ╚═════╝    ╚═╝    ╚═════╝     ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract OCTO is ERC20, ReentrancyGuard, Ownable {
    IUniswapV2Router02 public uniswapRouter;
    IUniswapV2Pair public uniswapPair;
    address public developmentWallet;
    address public preSaleWallet;
    uint256 public constant initialRewardRate = 100 * 1e18;
    uint256 public constant finalRewardRate = 10 * 1e18;
    uint256 public taxRate = 4;
    uint256 public lpTaxRate = 1;

    mapping(address => uint256) public liquidityBalance;
    mapping(address => uint256) public lpTokenBalance;
    mapping(address => uint256) public stakeStartTime;
    mapping(address => uint256) public vestingStart;
    mapping(address => uint256) public vestedAmount;
    mapping(address => uint256) public liquidityMiningRewards;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public liquidityMiningRate = 10 * 1e18;

    address[] public liquidityProviders;
    mapping(address => bool) public isLiquidityProvider;

    event RewardPaid(address indexed user, uint256 reward);
    event LiquidityAdded(address indexed provider, uint256 tokenAmount, uint256 ethAmount);
    event LiquidityRemoved(address indexed provider, uint256 amount);
    event TokensVested(address indexed beneficiary, uint256 amount, uint256 start, uint256 duration);
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event LiquidityMiningRewardPaid(address indexed user, uint256 reward);

    constructor(
        address router,
        address _developmentWallet,
        address _preSaleWallet
    ) ERC20("OCTO Labs", "OCTO") Ownable(msg.sender) {
        developmentWallet = _developmentWallet;
        preSaleWallet = _preSaleWallet;
        uniswapRouter = IUniswapV2Router02(router);

        uint256 totalSupply = 1_000_000 * 1e18; 
        uint256 devWalletSupply = totalSupply * 20 / 100; 
        uint256 preSaleSupply = totalSupply * 20 / 100;
        uint256 ownerSupply = totalSupply - devWalletSupply - preSaleSupply;

        uint256 vestingAmount = (devWalletSupply * 75) / 100;
        uint256 nonVestingAmount = devWalletSupply - vestingAmount;

        _mint(developmentWallet, nonVestingAmount);
        _mint(address(this), vestingAmount);
        _mint(preSaleWallet, preSaleSupply);
        _mint(msg.sender, ownerSupply);

        _vestTokens(developmentWallet, vestingAmount, block.timestamp, 365 days); // 1-year vesting period
    }

    function setUniswapPair(address pair) external onlyOwner {
        uniswapPair = IUniswapV2Pair(pair);
    }

    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            lpTokenBalance[account] = earned(account);
        }
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        return rewardPerTokenStored + ((block.timestamp - lastUpdateTime) * currentRewardRate() * 1e18 / totalSupply());
    }

    function currentRewardRate() public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - stakeStartTime[msg.sender];
        if (timeElapsed < 15 days) {
            return initialRewardRate / 1 days;
        } else if (timeElapsed < 22 days) {
            return (initialRewardRate - 10 * 1e18) / 1 days;
        } else if (timeElapsed < 29 days) {
            return (initialRewardRate - 20 * 1e18) / 1 days;
        } else if (timeElapsed < 36 days) {
            return (initialRewardRate - 30 * 1e18) / 1 days;
        } else if (timeElapsed < 43 days) {
            return (initialRewardRate - 40 * 1e18) / 1 days;
        } else if (timeElapsed < 50 days) {
            return (initialRewardRate - 50 * 1e18) / 1 days;
        } else if (timeElapsed < 57 days) {
            return (initialRewardRate - 60 * 1e18) / 1 days;
        } else if (timeElapsed < 64 days) {
            return (initialRewardRate - 70 * 1e18) / 1 days;
        } else {
            return finalRewardRate / 1 days;
        }
    }

    function earned(address account) public view returns (uint256) {
        return (lpTokenBalance[account] * (rewardPerToken() - rewardPerTokenStored) / 1e18) + lpTokenBalance[account];
    }

    function stake(uint256 amount) external nonReentrant {
        require(address(uniswapPair) != address(0), "Uniswap pair not set");
        if (stakeStartTime[msg.sender] == 0) {
            stakeStartTime[msg.sender] = block.timestamp;
        }
        updateReward(msg.sender);
        uniswapPair.transferFrom(msg.sender, address(this), amount);
        lpTokenBalance[msg.sender] += amount;
        if (!isLiquidityProvider[msg.sender]) {
            liquidityProviders.push(msg.sender);
            isLiquidityProvider[msg.sender] = true;
        }
        emit LiquidityAdded(msg.sender, amount, 0);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(lpTokenBalance[msg.sender] >= amount, "Withdraw amount exceeds balance");
        updateReward(msg.sender);
        lpTokenBalance[msg.sender] -= amount;
        uniswapPair.transfer(msg.sender, amount);
        if (lpTokenBalance[msg.sender] == 0) {
            isLiquidityProvider[msg.sender] = false;
            for (uint256 i = 0; i < liquidityProviders.length; i++) {
                if (liquidityProviders[i] == msg.sender) {
                    liquidityProviders[i] = liquidityProviders[liquidityProviders.length - 1];
                    liquidityProviders.pop();
                    break;
                }
            }
        }
        emit LiquidityRemoved(msg.sender, amount);
    }

    function getReward() external nonReentrant {
        updateReward(msg.sender);
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            lpTokenBalance[msg.sender] = 0;
            super._transfer(address(this), msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function _vestTokens(address beneficiary, uint256 amount, uint256 start, uint256 duration) internal {
        require(beneficiary != address(0), "Beneficiary is zero address");
        require(amount > 0, "Amount is zero");
        require(vestingStart[beneficiary] == 0, "Already vested");

        vestedAmount[beneficiary] = amount;
        vestingStart[beneficiary] = start;

        emit TokensVested(beneficiary, amount, start, duration);
    }

    function vestAdditionalTokens(address beneficiary, uint256 amount, uint256 duration) external onlyOwner {
        require(balanceOf(address(this)) >= amount, "Not enough tokens in contract to vest");
        _vestTokens(beneficiary, amount, block.timestamp, duration);
    }

    function releaseVestedTokens() external {
        uint256 unreleased = releasableAmount(msg.sender);
        require(unreleased > 0, "No tokens to release");

        vestedAmount[msg.sender] -= unreleased;
        _transfer(address(this), msg.sender, unreleased);

        emit TokensReleased(msg.sender, unreleased);
    }

    function releasableAmount(address beneficiary) public view returns (uint256) {
        return vestedAmount[beneficiary] * (block.timestamp - vestingStart[beneficiary]) / 365 days;
    }

    function distributeLiquidityMiningRewards() external onlyOwner {
        require(block.timestamp > lastUpdateTime, "Cannot distribute rewards yet");

        for (uint256 i = 0; i < liquidityProviders.length; i++) {
            address provider = liquidityProviders[i];
            uint256 reward = liquidityMiningRewards[provider];
            if (reward > 0) {
                liquidityMiningRewards[provider] = 0;
                _transfer(address(this), provider, reward);
                emit LiquidityMiningRewardPaid(provider, reward);
            }
        }
        lastUpdateTime = block.timestamp;
    }

    function calculateLiquidityMiningRewards(address provider) public view returns (uint256) {
        uint256 balance = uniswapPair.balanceOf(provider);
        uint256 timeStaked = block.timestamp - stakeStartTime[provider];
        return (balance * timeStaked * liquidityMiningRate) / 1e18;
    }

    function _addLiquidityMiningRewards(address provider) internal {
        uint256 reward = calculateLiquidityMiningRewards(provider);
        if (reward > 0) {
            liquidityMiningRewards[provider] += reward;
        }
    }

    receive() external payable {}

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        uint256 taxAmount;
        uint256 liquidityShare;
        uint256 developmentShare;

        if (isLiquidityProvider[sender]) {
            taxAmount = (amount * lpTaxRate) / 100;
            developmentShare = taxAmount; 
            liquidityShare = 0; 
        } else {
            taxAmount = (amount * taxRate) / 100;
            liquidityShare = (taxAmount * 75) / 100;
            developmentShare = taxAmount - liquidityShare;
        }

        uint256 amountAfterTax = amount - taxAmount;

        if (liquidityShare > 0) {
            super._transfer(sender, address(this), liquidityShare);
            _addLiquidity(liquidityShare); 
        }

        if (developmentShare > 0) {
            super._transfer(sender, developmentWallet, developmentShare);
        }

        super._transfer(sender, recipient, amountAfterTax);

        _addLiquidityMiningRewards(sender);  
        _addLiquidityMiningRewards(recipient); 
    }

    function _addLiquidity(uint256 tokenAmount) private {
        uint256 half = tokenAmount / 2;
        uint256 otherHalf = tokenAmount - half;

        uint256 initialBalance = address(this).balance;

        _approve(address(this), address(uniswapRouter), half);

        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            half,
            0,
            getPathForTokenToETH(),
            address(this),
            block.timestamp
        );

        uint256 newBalance = address(this).balance - initialBalance;

        _approve(address(this), address(uniswapRouter), otherHalf);

        uniswapRouter.addLiquidityETH{value: newBalance}(
            address(this),
            otherHalf,
            0,
            0,
            owner(),
            block.timestamp
        );

        emit LiquidityAdded(address(this), otherHalf, newBalance);
    }

    function getPathForTokenToETH() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapRouter.WETH();
        return path;
    }
}
