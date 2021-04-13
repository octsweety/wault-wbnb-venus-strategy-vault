//SPDX-License-Identifier: Unlicense
pragma solidity >0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IUniswapRouter.sol";
import "./interfaces/IVenusComptroller.sol";
import "./interfaces/IVToken.sol";
import "./interfaces/IVBNB.sol";

interface IWBNB is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

contract WaultWbnbVenusStrategy is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    bool public wantIsWBNB = false;
    address public constant wantAddress = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c); // WBNB
    address public constant vTokenAddress = address(0xA07c5b74C9B40447a954e1466938b865b6BBea36);
    address[] public venusMarkets;
    address public uniRouterAddress = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    // address public uniRouterAddress = address(0xfD36E2c2a6789Db23113685031d7F16329158384);

    address public constant wbnbAddress = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address public constant venusAddress = address(0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63);
    address public constant venusDistributionAddress = address(0xfD36E2c2a6789Db23113685031d7F16329158384);

    address public vault;
    address public govAddress = address(0xC627D743B1BfF30f853AE218396e6d47a4f34ceA);
    address constant public rewards  = address(0xC627D743B1BfF30f853AE218396e6d47a4f34ceA);
    address constant public treasury = address(0xC627D743B1BfF30f853AE218396e6d47a4f34ceA);

    uint256 public sharesTotal = 0;
    uint256 public lastEarnBlock = 0;

    uint256 public entranceFeeFactor = 9990; // < 0.1% entrance fee - goes to pool + prevents front-running
    uint256 public constant entranceFeeFactorMax = 10000;
    uint256 public constant entranceFeeFactorLL = 9950; // 0.5% is the max entrance fee settable. LL = lowerlimit
    uint256 public slippageFactor = 950; // 5% default slippage tolerance
    uint256 public deleverAmtFactorMax = 50; // 0.5% is the max amt to delever for deleverageOnce()
    uint256 public deleverAmtFactorSafe = 20; // 0.2% is the safe amt to delever for deleverageOnce()

    address[] public venusToWantPath;

    uint256 public performanceFee = 300;
    uint256 public treasuryReward = 50;
    uint256 public withdrawalFee = 0;
    uint256 public harvesterReward = 50;
    uint256 public constant FEE_DENOMINATOR = 10000;

    /**
     * @dev Variables that can be changed to config profitability and risk:
     * {borrowRate}          - What % of our collateral do we borrow per leverage level.
     * {borrowDepth}         - How many levels of leverage do we take.
     * {BORROW_RATE_MAX}     - A limit on how much we can push borrow risk.
     * {BORROW_DEPTH_MAX}    - A limit on how many steps we can leverage.
     */
    uint256 public borrowRate = 585;
    uint256 public borrowDepth = 3;
    uint256 public constant BORROW_RATE_MAX = 595;
    uint256 public constant BORROW_RATE_MAX_HARD = 599;
    uint256 public constant BORROW_DEPTH_MAX = 6;
    bool onlyGov = false;

    uint256 public supplyBal = 0; // Cached want supplied to venus
    uint256 public borrowBal = 0; // Cached want borrowed from venus
    uint256 public supplyBalTargeted = 0; // Cached targetted want supplied to venus to achieve desired leverage
    uint256 public supplyBalMin = 0;
    /**
     * @dev Events that the contract emits
     */
    event StratRebalance(uint256 _borrowRate, uint256 _borrowDepth);

    modifier onlyAllowGov() {
        require(msg.sender == govAddress, "!gov");
        _;
    }

    constructor(
        address _vault
    ) {
        vault = _vault;

        if (wantAddress == wbnbAddress) {
            wantIsWBNB = true;
            venusToWantPath = [venusAddress, wbnbAddress];
        } else {
            venusToWantPath = [venusAddress, wbnbAddress, wantAddress];
        }

        venusMarkets = [vTokenAddress];

        // transferOwnership(vault);

        _resetAllowances();

        IVenusComptroller(venusDistributionAddress).enterMarkets(venusMarkets);
    }

    function _supply(uint256 _amount) internal {
        if (wantIsWBNB) {
            IVBNB(vTokenAddress).mint{value: _amount}();
        } else {
            IVToken(vTokenAddress).mint(_amount);
        }
    }

    function _removeSupply(uint256 _amount) internal {
        IVToken(vTokenAddress).redeemUnderlying(_amount);
    }

    function _borrow(uint256 _amount) internal {
        IVToken(vTokenAddress).borrow(_amount);
    }

    function _repayBorrow(uint256 _amount) internal {
        if (wantIsWBNB) {
            IVBNB(vTokenAddress).repayBorrow{value: _amount}();
        } else {
            IVToken(vTokenAddress).repayBorrow(_amount);
        }
    }

    function deposit()
        public
        whenNotPaused
        returns (uint256)
    {
        uint256 _wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (_wantAmt == 0) return 0;

        updateBalance();

        uint256 sharesAdded = _wantAmt;
        if (balanceOf() > 0 && sharesTotal > 0) {
            sharesAdded = _wantAmt
                .mul(sharesTotal)
                .mul(entranceFeeFactor)
                .div(balanceOf())
                .div(entranceFeeFactorMax);
        }

        sharesTotal = sharesTotal.add(sharesAdded);

        _farm(true);

        return sharesAdded;
    }

    function farm(bool _withLev) public nonReentrant {
        _farm(_withLev);
    }

    function _farm(bool _withLev) internal {
        if (wantIsWBNB) {
            _unwrapBNB(); // WBNB -> BNB. Venus accepts BNB, not WBNB.
        }

        _leverage(_withLev);

        updateBalance();

        deleverageUntilNotOverLevered(); // It is possible to still be over-levered after depositing.
    }

    /**
     * @dev Repeatedly supplies and borrows bnb following the configured {borrowRate} and {borrowDepth}
     * into the vToken contract.
     */
    function _leverage(bool _withLev) internal {
        if (_withLev) {
            for (uint256 i = 0; i < borrowDepth; i++) {
                uint256 amount = venusWantBal();
                _supply(amount);
                amount = amount.mul(borrowRate).div(1000);
                _borrow(amount);
            }
        }

        _supply(venusWantBal()); // Supply remaining want that was last borrowed.
    }

    function leverageOnce() public onlyAllowGov {
        _leverageOnce();
    }

    function _leverageOnce() internal {
        updateBalance(); // Updates borrowBal & supplyBal & supplyBalTargeted & supplyBalMin
        uint256 borrowAmt = supplyBal.mul(borrowRate).div(1000).sub(borrowBal);
        if (borrowAmt > 0) {
            _borrow(borrowAmt);
            _supply(venusWantBal());
        }
        updateBalance(); // Updates borrowBal & supplyBal & supplyBalTargeted & supplyBalMin
    }

    /**
     * @dev Redeem to the desired leverage amount, then use it to repay borrow.
     * If already over leverage, redeem max amt redeemable, then use it to repay borrow.
     */
    function deleverageOnce() public onlyAllowGov {
        _deleverageOnce();
    }

    function _deleverageOnce() internal {
        updateBalance(); // Updates borrowBal & supplyBal & supplyBalTargeted & supplyBalMin

        if (supplyBal <= 0) {
            return;
        }

        uint256 deleverAmt;
        uint256 deleverAmtMax = supplyBal.mul(deleverAmtFactorMax).div(10000); // 0.5%

        if (supplyBal <= supplyBalMin) {
            // If very over levered, delever 0.2% at a time
            deleverAmt = supplyBal.mul(deleverAmtFactorSafe).div(10000);
        } else if (supplyBal <= supplyBalTargeted) {
            deleverAmt = supplyBal.sub(supplyBalMin);
        } else {
            deleverAmt = supplyBal.sub(supplyBalTargeted);
        }

        if (deleverAmt > deleverAmtMax) {
            deleverAmt = deleverAmtMax;
        }

        _removeSupply(deleverAmt);

        if (wantIsWBNB) {
            _unwrapBNB(); // WBNB -> BNB
            _repayBorrow(address(this).balance);
        } else {
            _repayBorrow(balanceOfWant());
        }

        updateBalance(); // Updates borrowBal & supplyBal & supplyBalTargeted & supplyBalMin
    }

    /**
     * @dev Redeem the max possible, use it to repay borrow
     */
    function deleverageUntilNotOverLevered() public {
        // updateBalance(); // To be more accurate, call updateBalance() first to cater for changes due to interest rates

        // If borrowRate slips below targetted borrowRate, withdraw the max amt first.
        // Further actual deleveraging will take place later on.
        // (This can happen in when net interest rate < 0, and supplied balance falls below targeted.)
        while (supplyBal > 0 && supplyBal <= supplyBalTargeted) {
            _deleverageOnce();
        }
    }

    /**
     * @dev Incrementally alternates between paying part of the debt and withdrawing part of the supplied
     * collateral. Continues to do this untill all want tokens is withdrawn. For partial deleveraging,
     * this continues until at least _minAmt of want tokens is reached.
     */

    function _deleverage(uint256 _minAmt) internal {
        updateBalance(); // Updates borrowBal & supplyBal & supplyBalTargeted & supplyBalMin

        deleverageUntilNotOverLevered();

        if (wantIsWBNB) {
            _wrapBNB(); // WBNB -> BNB
        }

        uint256 supplyRemovableMax = supplyBal.sub(supplyBalMin);
        if (_minAmt < supplyRemovableMax) {
            // If _minAmt to deleverage is less than supplyRemovableMax, just remove _minAmt
            supplyRemovableMax = _minAmt;
        }
        _removeSupply(supplyRemovableMax);

        uint256 wantBal = balanceOfWant();

        // Recursively repay borrowed + remove more from supplied
        while (wantBal < borrowBal) {
            // If only partially deleveraging, when sufficiently deleveraged, do not repay anymore
            if (wantBal >= _minAmt) {
                return;
            }

            _repayBorrow(wantBal);

            updateBalance(); // Updates borrowBal & supplyBal & supplyBalTargeted & supplyBalMin

            supplyRemovableMax = supplyBal.sub(supplyBalMin);
            if (_minAmt < supplyRemovableMax) {
                // If _minAmt to deleverage is less than supplyRemovableMax, just remove _minAmt
                supplyRemovableMax = _minAmt;
            }
            _removeSupply(supplyRemovableMax);

            wantBal = balanceOfWant();
        }

        // When sufficiently deleveraged, do not repay
        if (wantBal >= _minAmt) {
            return;
        }

        // Make a final repayment of borrowed
        _repayBorrow(borrowBal);

        // remove all supplied
        uint256 vTokenBal = IERC20(vTokenAddress).balanceOf(address(this));
        IVToken(vTokenAddress).redeem(vTokenBal);
    }

    /**
     * @dev Updates the risk profile and rebalances the vault funds accordingly.
     * @param _borrowRate percent to borrow on each leverage level.
     * @param _borrowDepth how many levels to leverage the funds.
     */
    function rebalance(uint256 _borrowRate, uint256 _borrowDepth) external {
        require(msg.sender == govAddress, "Not authorised");

        require(_borrowRate <= BORROW_RATE_MAX, "!rate");
        require(_borrowDepth <= BORROW_DEPTH_MAX, "!depth");

        borrowRate = _borrowRate;
        borrowDepth = _borrowDepth;

        updateBalance(); // Updates borrowBal & supplyBal & supplyBalTargeted & supplyBalMin
        deleverageUntilNotOverLevered();
    }

    function harvest() external whenNotPaused {
        if (onlyGov) {
            require(msg.sender == govAddress, "Not authorised");
        }

        IVenusComptroller(venusDistributionAddress).claimVenus(address(this));

        uint256 earnedAmt = IERC20(venusAddress).balanceOf(address(this));

        if (earnedAmt == 0) return;

        distributeFees(earnedAmt);

        earnedAmt = IERC20(venusAddress).balanceOf(address(this));

        // IUniswapRouter(uniRouterAddress).swapExactTokensForTokens(
        //     earnedAmt,
        //     0,
        //     venusToWantPath,
        //     address(this),
        //     block.timestamp.add(600)
        // );
        _safeSwap(
            uniRouterAddress,
            earnedAmt,
            slippageFactor,
            venusToWantPath,
            address(this),
            block.timestamp.add(600)
        );

        lastEarnBlock = block.number;

        _farm(false); // Supply wantToken without leverage, to cater for net -ve interest rates.
    }

    function distributeFees(uint256 _earnedAmt) internal {
        if (_earnedAmt == 0) return;

        uint256 _fee = _earnedAmt.mul(performanceFee).div(FEE_DENOMINATOR);
        uint256 _reward = _earnedAmt.mul(treasuryReward).div(FEE_DENOMINATOR);
        uint256 _harvesterReward = _earnedAmt.mul(harvesterReward).div(FEE_DENOMINATOR);
        IERC20(venusAddress).safeTransfer(rewards, _fee);
        IERC20(venusAddress).safeTransfer(treasury, _reward);
        IERC20(venusAddress).safeTransfer(msg.sender, _harvesterReward);
    }

    function withdraw(uint256 _wantAmt)
        external
        returns (uint256)
    {
        require(msg.sender == vault, "!vault");
        uint256 sharesRemoved =
            _wantAmt.mul(sharesTotal).div(balanceOf());
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        sharesTotal = sharesTotal.sub(sharesRemoved);

        uint256 wantBal = IERC20(wantAddress).balanceOf(address(this));
        if (wantBal < _wantAmt) {
            _deleverage(_wantAmt.sub(wantBal));
            if (wantIsWBNB) {
                _wrapBNB(); // wrap BNB -> WBNB before sending it back to user
            }
            wantBal = IERC20(wantAddress).balanceOf(address(this));
        }

        if (wantBal < _wantAmt) {
            _wantAmt = wantBal;
        }

        if (tx.origin == owner()) {
            IERC20(wantAddress).safeTransfer(vault, _wantAmt);
        } else {
            uint256 fee = _wantAmt.mul(withdrawalFee).div(FEE_DENOMINATOR);
            IERC20(wantAddress).safeTransfer(vault, _wantAmt.sub(fee));
            if (fee > 0) IERC20(wantAddress).safeTransfer(rewards, fee);
        }

        _farm(true);

        return sharesRemoved;
    }

    function _withdrawAll() internal {
        uint256 _wantAmt = sharesTotal;
        sharesTotal = 0;

        uint256 wantBal = IERC20(wantAddress).balanceOf(address(this));
        if (wantBal < _wantAmt) {
            _deleverage(_wantAmt.sub(wantBal));
            if (wantIsWBNB) {
                _wrapBNB(); // wrap BNB -> WBNB before sending it back to user
            }
        }
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public {
        require(msg.sender == govAddress, "Not authorised");

        _pause();

        IERC20(venusAddress).safeApprove(uniRouterAddress, 0);
        IERC20(wantAddress).safeApprove(uniRouterAddress, 0);
        if (!wantIsWBNB) {
            IERC20(wantAddress).safeApprove(vTokenAddress, 0);
        }
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external {
        require(msg.sender == govAddress, "Not authorised");
        _unpause();

        IERC20(venusAddress).safeApprove(uniRouterAddress, uint256(-1));
        IERC20(wantAddress).safeApprove(uniRouterAddress, uint256(-1));
        if (!wantIsWBNB) {
            IERC20(wantAddress).safeApprove(vTokenAddress, 0);
        }
    }

    function _resetAllowances() internal {
        IERC20(venusAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(venusAddress).safeIncreaseAllowance(
            uniRouterAddress,
            uint256(-1)
        );

        IERC20(wantAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            uniRouterAddress,
            uint256(-1)
        );

        if (!wantIsWBNB) {
            IERC20(wantAddress).safeApprove(vTokenAddress, uint256(0));
            IERC20(wantAddress).safeIncreaseAllowance(
                vTokenAddress,
                uint256(-1)
            );
        }
    }

    function resetAllowances() public {
        require(msg.sender == govAddress, "Not authorised");
        _resetAllowances();
    }

    /**
     * @dev Updates want locked in Venus after interest is accrued to this very block.
     * To be called before sensitive operations.
     */
    function updateBalance() public {
        supplyBal = IVToken(vTokenAddress).balanceOfUnderlying(address(this)); // a payable function because of acrueInterest()
        borrowBal = IVToken(vTokenAddress).borrowBalanceCurrent(address(this));
        supplyBalTargeted = borrowBal.mul(1000).div(borrowRate);
        supplyBalMin = borrowBal.mul(1000).div(BORROW_RATE_MAX_HARD);
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(supplyBal).sub(borrowBal);
    }

    function balanceOfWant() public view returns (uint256) {
        uint256 wantBal = IERC20(wantAddress).balanceOf(address(this));
        if (wantIsWBNB) {
            uint256 bnbBal = address(this).balance;
            return bnbBal.add(wantBal);
        } else {
            return wantBal;
        }
    }

    /**
     * @dev Returns balance of want. If wantAddress is WBNB, returns BNB balance, not WBNB balance.
     */
    function venusWantBal() public view returns (uint256) {
        if (wantIsWBNB) {
            return address(this).balance;
        }
        return IERC20(wantAddress).balanceOf(address(this));
    }

    function setEntranceFeeFactor(uint256 _entranceFeeFactor) public {
        require(msg.sender == govAddress, "Not authorised");
        require(_entranceFeeFactor > entranceFeeFactorLL, "!safe - too low");
        require(_entranceFeeFactor <= entranceFeeFactorMax, "!safe - too high");
        entranceFeeFactor = _entranceFeeFactor;
    }

    function setGov(address _govAddress) public {
        require(msg.sender == govAddress, "Not authorised");
        govAddress = _govAddress;
    }

    function setOnlyGov(bool _onlyGov) public {
        require(msg.sender == govAddress, "Not authorised");
        onlyGov = _onlyGov;
    }

    function setUniRouterAddress(address _uniRouterAddress)
        public
    {
        require(msg.sender == govAddress, "Not authorised");
        uniRouterAddress = _uniRouterAddress;
        _resetAllowances();
    }

    function setWithdrawalFee(uint256 _withdrawalFee) external {
        require(msg.sender == govAddress, "Not authorised");
        withdrawalFee = _withdrawalFee;
    }

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) public {
        require(msg.sender == govAddress, "!gov");
        require(_token != venusAddress, "!safe");
        require(_token != wantAddress, "!safe");
        require(_token != vTokenAddress, "!safe");

        IERC20(_token).safeTransfer(_to, _amount);
    }

    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        _withdrawAll();
        uint256 wantBal = IERC20(wantAddress).balanceOf(address(this));

        IERC20(wantAddress).safeTransfer(vault, wantBal);
    }

    function _wrapBNB() internal {
        // BNB -> WBNB
        uint256 bnbBal = address(this).balance;
        if (bnbBal > 0) {
            IWBNB(wbnbAddress).deposit{value: bnbBal}(); // BNB -> WBNB
        }
    }

    function _unwrapBNB() internal {
        // WBNB -> BNB
        uint256 wbnbBal = IERC20(wbnbAddress).balanceOf(address(this));
        if (wbnbBal > 0) {
            IWBNB(wbnbAddress).withdraw(wbnbBal);
        }
    }

    /**
     * @dev We should not have significant amts of BNB in this contract if any at all.
     * In case we do (eg. Venus returns all users' BNB to this contract or for any other reason),
     * We can wrap all BNB, allowing users to withdraw() as per normal.
     */
    function wrapBNB() public {
        require(msg.sender == govAddress, "Not authorised");
        require(wantIsWBNB, "!wantIsWBNB");
        _wrapBNB();
    }

    function _safeSwap(
        address _uniRouterAddress,
        uint256 _amountIn,
        uint256 _slippageFactor,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) internal {
        uint256[] memory amounts =
            IUniswapRouter(_uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        IUniswapRouter(_uniRouterAddress).swapExactTokensForTokens(
            _amountIn,
            amountOut.mul(_slippageFactor).div(1000),
            _path,
            _to,
            _deadline
        );
    }

    receive() external payable {}
}