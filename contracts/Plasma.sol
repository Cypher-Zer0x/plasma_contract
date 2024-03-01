// SPDX-License-Identifier: UNLICENSED
//@author : Cypher Lab Team - Cypher Zer0x
pragma solidity 0.8.16;

import "./IRiscZeroVerifier.sol";
import {PrimitiveTypeUtils} from "@iden3/contracts/lib/PrimitiveTypeUtils.sol";
import {ICircuitValidator} from "@iden3/contracts/interfaces/ICircuitValidator.sol";
import {ZKPVerifier} from "@iden3/contracts/verifiers/ZKPVerifier.sol";

contract Plasma is ZKPVerifier {
    // ##### Constants
    /**
     * @notice The time after which a deposit can be exited
     */
    uint256 public constant EXIT_LOCKTIME = 1 weeks;
    /**
     * @notice The amount of stake required to become a validator
     */
    uint256 public constant STAKE_AMOUNT = 1 ether;
    /**
     * @notice The id of the next exit
     */
    uint256 next_exit_id =0;

    /** 
     * @notice The address of the RISC-ZERO verifier contract
     * @dev The RISC-ZERO verifier contract is used to verify the validity of the zero-knowledge proof
     * @dev deployed on Sepolia testnet
    */
    IRiscZeroVerifier RISC_ZERO_GROTH_16_VERIFIER = IRiscZeroVerifier(0x83C2e9CD64B2A16D3908E94C7654f3864212E2F8);

    // ######### Polygon ID
    uint64 public constant TRANSFER_REQUEST_ID = 1;
    mapping(uint256 => address) public idToAddress;
    mapping(address => uint256) public addressToId;

    // ##### State variables
    /**
     * @notice The mapping of validators
     */
    mapping(address => bool) public isValidator;
    /**
     * @notice The mapping of public keys
     */
    mapping(address => string) public pubKey; 

    /**
     * @notice The mapping of exits
     * @dev The ownner address is the key
     * @dev The exit ids are the ids of the exits of the owner
     */
    mapping(address => uint256[]) public exitIds;
    /**
     * @notice The mapping of exit values
     * @dev The exit value is the amount of the exit (in the smallest unit)
     * @dev takes the exit id and returns the amount
     */
    mapping(uint256 => uint256) public exitValues; 
    /**
     * @notice The mapping of exit lock times
     * @dev The lock time is the timestamp when the exit can be processed
     * @dev takes the exit id and returns the lock time
     */
    mapping(uint256 => uint256) public exitLockTimes; 

    // ##### Events
    /**
     * @notice Event triggered when a deposit is created
     * @dev The owner is the msg.sender of the deposit
     * @dev The amount is the amount of the deposit (in the smallest unit)
     * @dev The currency is the currency of the deposit
     * @dev The blockNumber is the block number of the deposit
     * @dev The pubKey is the compressed public key of the owner of the utxo on the privacy layer
     * @dev The rG is the random point used to create the commitment on the privacy layer
     */
    event DepositCreated(
        address owner, 
        uint amount, 
        string currency, 
        uint blockNumber, 
        string pubKey, 
        string rG 
    );

    /**
     * @notice Event triggered when a user requests to exit
     * @dev The owner is the address who can withdraw the funds from contract
     * @dev The amount is the amount of the exit (in the smallest unit)
     * @dev The currency is the currency of the exit
     * @dev The lockTime is the timestamp when the exit can be processed
     * @dev The pubKey is the compressed public key of the owner of the utxo on the privacy layer
     */
    event ExitRequest(
        address owner, 
        uint256 amount, 
        string currency, 
        uint256 lockTime, 
        string pubKey 
    );

    /**
     * @notice Event triggered when a user claims an exit
     * @dev The owner is the address who can withdraw the funds from contract
     * @dev The exitId is the id of the exit
     * @dev The amount is the amount of the exit (in the smallest unit)
     */
    event ExitClaimed(
        address owner,
        uint256 exitId, 
        uint256 amount 
    );

    /**
     * @notice Event triggered when a validator is added
     * @dev The owner is the address who can withdraw the funds from contract
     * @dev The pubKey is the compressed public key of the validator in the privacy layer
     * @dev The stakedAmount is the amount of the stake (in the smallest unit)
     */
    event ValidatorAdded(
        address owner, 
        string pubKey, 
        uint256 stakedAmount 
    );

    /**
     * @notice Event triggered when a validator requests to exit
     * @dev The owner is the address who can withdraw the funds from contract
     * @dev The amount is the amount of the exit (in the smallest unit)
     * @dev The lockTime is the timestamp when the exit can be processed
     * @dev The pubKey is the compressed public key of the validator on the privacy layer
     */
    event ValidatorExitRequest(
        address owner, 
        uint256 amount, 
        uint256 lockTime, 
        string pubKey 
    );

    /**
     * @notice Event triggered when a proof is published
     * @dev The seal is the zero-knowledge proof
     * @dev The imageId is the id of the image
     * @dev The postStateDigest is the digest of the post state
     * @dev The journalDigest is the digest of the journal
     */
    event ProofPublished(
        address publisher,
        bytes seal,
        bytes32 imageId,
        bytes32 postStateDigest,
        bytes32 journalDigest
    );

    // ##### Modifiers
    /**
     * @notice Modifier to check if the msg.sender is a validator
     */
    modifier onlyValidator() {
        require(
            isValidator[msg.sender],
            "Only validator can call this function"
        );
        _;
    }

    // ##### Functions

    /**
     * @notice Deposit function
     * @dev The deposit function is used to deposit funds into the contract
     * @dev The deposit function emits a DepositCreated event
     * @dev The deposit function returns the block number of the deposit
     * @param _pubKey is the compressed public key of the owner of the utxo on the privacy layer
     * @param _rG is the random point used to create the commitment on the privacy layer
     * @return blockNumber is the block number of the deposit
     */
    function deposit(
        string calldata _pubKey,
        string calldata _rG 
        ) public payable returns (uint256 blockNumber) {
        require(
            proofs[msg.sender][TRANSFER_REQUEST_ID] == true,
            "only identities who provided proof are allowed to deposit"
        );
        if (msg.value == 0) {
            revert("Deposit amount must be greater than 0");
        }
        emit DepositCreated(
            msg.sender,
            msg.value,
            "ETH",
            block.number,
            _pubKey,
            _rG
        );
        return block.number;
    }

    /**
     * @notice Request exit function
     * @dev The requestExit function is used to request an exit from the contract 
     * @dev The requestExit function emits an ExitRequest event
     * @dev The requestExit function returns the lock time of the exit
     * @param _owner is the address who can withdraw the funds from contract
     * @param _amount is the amount of the exit (in the smallest unit)
     * @param _currency is the currency of the exit
     * @param _pubKey is the compressed public key of the owner of the utxo on the privacy layer
     * @return lockTime is the timestamp when the exit can be processed
     */
    function requestExit(
        address _owner, 
        uint256 _amount, 
        string calldata _currency,
        string calldata _pubKey 
    ) public onlyValidator returns (uint256 lockTime) {

        exitIds[_owner].push(next_exit_id);
        exitValues[next_exit_id] = _amount;
        exitLockTimes[next_exit_id] = block.timestamp + EXIT_LOCKTIME;

        next_exit_id++;

        emit ExitRequest(
            _owner,
            _amount,
            _currency,
            block.timestamp + EXIT_LOCKTIME,
            _pubKey
        );

        return block.timestamp + EXIT_LOCKTIME;
    }

    /**
     * @notice Claim exits function
     * @dev The claimExits function is used to claim exits from the contract
     * @dev The claimExits function emits an ExitClaimed event
     * @dev The claimExits function takes an array of exit ids and processes them
     * @param _exitIds is the array of exit ids
     */
    function claimExits(uint256[] memory _exitIds) public {
        require(
            proofs[msg.sender][TRANSFER_REQUEST_ID] == true,
            "only identities who provided proof are allowed to claim tokens"
        );
        for (uint256 i = 0; i < _exitIds.length; i++) {
            // check if msg.sender is the owner of the exit
            bool exitIdFound = false;
            for (uint256 j = 0; j < exitIds[msg.sender].length; j++) {
                if (exitIds[msg.sender][j] == _exitIds[i]) {
                    // remove the exit id from the array
                    delete exitIds[msg.sender][j];
                    exitIdFound = true;
                    break;
                }
            }

            require(exitIdFound, "Exit id already consumed or not related to msg.sender");

            // check if the exit is ready
            require(
                exitLockTimes[_exitIds[i]] < block.timestamp,
                "Exit is not ready"
            );
            delete exitLockTimes[_exitIds[i]];

            // get the amount of the exit
            uint256 amount = exitValues[_exitIds[i]];
            require(address(this).balance >= amount, "Contract balance is not enough");
            delete exitValues[_exitIds[i]];
            emit ExitClaimed(msg.sender, _exitIds[i], amount);
            payable(msg.sender).transfer(amount);
        }
    }

    /**
     * @notice Become validator function
     * @dev The becomeValidator function is used to become a validator
     * @dev The becomeValidator function emits a ValidatorAdded event
     * @dev The becomeValidator function requires a stake of STAKE_AMOUNT
     * @param pubkey is the compressed public key of the validator in the privacy layer
     */
    function becomeValidator(string memory pubkey) public payable {
        require(msg.value == STAKE_AMOUNT, "Stake amount is not correct");
        isValidator[msg.sender] = true;
        pubKey[msg.sender] = pubkey;
        emit ValidatorAdded(msg.sender, pubkey, STAKE_AMOUNT);
    }

    /**
     * @notice Remove validator function
     * @dev The removeValidator function is used to remove a validator
     * @dev The removeValidator function emits a ValidatorExitRequest event
     * @dev The removeValidator function requires a stake of STAKE_AMOUNT
     */
    function removeValidator() public onlyValidator {
        isValidator[msg.sender] = false;
        exitIds[msg.sender].push(next_exit_id);
        exitValues[next_exit_id] = STAKE_AMOUNT;
        exitLockTimes[next_exit_id] = block.timestamp + EXIT_LOCKTIME;
        next_exit_id++;

        emit ValidatorExitRequest(
            msg.sender,
            STAKE_AMOUNT,
            block.timestamp + EXIT_LOCKTIME,
            pubKey[msg.sender]
        );
    }
    /**
    * @notice Publish proof function
    * @dev The publishProof function is used to publish a proof
    * @dev The publishProof function emits a ProofPublished event
    * @dev The publishProof function requires a valid zero-knowledge proof
    */
    function publishProof(bytes calldata seal, bytes32 imageId, bytes32 postStateDigest, bytes32 journalDigest) public onlyValidator {
        bool success = RISC_ZERO_GROTH_16_VERIFIER.verify(seal, imageId, postStateDigest, journalDigest);
        require(success, "Proof is not valid");
        emit ProofPublished(msg.sender, seal, imageId, postStateDigest, journalDigest);
    }

    // ##### Polygon ID functions

    function _beforeProofSubmit(
        uint64 /* requestId */,
        uint256[] memory inputs,
        ICircuitValidator validator
    ) internal view override {
        // check that  challenge input is address of sender
        address addr = PrimitiveTypeUtils.int256ToAddress(
            inputs[validator.inputIndexOf("challenge")]
        );
        // this is linking between msg.sender and
        require(
            _msgSender() == addr,
            "address in proof is not a sender address"
        );
    }

    function _afterProofSubmit(
        uint64 requestId,
        uint256[] memory inputs,
        ICircuitValidator validator
    ) internal override {
        require(
            requestId == TRANSFER_REQUEST_ID && addressToId[_msgSender()] == 0,
            "proof can not be submitted more than once"
        );
    }
}
