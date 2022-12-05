// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.0;

import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {IInstantDistributionAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IInstantDistributionAgreementV1.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";


abstract contract SuperPool is Ownable, SuperAppBase, Initializable {


    struct Market {
        ISuperToken inputToken;
        uint256 lastDistributionAt; // The last time a distribution was made
        //uint256 rateTolerance; // The percentage to deviate from the oracle scaled to 1e6
        uint128 feeRate;
        //uint128 affiliateFee;
        address owner; // The owner of the market (reciever of fees)
        ISuperToken outputToken; // address of given output supertoken PToken
        //mapping(ISuperToken => OracleInfo) oracles; // Maps tokens to their oracle info
        //mapping(uint32 => OutputPool) outputPools; // Maps IDA indexes to their distributed Supertokens
        //mapping(ISuperToken => uint32) outputPoolIndicies; // Maps tokens to their IDA indexes in OutputPools
        //uint8 numOutputPools; // Indexes outputPools and outputPoolFees
    }


    ISuperfluid internal host; // Superfluid host contract
    IConstantFlowAgreementV1 internal cfa; // The stored constant flow agreement class address
    IInstantDistributionAgreementV1 internal ida; // The stored instant dist. agreement class address
    //ITellor public oracle; // Address of deployed simple oracle for input//output token
    Market internal market;
    // uint32 internal constant PRIMARY_OUTPUT_INDEX = 0;
    // uint8 internal constant MAX_OUTPUT_POOLS = 5;



    // TODO: Emit these events where appropriate
    /// @dev Distribution event. Emitted on each token distribution operation.
    /// @param totalAmount is total distributed amount
    /// @param feeCollected is fee amount collected during distribution
    /// @param token is distributed token address

    event Distribution(
        uint256 totalAmount,
        uint256 feeCollected,
        address token
    );


    constructor(
        address _owner,
        ISuperfluid _host,
        IConstantFlowAgreementV1 _cfa,
        IInstantDistributionAgreementV1 _ida,
        string memory _registrationKey
    ) {
        host = _host;
        cfa = _cfa;
        ida = _ida;

        transferOwnership(_owner);

        uint256 _configWord = SuperAppDefinitions.APP_LEVEL_FINAL;

        if (bytes(_registrationKey).length > 0) {
            host.registerAppWithKey(_configWord, _registrationKey);
        } else {
            host.registerApp(_configWord);
        }
    }

        /// @dev Allows anyone to close any stream if the app is jailed.
    /// @param streamer is stream source (streamer) address
    function emergencyCloseStream(address streamer, ISuperToken token) external virtual {
        // Allows anyone to close any stream if the app is jailed
        require(host.isAppJailed(ISuperApp(address(this))), "!jailed");

        host.callAgreement(
            cfa,
            abi.encodeWithSelector(
                cfa.deleteFlow.selector,
                token,
                streamer,
                address(this),
                new bytes(0) // placeholder
            ),
            "0x"
        );
    }


    /// @dev Close stream from `streamer` address if balance is less than 8 hours of streaming
    /// @param streamer is stream source (streamer) address
    function closeStream(address streamer, ISuperToken token) public {
      // Only closable iff their balance is less than 8 hours of streaming
      (,int96 streamerFlowRate,,) = cfa.getFlow(token, streamer, address(this));
      // int96 streamerFlowRate = getStreamRate(token, streamer);
      require(int(token.balanceOf(streamer)) <= streamerFlowRate * 8 hours,
                "!closable");

      // Close the streamers stream
      // Does this trigger before/afterAgreementTerminated
      host.callAgreement(
          cfa,
          abi.encodeWithSelector(
              cfa.deleteFlow.selector,
              token,
              streamer,
              address(this),
              new bytes(0) // placeholder
          ),
          "0x"
      );
    }

    /// @dev Drain contract's input and output tokens balance to owner if SuperApp dont have any input streams.
    function emergencyDrain(ISuperToken token) external virtual onlyOwner {
        require(host.isAppJailed(ISuperApp(address(this))), "!jailed");

        token.transfer(
            owner(),
            token.balanceOf(address(this))
        );
    }

    // Setters

    // /// @dev Set rate tolerance
    // /// @param _rate This is the new rate we need to set to
    // function setRateTolerance(uint256 _rate) external onlyOwner {
    //     market.rateTolerance = _rate;
    // }

    /// @dev Sets fee rate for a output pool/token
    // /// @param _index IDA index for the output pool/token
    /// @param _feeRate Fee rate for the output pool/token
    function setFeeRate(uint128 _feeRate) external onlyOwner {
        //market.outputPools[_index].feeRate = _feeRate;
        market.feeRate = _feeRate;
    }

    // /// @dev Sets emission rate for a output pool/token
    // /// @param _index IDA index for the output pool/token
    // /// @param _emissionRate Emission rate for the output pool/token
    // function setEmissionRate(uint32 _index, uint128 _emissionRate)
    //     external
    //     onlyOwner
    // {
    //     market.outputPools[_index].emissionRate = _emissionRate;
    // }

    // Getters

    /// @dev Get input token address
    /// @return input token address
    function getInputToken() external view returns (ISuperToken) {
        return market.inputToken;
    }

    /// @dev Get output token address
    /// @return output token address
    function getOutputPool()
        external
        view
        returns (ISuperToken)
    {
        return market.outputToken;
    }

    /// @dev Get last distribution timestamp
    /// @return last distribution timestamp
    function getLastDistributionAt() external view returns (uint256) {
        return market.lastDistributionAt;
    }

    /// @dev Is app jailed in SuperFluid protocol
    /// @return is app jailed in SuperFluid protocol
    function isAppJailed() external view returns (bool) {
        return host.isAppJailed(this);
    }

    // /// @dev Get rate tolerance
    // /// @return Rate tolerance scaled to 1e6
    // function getRateTolerance() external view returns (uint256) {
    //     return market.rateTolerance;
    // }

    /// @dev Get fee rate for a given output pool/token
    /// @return Fee rate for the output pool
    function getFeeRate() external view returns (uint128) {
        return market.feeRate;
    }

    // /// @dev Get emission rate for a given output pool/token
    // /// @param _index IDA index for the output pool/token
    // /// @return Emission rate for the output pool
    // function getEmissionRate(uint32 _index) external view returns (uint256) {
    //     return market.outputPools[_index].emissionRate;
    // }


}