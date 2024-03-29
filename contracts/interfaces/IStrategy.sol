// SPDX-License-Identifier: MIT
pragma solidity >0.6.0;

interface IStrategy {
    function want() external view returns (address);
    function deposit() external returns (uint256);
    function withdraw(uint256) external returns (uint256);
    function balanceOf() external view returns (uint256);
    function harvest() external;
    function retireStrat() external;
    function panic() external;
    function pause() external;
    function unpause() external;
}