// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.16;

interface IGroth16Verifier {
    
    function verify(uint256[2] calldata _pA,
        uint256[2][2] calldata _pB,
        uint256[2] calldata _pC,
        uint256[4] calldata _pubSignals)
        external
        view
        returns (bool);
}