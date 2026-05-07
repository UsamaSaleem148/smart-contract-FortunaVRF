// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFMigratableConsumerV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Fortuna VRF Lottery
 * @notice A decentralized lottery contract using Chainlink VRF v2.5 for randomness.
 * Players enter by paying a ticket price; after each round, a winner is picked and rewarded.
 */
contract FortunaVRFLottery is VRFConsumerBaseV2Plus {
    enum LotteryState { Open, Calculating }

    /// @notice List of players who entered the current round.
    address[] public players;

    /// @notice Price of one ticket in wei.
    uint256 public ticketPrice;

    /// @notice Current round number.
    uint256 public round;

    /// @notice Jackpot reserve accumulated from previous rounds.
    uint256 public jackpotReserve;

    /// @notice Ticket proceeds collected for the current round (the only ETH eligible for splitting).
    uint256 public prizePool;

    /// @notice Most recent winner.
    address public recentWinner;

    /// @notice When the current round ends (timestamp).
    uint256 public roundEndTime;

    /// @notice Duration of each round in seconds.
    uint256 public roundDuration;

    /// @notice Chainlink VRF coordinator.
    IVRFCoordinatorV2Plus COORDINATOR;

    /// @notice Subscription ID for Chainlink VRF.
    uint256 public subscriptionId;

    /// @notice Key hash for Chainlink VRF.
    bytes32 public keyHash;

    /// @notice Gas limit for VRF callback.
    uint32 public callbackGasLimit = 200_000;

    /// @notice Number of block confirmations for VRF.
    uint16 public requestConfirmations = 3;

    /// @notice Number of random words requested from VRF.
    uint32 public numWords = 1;

    /// @notice Last VRF request ID.
    uint256 public lastRequestId;

    /// @notice Current state of the lottery (open or calculating).
    LotteryState public lotteryState;

    /// @notice Emitted when a new round starts.
    event NewRound(uint256 round, uint256 endTime);

    /// @notice Emitted when a player enters the lottery.
    event PlayerEntered(address indexed player);

    /// @notice Emitted when a winner is picked.
    event WinnerPicked(address indexed winner, uint256 prize);

    /// @notice Emitted when a round is skipped because no players entered.
    event RoundSkipped(uint256 round);

    /**
    * @notice Constructor to initialize the lottery.
    */
    constructor(
        address vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint256 _ticketPrice,
        uint256 _roundDuration
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        COORDINATOR = IVRFCoordinatorV2Plus(vrfCoordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        ticketPrice = _ticketPrice;
        round = 1;
        roundDuration = _roundDuration;

        _startNewRound();
    }

    /**
    * @notice Allows a player to enter the current lottery round by paying the ticket price.
    */
    function enter() external payable {
        require(lotteryState == LotteryState.Open, "Not open");
        require(msg.value == ticketPrice, "Incorrect ticket price");
        require(block.timestamp < roundEndTime, "Round ended");

        players.push(msg.sender);
        prizePool += msg.value;
        emit PlayerEntered(msg.sender);
    }

    /**
    * @notice Check if upkeep is needed (round ended and players present).
    */
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (lotteryState == LotteryState.Open && block.timestamp >= roundEndTime && players.length > 0);
        performData = "";
    }

    /**
    * @notice Called by Chainlink Automation to start winner selection when round ends.
    */
    function performUpkeep(bytes calldata) external {
        require(lotteryState == LotteryState.Open, "Already calculating");
        require(block.timestamp >= roundEndTime, "Round not over yet");

        if (players.length == 0) {
            emit RoundSkipped(round);
            _startNewRound();
            return;
        }

        lotteryState = LotteryState.Calculating;

        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
            keyHash: keyHash,
            subId: subscriptionId,
            requestConfirmations: requestConfirmations,
            callbackGasLimit: callbackGasLimit,
            numWords: numWords,
            extraArgs: ""
        });

        lastRequestId = COORDINATOR.requestRandomWords(req);
    }

    /**
    * @notice Callback function used by VRF Coordinator to provide random words.
    */
    function fulfillRandomWords(uint256 /*requestId*/, uint256[] calldata randomWords) internal override {
        require(players.length > 0, "No players in this round");

        uint256 winnerIndex = randomWords[0] % players.length;
        recentWinner = players[winnerIndex];

        uint256 currentPool = prizePool;
        uint256 prize = (currentPool * 80) / 100;
        uint256 toJackpot = currentPool - prize;

        // Zero out before external call (checks-effects-interactions).
        prizePool = 0;
        jackpotReserve += toJackpot;

        if (prize > 0) {
            payable(recentWinner).transfer(prize);
        }

        emit WinnerPicked(recentWinner, prize);

        _startNewRound();
    }

    /**
    * @notice Internal function to start a new round.
    */
    function _startNewRound() internal {
        delete players;
        round++;
        roundEndTime = block.timestamp + roundDuration;
        lotteryState = LotteryState.Open;

        emit NewRound(round, roundEndTime);
    }

    /**
    * @notice Allows the owner to withdraw the accumulated jackpot.
    */
    function withdrawJackpot(address payable to) external onlyOwner {
        require(jackpotReserve > 0, "No jackpot");
        uint256 amount = jackpotReserve;
        jackpotReserve = 0;
        to.transfer(amount);
    }

    /**
    * @notice Returns the list of current players.
    */
    function getPlayers() external view returns (address[] memory) {
        return players;
    }

    /**
    * @notice Accepts plain ETH transfers.
    */
    receive() external payable {}
}