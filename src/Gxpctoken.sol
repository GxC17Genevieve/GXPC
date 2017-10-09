pragma solidity ^0.4.17;


    /****************************************************************
     *
     * dapp framework standard modules
     *
     ****************************************************************/

import "ds-auth/auth.sol";
import "ds-math/math.sol";
import "ds-note/note.sol";
import "ds-stop/stop.sol";
import "ds-thing/thing.sol";
import "ds-token/token.sol";
import "ds-vault/multivault.sol";


    /****************************************************************
     *
     * Base contract supporting async send for pull payments
     * Inherit from this contract and use asyncSend instead of send
     *
     ****************************************************************/

contract PullPayment {
    mapping(address => uint) public payments;

    event RefundETH(address to, uint value);

    // Store sent amount as credit to be pulled, called by payer
    function asyncSend(address dest, uint amount) internal {
        payments[dest] += amount;
    }

    // Withdraw accumulated balance, called by payee
    function withdrawPayments() internal returns (bool) {
        address payee = msg.sender;
        uint payment = payments[payee];

        if (payment == 0) {
            revert();
        }

        if (this.balance < payment) {
            revert();
        }

        payments[payee] = 0;

        if (!payee.send(payment)) {
            revert();
        }
        RefundETH(payee, payment);
        return true;
    }
}


    /****************************************************************
     *
     * Crowdsale Smart Contract
     * Collects ETH and in return sends GXPC tokens to the Backers
     *
     ****************************************************************/

