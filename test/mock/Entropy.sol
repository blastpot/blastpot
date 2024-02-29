// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {IEntropy} from "entropy/IEntropy.sol";
import {EntropyStructs} from "entropy/EntropyStructs.sol";

contract MockEntropy is IEntropy {
    uint64 public sequenceNum;
    address public dprovider = address(0x0000000000000000000000000000000000000001);
    bytes32 lastRandom;

    mapping(uint64 => bytes32) public requests;

    function register(uint128, bytes32, bytes calldata, uint64, bytes calldata) external override {}

    function withdraw(uint128 amount) external override {}

    function getFee(address) external pure override returns (uint128 fee) {
        return 0.01 ether;
    }

    function request(address, bytes32 commitment, bool)
        external
        payable
        override
        returns (uint64 assignedSequenceNumber)
    {
        if (msg.value < 0.01 ether) revert();
        requests[sequenceNum] = commitment;
        assignedSequenceNumber = sequenceNum++;
    }

    function reveal(address, uint64 _sequenceNum, bytes32 userRandomness, bytes32 random)
        external
        override
        returns (bytes32 randomNumber)
    {
        if (requests[_sequenceNum] != userRandomness) revert();
        lastRandom = random;
        return random;
    }

    function getProviderInfo(address provider)
        external
        view
        override
        returns (EntropyStructs.ProviderInfo memory info)
    {}

    function getDefaultProvider() external view override returns (address provider) {
        return dprovider;
    }

    function getRequest(address provider, uint64 sequenceNumber)
        external
        view
        override
        returns (EntropyStructs.Request memory req)
    {}

    function getAccruedPythFees() external view override returns (uint128 accruedPythFees) {}

    function constructUserCommitment(bytes32 userRandomness) external pure override returns (bytes32 commitment) {}

    function combineRandomValues(bytes32 userRandomness, bytes32 providerRandomness, bytes32 blockHash)
        external
        pure
        override
        returns (bytes32 randomNumber)
    {}
}
