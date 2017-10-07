pragma solidity ^0.4.17;

import "ds-auth/auth.sol";
import "ds-math/math.sol";
import "ds-note/note.sol";
import "ds-token/token.sol";
import "ds-vault/multivault.sol";

contract SystemRules {

    function canCashOut(address user) returns(bool);

    function serviceFee() returns(uint128);
}

contract Gxpctoken is DSAuth, DSMath, DSNote {

    ERC20 deposit;
    DSToken appToken;
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

}

