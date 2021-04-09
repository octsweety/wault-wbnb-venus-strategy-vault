//SPDX-License-Identifier: Unlicense
pragma solidity >0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/IUniswapRouter.sol";
import "./interfaces/IVenusComptroller.sol";
import "./interfaces/IVToken.sol";

contract WaultWbnbVenusStrategy is Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    // using Math for uint256;

    address public constant xvs = address(0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63);
    address public constant wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address public constant venusComptroller = address(0xfD36E2c2a6789Db23113685031d7F16329158384);
    address public constant uniswapRouter = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);

    address constant public rewards  = address(0xC627D743B1BfF30f853AE218396e6d47a4f34ceA);
    address constant public treasury = address(0xC627D743B1BfF30f853AE218396e6d47a4f34ceA);
    address public vault;
    address public strategist = address(0xC627D743B1BfF30f853AE218396e6d47a4f34ceA);

    address public constant want = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c); // WBNB
    address public constant vToken = address(0xA07c5b74C9B40447a954e1466938b865b6BBea36);
    address[] public xvsToWantPath = [xvs, wbnb];
    uint256 public targetBorrowLimit = uint256(5900).mul(1e14);
    uint256 public targetBorrowLimitHysteresis = uint256(10).mul(1e14);

    uint256 public performanceFee = 300;
    uint256 public treasuryReward = 50;
    uint256 public withdrawalFee = 0;
    uint256 public harvesterReward = 50;
    uint256 public constant FEE_DENOMINATOR = 10000;

    bool public paused;

    constructor(address _vault) {
        vault = _vault;

        address[] memory _markets = new address[](1);
        _markets[0] = vToken;
        IVenusComptroller(venusComptroller).enterMarkets(_markets);
    }

    function deposit() public {
      uint256 _want = IERC20(want).balanceOf(address(this));
      if (_want > 0) {
        _supplyWant();
        _rebalance(0);
      }
    }

    function _supplyWant() internal {
      if(paused) return;
      uint256 _want = IERC20(want).balanceOf(address(this));
      IERC20(want).safeApprove(vToken, 0);
      IERC20(want).safeApprove(vToken, _want);
      IVToken(vToken).mint(_want);
    }

    function _claimXvs() internal {
      address[] memory _markets = new address[](1);
      _markets[0] = vToken;
      IVenusComptroller(venusComptroller).claimVenus(address(this), _markets);
    }


    function _rebalance(uint withdrawAmount) internal {
      uint256 _ox = IVToken(vToken).balanceOfUnderlying(address(this));
      if(_ox == 0) return;
      if(withdrawAmount >= _ox) withdrawAmount = _ox.sub(1);
      uint256 _x = _ox.sub(withdrawAmount);
      uint256 _y = IVToken(vToken).borrowBalanceCurrent(address(this));
      uint256 _c = collateralFactor();
      uint256 _L = _c.mul(targetBorrowLimit).div(1e18);
      uint256 _currentL = _y.mul(1e18).div(_x);
      uint256 _liquidityAvailable = IVToken(vToken).getCash();

      if(_currentL < _L && _L.sub(_currentL) > targetBorrowLimitHysteresis) {
        uint256 _dy = _L.mul(_x).div(1e18).sub(_y).mul(1e18).div(uint256(1e18).sub(_L));
        uint256 _max_dy = _ox.mul(_c).div(1e18).sub(_y);
        if(_dy > _max_dy) _dy = _max_dy;
        if(_dy > _liquidityAvailable) _dy = _liquidityAvailable;
        IVToken(vToken).borrow(_dy);
        _supplyWant();
      } else {
        while(_currentL > _L && _currentL.sub(_L) > targetBorrowLimitHysteresis) {
          uint256 _dy = _y.sub(_L.mul(_x).div(1e18)).mul(1e18).div(uint256(1e18).sub(_L));
          uint256 _max_dy = _ox.sub(_y.mul(1e18).div(_c));
          if(_dy > _max_dy) _dy = _max_dy;
          if(_dy > _liquidityAvailable) _dy = _liquidityAvailable;
          require(IVToken(vToken).redeemUnderlying(_dy) == 0, "_rebalance: redeem failed");

          _ox = _ox.sub(_dy);
          if(withdrawAmount >= _ox) withdrawAmount = _ox.sub(1);
          _x = _ox.sub(withdrawAmount);

          if(_dy > _y) _dy = _y;
          IERC20(want).safeApprove(vToken, 0);
          IERC20(want).safeApprove(vToken, _dy);
          IVToken(vToken).repayBorrow(_dy);
          _y = _y.sub(_dy);

          _currentL = _y.mul(1e18).div(_x);
          _liquidityAvailable = IVToken(vToken).getCash();
        }
      }
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external {
      require(msg.sender == vault, "!vault");

      uint256 _balance = IERC20(want).balanceOf(address(this));
      if (_balance < _amount) {
          _amount = _withdrawSome(_amount.sub(_balance));
          _amount = _amount.add(_balance);
      }

      uint256 _fee = _amount.mul(withdrawalFee).div(FEE_DENOMINATOR);
      if (_fee > 0) IERC20(want).safeTransfer(rewards, _fee);
      IERC20(want).safeTransfer(vault, _amount.sub(_fee));
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
      _rebalance(_amount);
      uint _balance = IVToken(vToken).balanceOfUnderlying(address(this));
      if(_amount > _balance) _amount = _balance;
      require(IVToken(vToken).redeemUnderlying(_amount) == 0, "_withdrawSome: redeem failed");
      return _amount;
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint256 balance) {
      require(msg.sender == vault, "!vault");
      _withdrawAll();

      balance = IERC20(want).balanceOf(address(this));

      IERC20(want).safeTransfer(vault, balance);
    }

    function _withdrawAll() internal {
      targetBorrowLimit = 0;
      targetBorrowLimitHysteresis = 0;
      _rebalance(0);
      require(IVToken(vToken).redeem(IVToken(vToken).balanceOf(address(this))) == 0, "_withdrawAll: redeem failed");      
    }

    function _convertRewardsToWant() internal {
      uint256 _xvs = IERC20(xvs).balanceOf(address(this));
      if(_xvs > 0 ) {
        IERC20(xvs).safeApprove(uniswapRouter, 0);
        IERC20(xvs).safeApprove(uniswapRouter, _xvs);

        IUniswapRouter(uniswapRouter).swapExactTokensForTokens(_xvs, uint256(0), xvsToWantPath, address(this), block.timestamp.add(1800));
      }
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfStakedWant() public view returns (uint256) {
      return IVToken(vToken).balanceOf(address(this)).mul(IVToken(vToken).exchangeRateStored()).div(1e18)
        .sub(IVToken(vToken).borrowBalanceStored(address(this)));
    }

    function balanceOfStakedWantCurrent() public returns (uint256) {
      return IVToken(vToken).balanceOfUnderlying(address(this))
        .sub(IVToken(vToken).borrowBalanceCurrent(address(this)));
    }

    function borrowLimit() public returns (uint256) {
      return IVToken(vToken).borrowBalanceCurrent(address(this))
        .mul(1e18).div(IVToken(vToken).balanceOfUnderlying(address(this)).mul(collateralFactor()).div(1e18));
    }

    function collateralFactor() public view returns (uint256) {
      (,uint256 _collateralFactor,) = IVenusComptroller(venusComptroller).markets(vToken);
      return _collateralFactor;
    }


    function harvest() public returns (uint harvesterRewarded) {
      require(msg.sender == tx.origin, "not eoa");

      _claimXvs();

      uint _xvs = IERC20(xvs).balanceOf(address(this)); 
      uint256 _harvesterReward;
      if (_xvs > 0) {
        uint256 _fee = _xvs.mul(performanceFee).div(FEE_DENOMINATOR);
        uint256 _reward = _xvs.mul(treasuryReward).div(FEE_DENOMINATOR);
        _harvesterReward = _xvs.mul(harvesterReward).div(FEE_DENOMINATOR);
        IERC20(xvs).safeTransfer(rewards, _fee);
        IERC20(xvs).safeTransfer(treasury, _reward);
        IERC20(xvs).safeTransfer(msg.sender, _harvesterReward);
      }

      _convertRewardsToWant();
      _supplyWant();
      _rebalance(0);

      return _harvesterReward;
    }

    function balanceOf() public view returns (uint256) {
      return balanceOfWant()
        .add(balanceOfStakedWant());
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }
    
    function setStrategist(address _strategist) external onlyOwner {
        strategist = _strategist;
    }

    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        performanceFee = _performanceFee;
    }

    function setTreasuryReward(uint256 _treasuryReward) external onlyOwner {
        treasuryReward = _treasuryReward;
    }

    function setWithdrawalFee(uint256 _withdrawalFee) external onlyOwner {
        withdrawalFee = _withdrawalFee;
    }

    function setHarvesterReward(uint256 _harvesterReward) external onlyOwner {
        harvesterReward = _harvesterReward;
    }

    function setTargetBorrowLimit(uint256 _targetBorrowLimit, uint256 _targetBorrowLimitHysteresis) external onlyOwner {
        targetBorrowLimit = _targetBorrowLimit;
        targetBorrowLimitHysteresis = _targetBorrowLimitHysteresis;
    }

    function pause() external onlyOwner {
        _withdrawAll();
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        _withdrawAll();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }
}