// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title TicketSalesV6
 * @author Nikita Gurbatov
 * Contract lets users to create an event
 * They can set price, name and number amounts
 * Owners of events receive payment for every ticket sold for that event
 * Tickets are dispensed as NFTs and can be found by unique bytes32
*/

contract TicketSalesV6 is ERC721 {

    using Counters for Counters.Counter;

    /**
     *  EVENT SECTION
     *  -------------
    */

    struct Event{
        address eventOwner;
        string name;
        uint numberOfTickets;
        uint price;
        bytes32 generatedEventId;
        bool isEvent;
    }

    //An array that holds the events structs
    Event[] private events;

    // keep count number of events
    Counters.Counter public eventCounter;
    
    mapping (address => Event) public owner_toEvent;
    mapping (uint => Event) public eventId_toEvent;
    mapping (address => uint) public owner_eventCount;

    mapping(bytes32 => uint) private genId_toEventId;

    // function to generate uniquely identifiable hash
    // for tickets and events
    function generateHash(string memory _name, address _addressOwner) internal pure returns (bytes32) {
        bytes32 generatedHash = bytes32(keccak256(abi.encodePacked(_name, _addressOwner)));
        return generatedHash;
    }

    function createEvent(string memory _name, uint _numberOfTickets, uint _price) public {
        
        // we handle the case for the number of tickets
        require(_numberOfTickets >= 1, "Number of tickets must be greater than 1");

        // a bytes32 is generated to be used as an unique identifier of the event in the front end
        bytes32 generatedEventId = generateHash(_name, msg.sender);

        // it is also used to assert that an account does not create two with the same name
        // we handle the case that an owner creates duplicates of an event
        require (owner_toEvent[msg.sender].generatedEventId != generatedEventId, "Cannot create Event with the same name from the same address");
    
        // we create instance of the new event and add it to our array
        Event memory newEvent = Event(msg.sender, _name, _numberOfTickets, _price, generatedEventId, true);
        events.push(newEvent);

        // map the new states
        eventId_toEvent[eventCounter.current()] = newEvent;
        owner_toEvent[msg.sender] = newEvent;
        owner_eventCount[msg.sender] ++;

        genId_toEventId[generatedEventId] = eventCounter.current();

        eventCounter.increment();
    }

    function getEventsByOwner() public view returns(uint[] memory) {
        uint[] memory result = new uint[](owner_eventCount[msg.sender]);
        uint counter = 0;
        for (uint i = 0; i < events.length; i++) {
            if (eventId_toEvent[i].eventOwner == msg.sender) {
                result[counter] = i;
                counter++;
            }
        }
        return result;
    }
    
    function getEventId_fromGenId(bytes32 generatedEventId) public view returns(uint) {
       uint eventId = genId_toEventId[generatedEventId];
       return eventId;
    }

    /**
     *  TICKET SECTION
     *  --------------
     *  ERC721 Compliant
    */

    constructor() ERC721("Ticket", "TKT") {}

    mapping (address => uint) public _balances;
    mapping (uint => address) public _owner;

    mapping(uint256 => address) public ticketToken_approvals;

    Counters.Counter private ticketTokenId;

    uint[] private tickets;

    function totalSupply() external view returns(uint) {
        return ticketTokenId.current();
    }

    function balanceOf(address owner) public override view returns (uint256 balance) {
        return _balances[owner];
    }

    function ownerOf(uint256 _ticketTokenId) public override view returns (address owner) {
        return _owner[_ticketTokenId];
    }

    function _exists(uint256 _ticketTokenId) internal view override returns (bool) {
        address owner = ownerOf(_ticketTokenId);
        return owner != address(0);
    }

    function buyTicket(bytes32 generatedEventId) public payable {
        
        uint eventId = getEventId_fromGenId(generatedEventId);
        
        // makes sure that event exists
        require(eventId_toEvent[eventId].isEvent == true, "This event never existed");

        // makes sure that the event is not sold out
        require(eventId_toEvent[eventId].numberOfTickets >= 1, "This event is sold out");

        // make sure that payment value is greater than the ticket price
        // and transfers the value to the event owner
        require(msg.value >= eventId_toEvent[eventId].price, "Not enough - please send more ether");
        payable(eventId_toEvent[eventId].eventOwner).transfer(msg.value);

        // increase the ticket balance of ticket buyer by one;
        // map the ticketTokenId to owner
        _balances[msg.sender] ++;
        _owner[ticketTokenId.current()] = msg.sender;

        // push NFT to tickets array
        // and increase the counter
        // next ticketTokenId will be different
        tickets.push(ticketTokenId.current());
        ticketTokenId.increment();

        // decrease the number of tickets for the event by one
        eventId_toEvent[eventId].numberOfTickets --;
    }

    function getMyTickets() public view returns (uint[] memory) {
        uint[] memory myTickets = new uint[](_balances[msg.sender]);
        uint counter = 0;
        for (uint i = 0; i < tickets.length; i++) {
            if (_owner[i] == msg.sender) {
                myTickets[counter] = i;
                counter++;
            }
        }
        return myTickets;
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) public override {
        require(_owner[_tokenId] == msg.sender || ticketToken_approvals[_tokenId] == _to, "You are not the owner of the ticket or the token transfer is not approved");

        _balances[_from] = _balances[_from] - 1;
        _balances[_to] = _balances[_to] + 1;
        _owner[_tokenId] = _to;
    }

    function approve(address to, uint256 _ticketTokenId) public override {
        address owner = ownerOf(_ticketTokenId);
        require (to != owner, "ERC721: approval to current owner");
        require (_exists(_ticketTokenId), "Token does not exist");
        require (msg.sender == owner, "Approval needs to be set by the owner of Token"); 

        ticketToken_approvals[_ticketTokenId] = to;
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) public override {
        require(_owner[_tokenId] == _from || ticketToken_approvals[_tokenId] == _to, "You are not the owner of the ticket or the token transfer is not approved");

        _balances[_from] = _balances[_from] - 1;
        _balances[_to] = _balances[_to] + 1;
        _owner[_tokenId] = _to;
    }
}