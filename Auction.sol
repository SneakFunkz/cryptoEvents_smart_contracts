
// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;
import "contracts/TicketSalesV6.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title TicketAuctionHouse
 * @author Nikita Gurbatov
 * contract receives ether when a successful bid is placed
 * contract has two public accounts
 * withdrawable balance & locked in balance  ||  balance_withdrawableETH & balance_lockedInETH
 * successful bidder:
 *  - has locked in balance increased by msg.value
 * previous highest bidder:
 *  - withdrawable balance increased by their old highest bid
 *  - locked in balance decreases by new 
*/

contract AuctionHouse is TicketSalesV6 {

    using Counters for Counters.Counter; 
    
   struct Auction {
        address highestBidOwner;
        uint highestBidValue;
        uint startBlock;
        uint endBlock;
        // uint ticketTokenId;
        bool isActive;
    }

    // Counters.Counter public auctionCounter;

    mapping(address => uint) public balance_lockedInETH;
    mapping(address => uint) public balance_withdrawableETH;
    mapping (uint => Auction) public ticketTokenId_toAuction;

    Auction[] private Auctions;

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

    // function returns the total eth in contract
    function getThisAddressBalance() external view returns (uint) {
        return address(this).balance;
    }

    // function returns the total withdrawable balance of msg.sender
    function getMyWithdrawalBalance() public view returns(uint) {
        return balance_withdrawableETH[msg.sender];
    }

    function getMyLockedInBalance() public view returns(uint) {
        return balance_lockedInETH[msg.sender];
    }

    event Received(address caller, uint amount);
    event Cancelled();
    event newBid();
    event auctionFinished();

    function setNewHighestBidder(uint _ticketTokenId) private {
        ticketTokenId_toAuction[_ticketTokenId].highestBidOwner = msg.sender;
    }

    function setNewHighestBid(uint _ticketTokenId, uint _value) private {
        ticketTokenId_toAuction[_ticketTokenId].highestBidValue = _value;
    }

    function sub_lockedInBalance(address _owner, uint _value) private {
        balance_lockedInETH[_owner] = balance_lockedInETH[_owner] - _value;
    }

    function inc_lockedInBalance(address _owner, uint _value) private {
        balance_lockedInETH[_owner] = balance_lockedInETH[_owner] + _value;
    }

    function inc_withdawalBalance(address _owner, uint _value) private {
        balance_withdrawableETH[_owner] = balance_withdrawableETH[_owner] + _value;
    }

    function sub_withdawalBalance(address _owner, uint _value) private {
        require(_owner == msg.sender, "You are not able to perform this action");
        balance_withdrawableETH[_owner] = balance_withdrawableETH[_owner] - _value;
    }

    // function checks if the auction is ongoing and returns bool
    // will be used to check if auction owner is 
    // able to withdraw the value of the highest bid
    function auctionActive(uint _ticketTokenId) public returns(bool) {
        bool auctionIsActive;
        if (ticketTokenId_toAuction[_ticketTokenId].endBlock < block.timestamp){
            auctionIsActive = false;
            ticketTokenId_toAuction[_ticketTokenId].isActive = false;
        } else if (ticketTokenId_toAuction[_ticketTokenId].endBlock > block.timestamp || ticketTokenId_toAuction[_ticketTokenId].isActive == true) {
            auctionIsActive = true;
        }
        return auctionIsActive;
    }

    function endAuction(uint _ticketTokenId) public {

        require(ticketTokenId_toAuction[_ticketTokenId].highestBidOwner != address(0), "This auction had no successful bids");

        require(ownerOf(_ticketTokenId) == msg.sender || ticketTokenId_toAuction[_ticketTokenId].highestBidOwner == msg.sender,
            "Only the highest bidder or the owner of the auction may end it");

        // run auctionActive function
        // if it has then it will flick the isActive property to false
        auctionActive(_ticketTokenId);
        require(ticketTokenId_toAuction[_ticketTokenId].isActive == false, "This auction has not ended yet");

        ticketToken_approvals[_ticketTokenId] = ticketTokenId_toAuction[_ticketTokenId].highestBidOwner;

        // (bool success, ) = address(ownerOf(_ticketTokenId)).call{value: ticketTokenId_toAuction[_ticketTokenId].highestBidValue}("");
        // require(success, "failed to place bid");
        sub_lockedInBalance(ticketTokenId_toAuction[_ticketTokenId].highestBidOwner, ticketTokenId_toAuction[_ticketTokenId].highestBidValue);
        inc_withdawalBalance(ownerOf(_ticketTokenId), ticketTokenId_toAuction[_ticketTokenId].highestBidValue);

        safeTransferFrom(ownerOf(_ticketTokenId), ticketTokenId_toAuction[_ticketTokenId].highestBidOwner, _ticketTokenId);
    }

    // CREATES AN AUCTION
    function createAuction(uint _ticketTokenId, uint _minutes) external {
        require (msg.sender == ownerOf(_ticketTokenId), "You are not the owner of the ticket");
        require (_minutes >= 1, "The auction must be set to end in the future, not the past");
        require (auctionActive(_ticketTokenId) != true, "This auction already exists");

        // creates new instance of the auction
        Auction memory newAuction = Auction(address(0), 0, block.timestamp, block.timestamp + _minutes * 1 minutes, true);

        ticketTokenId_toAuction[_ticketTokenId] = newAuction;

        // adds auction to the Auctions array
        Auctions.push(newAuction);
    }

    // PLACES BID
    function placeBids(uint _ticketTokenId) public payable {
        
        // handles case for auction not not being active
        require (auctionActive(_ticketTokenId) == true, "Auction does not exist or is not active");

        // handles case for owner bidding
        require (_owner[_ticketTokenId] != msg.sender, "Owner of the auction may not participate in the auction");

        // get the target auction
        Auction memory targetAuction = ticketTokenId_toAuction[_ticketTokenId];

        // handles cases for validity of bid amount
        require (msg.value > 0, "Cannot bid a value of 0");
        require (msg.value > targetAuction.highestBidValue, "Bid value must be higher than current highest bid");

        // handles cases for timing
        require (block.timestamp < targetAuction.endBlock + 30 seconds, "Not enough time to place a bid");

        // now they have been outbid
        // their locked in funds are decreased
        // & transferred to withdrawable
        sub_lockedInBalance(ticketTokenId_toAuction[_ticketTokenId].highestBidOwner, ticketTokenId_toAuction[_ticketTokenId].highestBidValue);
        inc_withdawalBalance(ticketTokenId_toAuction[_ticketTokenId].highestBidOwner, ticketTokenId_toAuction[_ticketTokenId].highestBidValue);

        // contract receives ether from msg.sender
        (bool success,) = address(this).call{value: msg.value}("");
        require(success, "failed to place bid");

        // the highest bidder should not be allowed to withdraw his eth
        // until he is outbid
        // so we update their locked in balance
        inc_lockedInBalance(msg.sender, msg.value);

        // finally we must update the state of the auction
        // to account for these changes
        setNewHighestBidder(_ticketTokenId);
        setNewHighestBid(_ticketTokenId, msg.value);
    }

    function withdrawMyBalance() public {
        uint _amount = getMyWithdrawalBalance();
        require(balance_withdrawableETH[msg.sender] >= _amount, "Not enough withdrawable funds");
        require(balance_withdrawableETH[msg.sender] > 0, "You have 0 funds to withdraw");

        sub_withdawalBalance(msg.sender, _amount);
        (bool success, ) = address(msg.sender).call{value: _amount}("");
        require(success, "Failed to transfer the funds, aborting.");
    }

}