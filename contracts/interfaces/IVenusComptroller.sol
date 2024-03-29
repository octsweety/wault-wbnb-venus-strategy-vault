//SPDX-License-Identifier: Unlicense
pragma solidity >0.6.0;

interface IVenusComptroller {
  function _addVenusMarkets ( address[] calldata vTokens ) external;
  function _become ( address unitroller ) external;
  function _borrowGuardianPaused (  ) external view returns ( bool );
  function _dropVenusMarket ( address vToken ) external;
  function _mintGuardianPaused (  ) external view returns ( bool );
  function _setCloseFactor ( uint256 newCloseFactorMantissa ) external returns ( uint256 );
  function _setCollateralFactor ( address vToken, uint256 newCollateralFactorMantissa ) external returns ( uint256 );
  function _setLiquidationIncentive ( uint256 newLiquidationIncentiveMantissa ) external returns ( uint256 );
  function _setMaxAssets ( uint256 newMaxAssets ) external returns ( uint256 );
  function _setPauseGuardian ( address newPauseGuardian ) external returns ( uint256 );
  function _setPriceOracle ( address newOracle ) external returns ( uint256 );
  function _setProtocolPaused ( bool state ) external returns ( bool );
  function _setVAIController ( address vaiController_ ) external returns ( uint256 );
  function _setVAIMintRate ( uint256 newVAIMintRate ) external returns ( uint256 );
  function _setVenusRate ( uint256 venusRate_ ) external;
  function _supportMarket ( address vToken ) external returns ( uint256 );
  function accountAssets ( address, uint256 ) external view returns ( address );
  function admin (  ) external view returns ( address );
  function allMarkets ( uint256 ) external view returns ( address );
  function borrowAllowed ( address vToken, address borrower, uint256 borrowAmount ) external returns ( uint256 );
  function borrowGuardianPaused ( address ) external view returns ( bool );
  function borrowVerify ( address vToken, address borrower, uint256 borrowAmount ) external;
  function checkMembership ( address account, address vToken ) external view returns ( bool );
  function claimVenus ( address holder, address[] calldata vTokens ) external;
  function claimVenus ( address holder ) external;
  function claimVenus ( address[] calldata holders, address[] calldata vTokens, bool borrowers, bool suppliers ) external;
  function closeFactorMantissa (  ) external view returns ( uint256 );
  function comptrollerImplementation (  ) external view returns ( address );
  function enterMarkets ( address[] calldata vTokens ) external returns ( uint256[] memory );
  function exitMarket ( address vTokenAddress ) external returns ( uint256 );
  function getAccountLiquidity ( address account ) external view returns ( uint256, uint256, uint256 );
  function getAllMarkets (  ) external view returns ( address[] memory );
  function getAssetsIn ( address account ) external view returns ( address[] memory );
  function getBlockNumber (  ) external view returns ( uint256 );
  function getHypotheticalAccountLiquidity ( address account, address vTokenModify, uint256 redeemTokens, uint256 borrowAmount ) external view returns ( uint256, uint256, uint256 );
  function getMintableVAI ( address minter ) external view returns ( uint256, uint256 );
  function getVAIMintRate (  ) external view returns ( uint256 );
  function getXVSAddress (  ) external view returns ( address );
  function isComptroller (  ) external view returns ( bool );
  function liquidateBorrowAllowed ( address vTokenBorrowed, address vTokenCollateral, address liquidator, address borrower, uint256 repayAmount ) external returns ( uint256 );
  function liquidateBorrowVerify ( address vTokenBorrowed, address vTokenCollateral, address liquidator, address borrower, uint256 actualRepayAmount, uint256 seizeTokens ) external;
  function liquidateCalculateSeizeTokens ( address vTokenBorrowed, address vTokenCollateral, uint256 actualRepayAmount ) external view returns ( uint256, uint256 );
  function liquidationIncentiveMantissa (  ) external view returns ( uint256 );
  function markets ( address ) external view returns ( bool isListed, uint256 collateralFactorMantissa, bool isVenus );
  function maxAssets (  ) external view returns ( uint256 );
  function mintAllowed ( address vToken, address minter, uint256 mintAmount ) external returns ( uint256 );
  function mintGuardianPaused ( address ) external view returns ( bool );
  function mintVAI ( uint256 mintVAIAmount ) external returns ( uint256 );
  function mintVAIGuardianPaused (  ) external view returns ( bool );
  function mintVerify ( address vToken, address minter, uint256 actualMintAmount, uint256 mintTokens ) external;
  function mintedVAIOf ( address owner ) external view returns ( uint256 );
  function mintedVAIs ( address ) external view returns ( uint256 );
  function oracle (  ) external view returns ( address );
  function pauseGuardian (  ) external view returns ( address );
  function pendingAdmin (  ) external view returns ( address );
  function pendingComptrollerImplementation (  ) external view returns ( address );
  function protocolPaused (  ) external view returns ( bool );
  function redeemAllowed ( address vToken, address redeemer, uint256 redeemTokens ) external returns ( uint256 );
  function redeemVerify ( address vToken, address redeemer, uint256 redeemAmount, uint256 redeemTokens ) external;
  function refreshVenusSpeeds (  ) external;
  function repayBorrowAllowed ( address vToken, address payer, address borrower, uint256 repayAmount ) external returns ( uint256 );
  function repayBorrowVerify ( address vToken, address payer, address borrower, uint256 actualRepayAmount, uint256 borrowerIndex ) external;
  function repayVAI ( uint256 repayVAIAmount ) external returns ( uint256 );
  function repayVAIGuardianPaused (  ) external view returns ( bool );
  function seizeAllowed ( address vTokenCollateral, address vTokenBorrowed, address liquidator, address borrower, uint256 seizeTokens ) external returns ( uint256 );
  function seizeGuardianPaused (  ) external view returns ( bool );
  function seizeVerify ( address vTokenCollateral, address vTokenBorrowed, address liquidator, address borrower, uint256 seizeTokens ) external;
  function setMintedVAIOf ( address owner, uint256 amount ) external returns ( uint256 );
  function transferAllowed ( address vToken, address src, address dst, uint256 transferTokens ) external returns ( uint256 );
  function transferGuardianPaused (  ) external view returns ( bool );
  function transferVerify ( address vToken, address src, address dst, uint256 transferTokens ) external;
  function vaiController (  ) external view returns ( address );
  function vaiMintRate (  ) external view returns ( uint256 );
  function venusAccrued ( address ) external view returns ( uint256 );
  // function venusBorrowState ( address ) external view returns ( uint224 index, uint32 block );
  function venusBorrowerIndex ( address, address ) external view returns ( uint256 );
  function venusClaimThreshold (  ) external view returns ( uint256 );
  function venusInitialIndex (  ) external view returns ( uint224 );
  function venusRate (  ) external view returns ( uint256 );
  function venusSpeeds ( address ) external view returns ( uint256 );
  function venusSupplierIndex ( address, address ) external view returns ( uint256 );
  // function venusSupplyState ( address ) external view returns ( uint224 index, uint32 block );
}