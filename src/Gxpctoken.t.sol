pragma solidity ^0.4.17;

import "ds-test/test.sol";

import "./Gxpctoken.sol";

contract GxpctokenTest is DSTest {
    Gxpctoken gxpctoken;

    function setUp() {
        gxpctoken = new Gxpctoken();
    }

    function testFail_basic_sanity() {
        assertTrue(false);
    }

    function test_basic_sanity() {
        assertTrue(true);
    }
}
