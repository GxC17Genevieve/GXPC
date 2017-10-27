pragma solidity ^0.4.17;

import "ds-test/test.sol";

import "./GXPC.sol";

contract GXPCtest is DSTest {
    GXPC gxpc;

    function setUp() {
        gxpc = new GXPC(0xd98a157F2DfBb7c8b3B2470acF9283FADF76BD2a);
    }

    function testFail_basic_sanity() {
        assertTrue(false);
    }

    function test_basic_sanity() {
        assertTrue(true);
    }
}