//contract Crowdsale is SafeMath, Pausable, PullPayment {
contract Crowdsale is DSMath, DSStop, PullPayment {

    struct Backer {
        uint weiReceived; // amount of ETH contributed
        uint GXPCSent;    // amount of tokens  sent        
    }

    Gxpctoken public gxpc;                     // DMINI contract reference   
    address   public multisigETH;              // Multisig contract that will receive the ETH    
    address   public team;                     // Address at which the team GXPC will be sent   
    uint      public ETHReceived;              // Number of ETH received
    uint      public GXPCSentToETH;            // Number of GXPC sent to ETH contributors
    uint      public startBlock;               // Crowdsale start block
    uint      public endBlock;                 // Crowdsale end block
    uint      public maxCap;                   // Maximum number of GXPC to sell
    uint      public minCap;                   // Minimum number of ETH to raise
    uint      public minInvestETH;             // Minimum amount to invest
    bool      public crowdsaleClosed;          // Is crowdsale still on going?
    uint      public tokenPriceWei;            // Token price in Wei
    uint             GXPCReservedForPresale ;  // Number of GXPC Tokens reserved for presale
    uint             multiplier = 10000000000; // to provide 10 decimal values

    // Looping through Backers
    mapping(address => Backer) public backers; //backer list
    address[] public backersIndex ;            // to be able to iterate through backers when distributing the tokens

    // @notice to verify if action is not performed out of the campaing range
    modifier respectTimeFrame() {
        if ((block.number < startBlock) || (block.number > endBlock)) revert();
        _;
    }

    modifier minCapNotReached() {
        if (GXPCSentToETH >= minCap) revert();
        _;
    }

    // Events
    event ReceivedETH(address backer, uint amount, uint tokenAmount);

    // Crowdsale  {constructor}
    // @notice fired when contract is created. Initializes all constants.
    function Crowdsale() {
        multisigETH   = 0x62739Ec09cdD8FAe2f7b976f8C11DbE338DF8750; 
        team          = 0x62739Ec09cdD8FAe2f7b976f8C11DbE338DF8750;                    
        GXPCSentToETH = 487000 * multiplier;               
        minInvestETH  = 100000000000000000 ; // 0.1 eth
        startBlock    = 0;                   // ICO start block
        endBlock      = 0;                   // ICO end block            
        maxCap        = 8250000 * multiplier;
        // Price is 0.001 eth                         
        tokenPriceWei = 3004447000000000;
        minCap        = 500000 * multiplier;
    }

    // @notice Specify address of token contract
    // @param _GXPCAddress {address} address of GXPC token contrac
    // @return res {bool}
    // TO DO replace onlyOwner by DSAuth
    //function updateTokenAddress(Gxpctoken _GXPCAddress) public onlyOwner() returns(bool res) {
    function updateTokenAddress(Gxpctoken _GXPCAddress) public returns(bool res) {
        gxpc = _GXPCAddress;  
        return true;    
    }

    // @notice modify this address should this be needed. 
    // TO DO replace onlyOwner by DSAuth
    //function updateTeamAddress(address _teamAddress) public onlyOwner returns(bool){
    function updateTeamAddress(address _teamAddress) public returns(bool){
        team = _teamAddress;
        return true; 
    }

    // @notice return number of contributors
    // @return  {uint} number of contributors
    function numberOfBackers()constant returns (uint){
        return backersIndex.length;
    }

    // {fallback function}
    // @notice It will call internal function which handels allocation of Ether and calculates GXPC tokens.
    function () payable {         
        handleETH(msg.sender);
    }

    // @notice It will be called by owner to start the sale   
    // TO DO replace onlyOwner by DSAuth
    //function start(uint _block) onlyOwner() {
    function start(uint _block) {
        startBlock      = block.number;
        endBlock        = startBlock + _block; //TODO: Replace _block with 40320 for 7 days
        // 1 week in blocks = 40320 (4 * 60 * 24 * 7)
        // enable this for live assuming each bloc takes 15 sec
        crowdsaleClosed = false;
    }

    // @notice It will be called by fallback function whenever ether is sent to it
    // @param  _backer {address} address of beneficiary
    // @return res {bool} true if transaction was successful
    // TO DO replace stopInEmergency and respectTimeFrame by DSAuth
    //function handleETH(address _backer) internal stopInEmergency respectTimeFrame returns(bool res) {
    function handleETH(address _backer) internal returns(bool res) {

        if (msg.value < minInvestETH) revert(); // stop when required minimum is not sent

        uint GXPCToSend = (msg.value * multiplier) / tokenPriceWei ; // calculate number of tokens

        // Ensure that max cap hasn't been reached
        //if (safeAdd(GXPCSentToETH, GXPCToSend) > maxCap) revert();
        if (add(GXPCSentToETH, GXPCToSend) > maxCap) revert();

        Backer storage backer = backers[_backer];

         if ( backer.weiReceived == 0)
             backersIndex.push(_backer);

        if (!gxpc.transfer(_backer, GXPCToSend)) revert(); // Transfer GXPC tokens
        //backer.GXPCSent = safeAdd(backer.GXPCSent, GXPCToSend);
        backer.GXPCSent = add(backer.GXPCSent, GXPCToSend);
        //backer.weiReceived = safeAdd(backer.weiReceived, msg.value);
        backer.weiReceived = add(backer.weiReceived, msg.value);
        //ETHReceived = safeAdd(ETHReceived, msg.value); // Update the total Ether recived
        ETHReceived = add(ETHReceived, msg.value); // Update the total Ether recived
        //GXPCSentToETH = safeAdd(GXPCSentToETH, GXPCToSend);
        GXPCSentToETH = add(GXPCSentToETH, GXPCToSend);
        ReceivedETH(_backer, msg.value, GXPCToSend); // Register event
        return true;
    }

    // @notice This function will finalize the sale.
    // It will only execute if predetermined sale time passed or all tokens are sold.
    // TO DO replace onlyOwner by DSAuth
    //function finalize() onlyOwner() {
    function finalize() {

        if (crowdsaleClosed) revert();
        
        uint daysToRefund = 4*60*24*10;  //10 days        

        if (block.number < endBlock && GXPCSentToETH < maxCap -100 ) revert();  // -100 is used to allow closing of the campaing when contribution is near
                                                                               // finished as exact amount of maxCap might be not feasible e.g. you can't easily buy few tokens
                                                                               // when min contribution is 0.1 ETH

        //if (GXPCSentToETH < minCap && block.number < safeAdd(endBlock , daysToRefund)) revert();   
        if (GXPCSentToETH < minCap && block.number < add(endBlock , daysToRefund)) revert();   

        if (GXPCSentToETH > minCap) {
            if (!multisigETH.send(this.balance)) revert();  // transfer balance to multisig wallet
            if (!gxpc.transfer(team,  gxpc.balanceOf(this))) revert(); // transfer tokens to admin account or multisig wallet                                
            gxpc.unlock();    // release lock from transfering tokens. 
        }
        else{
            if (!gxpc.burn(this, gxpc.balanceOf(this))) revert();  // burn all the tokens remaining in the contract                       
        }

        crowdsaleClosed = true;
        
    }

    // @notice Failsafe drain
    // TO DO replace onlyOwner by DSAuth
    function drain() {
    //function drain() onlyOwner(){
        if (!owner.send(this.balance)) revert();
    }

    // @notice Failsafe transfer tokens for the team to given account 
    // TO DO replace onlyOwner by DSAuth
    function transferDevTokens(address _devAddress) returns(bool){
    //function transferDevTokens(address _devAddress) onlyOwner returns(bool){
        if (!gxpc.transfer(_devAddress,  gxpc.balanceOf(this))) 
            revert(); 
        return true;

    }    

    // @notice Prepare refund of the backer if minimum is not reached
    // burn the tokens
    function prepareRefund()  minCapNotReached internal returns (bool){
        uint value = backers[msg.sender].GXPCSent;

        if (value == 0) revert();           
        if (!gxpc.burn(msg.sender, value)) revert();
        uint ETHToSend = backers[msg.sender].weiReceived;
        backers[msg.sender].weiReceived = 0;
        backers[msg.sender].GXPCSent = 0;
        if (ETHToSend > 0) {
            asyncSend(msg.sender, ETHToSend);
            return true;
        }else
            return false;
        
    }

    // @notice refund the backer
    function refund() public returns (bool){

        if (!prepareRefund()) revert();
        if (!withdrawPayments()) revert();
        return true;

    }
 
}


    /****************************************************************
     *
     * System Rules smart contract
     * Interface implementing business rules
     *
     ****************************************************************/

