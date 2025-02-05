pragma solidity ^0.5.0;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    // Consensus Min of airlines
    uint8 AIRLINES_CONSENSUS_MIN = 4;
    uint AIRLINE_FUND = 10 ether;
    uint INSURANCE_LIMIT = 1 ether;


    address private contractOwner;          // Account used to deploy contract

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
    }

    mapping(bytes32 => Flight) private flights;

    mapping(address => address[]) private airlineConsensus;

    // Data Contract
    FlightSuretyData appData;


    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational()
    {
        require(appData.isOperational(), "Contract is currently not operational");
        _;
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireIsAirline() {
        require(appData.isAirlineRegistered(msg.sender), "Address is not a registered Airline");
        _;
    }

    /********************************************************************************************/
    /*                                         EVENTS                                           */
    /********************************************************************************************/

    event AirlineFunded(address airline);
    event AirlineRegistered(address airline, uint256 airlineCount, uint votes);
    event FlightRegistered(address airline, string flightId);


    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
    * @dev Contract constructor
    *
    */
    constructor (address dataContract) public {
        contractOwner = msg.sender;
        appData = FlightSuretyData(dataContract);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() public view returns(bool)
    {
        return appData.isOperational();
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/


   /**
    * @dev Add an airline to the registration queue
    *
    */
    function registerAirline (address airline) external requireIsOperational requireIsAirline
    {
        require(!appData.isAirlineRegistered(airline), "Airline already registered");

        uint airlineCount = appData.getAirlinesCount();

        if (airlineCount < AIRLINES_CONSENSUS_MIN) {
            airlineCount = airlineCount.add(1);
            appData.registerAirline(airline);

            emit AirlineRegistered(airline, airlineCount, 0);

            return;
        }

        // check if the airline already votted
        for (uint a = 0; a < airlineConsensus[airline].length; a++) {
           if (airlineConsensus[airline][a] == msg.sender) {
               return;
           }
        }

        airlineConsensus[airline].push(msg.sender);

        // check if airline has enough votes
        if(airlineConsensus[airline].length >= airlineCount.div(2)) {
            appData.registerAirline(airline);

            airlineCount = airlineCount.add(1);

            emit AirlineRegistered(airline, airlineCount, airlineConsensus[airline].length);
        }

    }

    function fundAirline() external payable requireIsAirline
    {
        require(!appData.isAirlineFunded(msg.sender), "Airline already funded");
        require(msg.value >= AIRLINE_FUND, "Not enough to Fund");

        msg.sender.transfer(msg.value);

        appData.fundAirline(msg.sender);

        emit AirlineFunded(msg.sender);
    }

    function buyInsurance(string calldata flightId) external payable
    {
        require(msg.value > 0, "Insurance value can not be zero");
        require(msg.value <= 1 ether, "Insurance limit is 1 ether");

        appData.buy(msg.sender, flightId, msg.value);
    }

    function withdrawalInsurance(string calldata flightId) external payable
    {
        uint amount = appData.withdrawal(msg.sender, flightId);
        msg.sender.transfer(amount);
    }


   /**
    * @dev Register a future flight for insuring.
    *
    */
    function registerFlight(string calldata flightId) external
    {
        appData.registerFlight(msg.sender, flightId);

        emit FlightRegistered(msg.sender, flightId);
    }

   /**
    * @dev Called after oracle has updated flight status
    *
    */
    function processFlightStatus (string memory flight, uint8 statusCode) internal
    {
        if (statusCode == STATUS_CODE_LATE_AIRLINE) {
            appData.creditInsurees(flight);
        }
    }


    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus (address airline, string calldata flight, uint256 timestamp) external
    {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        oracleResponses[key] = ResponseInfo({requester: msg.sender, isOpen: true});

        emit OracleRequest(index, airline, flight, timestamp);
    }


// region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;


    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                        // This lets us group responses and identify
                                                        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);


    // Register an oracle with the contract
    function registerOracle () external payable
    {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    function getMyIndexes () external view returns (uint8[3] memory)
    {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse (
                            uint8 index,
                            address airline,
                            string calldata flight,
                            uint256 timestamp,
                            uint8 statusCode
                        )
                        external
    {
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");


        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {

            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(flight, statusCode);
        }
    }


    function getFlightKey (address airline, string memory flight, uint256 timestamp) internal pure returns(bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes (address account) internal returns(uint8[3] memory)
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while(indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex (address account) internal returns (uint8)
    {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

// endregion

    function() external payable
    {
    }
}

contract FlightSuretyData {
    function isOperational() external view returns(bool);

    function registerAirline(address airline) external;
    function fundAirline(address airline) external;
    function isAirlineRegistered(address airline) external view returns (bool);
    function isAirlineFunded(address airline) external view returns (bool);
    function getAirlinesCount() external view returns (uint);

    function registerFlight (address airline, string calldata flightId) external;

    function buy (address payable passenger, string calldata flightId, uint amount) external payable;
    function creditInsurees (string calldata flightId) external;
    function withdrawal (address passenger, string calldata flightId) external payable  returns (uint256);
}