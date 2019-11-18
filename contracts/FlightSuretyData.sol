pragma solidity ^0.5.0;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false
    mapping(address => uint) authorizedContracts;

    struct Airline {
        bool registered;
        bool funded;
    }

    mapping(address => Airline) airlines;
    uint airlines_count = 0;

    struct Flight {
        bool registered;
        address airline;
        uint8 statusCode;
    }
    mapping(string => Flight) private flights;

    mapping(bytes32 => uint256) insurances;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/


    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor () public {
        contractOwner = msg.sender;
        // First airline is registered when contract is deployed
        airlines[contractOwner] = Airline({registered: true, funded: true});
        airlines_count = 1;
    }

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
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier isCallerAuthorized() {
        require(authorizedContracts[msg.sender] == 1, "Unauthorized access (Caller)");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */
    function isOperational() public view returns(bool) {
        return operational;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */
    function setOperatingStatus (bool mode) external requireContractOwner {
        operational = mode;
    }

    function authorizeCaller(address dataContract) external requireIsOperational requireContractOwner {
        authorizedContracts[dataContract] = 1;
    }

    function unauthorizeCaller(address dataContract) external requireIsOperational requireContractOwner {
        authorizedContracts[dataContract] = 0;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function registerAirline (address airline) external requireIsOperational isCallerAuthorized {
        airlines[airline] = Airline({registered: true, funded : false});
        airlines_count = airlines_count.add(1);
    }

    function isAirlineRegistered (address airline) external view requireIsOperational returns (bool) {
        return airlines[airline].registered;
    }

    function isAirlineFunded (address airline) external view requireIsOperational returns (bool) {
        return airlines[airline].funded;
    }

    function fundAirline (address airline) external requireIsOperational isCallerAuthorized {
        airlines[airline].funded = true;
    }

    function getAirlinesCount() external view requireIsOperational returns (uint) {
        return airlines_count;
    }

    function isFlightRegistered (string calldata flightId) external view requireIsOperational returns (bool) {
        return flights[flightId].registered;
    }

    function registerFlight (address airline, string calldata flightId) external requireIsOperational isCallerAuthorized
    {
        require(airlines[airline].registered, "Airline not registered");
        require(!flights[flightId].registered, "Flight already registered");

        flights[flightId] = Flight({
            registered: true,
            airline: airline,
            statusCode: 0
        });
    }

    function getInsuranceKey(address passenger, string memory flightId) internal view requireIsOperational returns(bytes32) {
        return keccak256(abi.encodePacked(passenger, flightId));
    }

    function getInsuranceValue(address passenger, string calldata flightId) external view requireIsOperational returns (uint) {
        bytes32 insuranceKey = getInsuranceKey(passenger, flightId);
        return insurances[insuranceKey];
    }


   /**
    * @dev Buy insurance for a flight
    *
    */
    function buy (address passenger, string calldata flightId, uint amount) external requireIsOperational isCallerAuthorized
    {
        bytes32 insuranceKey = getInsuranceKey(passenger, flightId);
        insurances[insuranceKey] = amount;
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees
                                (
                                )
                                external
                                pure
    {
    }
    

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay
                            (
                            )
                            external
                            pure
    {
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */   
    function fund
                            (   
                            )
                            public
                            payable
    {
    }

    function getFlightKey (address airline, string memory flight, uint256 timestamp) pure internal returns(bytes32) 
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function() external payable requireIsOperational isCallerAuthorized
    {
        fund();
    }


}