contract SystemRules {
    // from dapp example

    function canCashOut(address user) returns(bool);

    function serviceFee() returns(uint128);
}


//contract Gxpctoken is DSAuth, DSMath, DSNote, DSStop {
//contract Gxpctoken is DSMath, DSNote, DSStop {
//contract Gxpctoken is DSThing, DSStop {

contract Gxpctoken is DSThing {
    // from dapp example

    ERC20        deposit;
    DSToken      appToken;
    DSMultiVault multiVault;

    SystemRules rules;

    function cashOut(uint128 wad) {
        assert(rules.canCashOut(msg.sender));

        // Basic idea here is that prize < wad
        // with the contract keeping the difference as a fee.
        // See DS-Math for wdiv docs.

        uint prize = wdiv(wad, rules.serviceFee());

        appToken.pull(msg.sender, wad);

        // only this contract is authorized to burn tokens
        appToken.burn(prize);

        deposit.transfer(msg.sender, prize);
    }

    function newRules(SystemRules rules_) auth {
        rules = rules_;
    }

    // from GXC token

    // Public variables of the token
    string  public name;
    string  public symbol;
    uint8   public decimals; // How many decimals to show.
    string  public version = "v0.1";
    uint    public initialSupply;
    uint    public totalSupply;
    bool    public locked;
    address public crowdSaleAddress;
    uint           multiplier = 10000000000;        
    uint256 public totalMigrated;

    mapping(address => uint) balances;
    mapping(address => mapping(address => uint)) allowed;
    
    // Lock transfer during the ICO
    modifier onlyUnlocked() {
        if (msg.sender != crowdSaleAddress && locked && msg.sender != owner) revert();
        _;
    }

    modifier onlyAuthorized() {
        if ( msg.sender != crowdSaleAddress && msg.sender != owner) revert();
        _;
    }

    // The GXPC Token constructor
    function GXPC(address _crowdSaleAddress) {        
        locked           = true;    // Lock the transfer of tokens during the crowdsale
        initialSupply    = 10000000 * multiplier;
        totalSupply      = initialSupply;
        name             = 'GXPC';  // Set the name for display purposes
        symbol           = 'GXPC';  // Set the symbol for display purposes
        decimals         = 10;      // Amount of decimals for display purposes
        crowdSaleAddress = _crowdSaleAddress;               
        balances[crowdSaleAddress] = totalSupply;       
    }

    function restCrowdSaleAddress(address _newCrowdSaleAddress) onlyAuthorized() {
            crowdSaleAddress = _newCrowdSaleAddress;
    }

    function unlock() onlyAuthorized {
        locked = false;
    }

    function lock() onlyAuthorized {
        locked = true;
    }

    function burn( address _member, uint256 _value) onlyAuthorized returns(bool) {
        //balances[_member] = safeSub(balances[_member], _value);
        balances[_member] = sub(balances[_member], _value);
        //totalSupply       = safeSub(totalSupply, _value);
        totalSupply       = sub(totalSupply, _value);
        // TO DO replace this event by new one
        //Transfer(_member, 0x0, _value);
        return true;
    }

    function transfer(address _to, uint _value) onlyUnlocked returns(bool) {
        //balances[msg.sender] = safeSub(balances[msg.sender], _value);
        balances[msg.sender] = sub(balances[msg.sender], _value);
        //balances[_to]        = safeAdd(balances[_to], _value);
        balances[_to]        = add(balances[_to], _value);
        // TO DO replace this event by new one
        //Transfer(msg.sender, _to, _value);
        return true;
    }

    /* A contract attempts to get the coins */
    function transferFrom(address _from, address _to, uint256 _value) onlyUnlocked returns(bool success) {
        if (balances[_from] < _value) revert(); // Check if the sender has enough
        if (_value > allowed[_from][msg.sender]) revert(); // Check allowance
        //balances[_from]            = safeSub(balances[_from], _value); // Subtract from the sender
        balances[_from]            = sub(balances[_from], _value); // Subtract from the sender
        //balances[_to]              = safeAdd(balances[_to], _value); // Add the same to the recipient
        balances[_to]              = add(balances[_to], _value); // Add the same to the recipient
        //allowed[_from][msg.sender] = safeSub(allowed[_from][msg.sender], _value);
        allowed[_from][msg.sender] = sub(allowed[_from][msg.sender], _value);
        // TO DO replace this event by new one
        //Transfer(_from, _to, _value);
        return true;
    }

    function balanceOf(address _owner) constant returns(uint balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint _value) returns(bool) {
        allowed[msg.sender][_spender] = _value;
        // TO DO replace this event by new one
        //Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns(uint remaining) {
        return allowed[_owner][_spender];
    }

}

