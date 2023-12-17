
// SPDX-License-Identifier: NI

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Callee.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Router01.sol";
import "./IUniswapV2Pair.sol";
import "./UniswapV2Library.sol";
import "./IERC20.sol";
import "./TransferHelper.sol";

pragma solidity ^0.8.23;

contract manualFlashSwapper is IUniswapV2Callee {
    enum SwapType {
        SimpleLoan,
        SimpleSwap,
        flashSwap,
        TriangularSwap,
        None
    }

    address constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    address public uniswapFactory;
    IUniswapV2Factory public factoryContract;

    address public tokenChanger;//ignore this

    IUniswapV2Router02 public furstRouter;
    IUniswapV2Router02 public sekkendRouter;

    uint constant deadline = 10 minutes;

    address private _permissionedPairAddress = address(0);
    address private _permissionedSender = address(0);

    // but it's not possible because it requires a call to the v1 factory, which takes too much gas
    receive() external payable {}

    function swapSomeByHand(
        address routerUni,
        address routerSushi,
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) external {
        _permissionedSender = msg.sender;

        furstRouter = IUniswapV2Router02(routerUni);
        sekkendRouter = IUniswapV2Router02(routerSushi);
        uniswapFactory = IUniswapV2Router02(routerUni).factory();

        factoryContract = IUniswapV2Factory(uniswapFactory);

        //        if (tokenChanger == address(0)) {
        flashLoan(tokenIn, amount, tokenOut);
        //            return;
        //        }
        //        if (tokenChanger == WETH) {
        //            flashSwap(tokenIn, amount, tokenOut,);
        //            return;
        //        }
        //        traingularFlashSwap(tokenIn, amount, tokenOut);
    }

    //todo below needs fix, dont use it

    function swapSomeV2flash(
    address routerUni,
    address routerSushi,
    address tokenIn,
    address tokenOut,
    uint256 amount
   
) external {
    _permissionedSender = msg.sender;

    furstRouter = IUniswapV2Router02(routerUni);
    sekkendRouter = IUniswapV2Router02(routerSushi);
    uniswapFactory = IUniswapV2Router02(routerUni).factory();

    factoryContract = IUniswapV2Factory(uniswapFactory);


    if (tokenChanger == address(0)) {
        flashLoan(tokenIn, amount, tokenOut);
        return;
    }
    if (tokenChanger == WETH) {
    //    flashSwap(tokenIn, amount, tokenOut);
        return;
    }
   // triangularFlashSwap(tokenIn, amount, tokenOut);
}

function setTokenChanger(address _tokenChanger) external {
        // ignore this
        tokenChanger = _tokenChanger;
    }


    function getAmountOutMin(
        address router,
        address _tokenIn,
        address _tokenOut,
        uint256 _amount
    ) public view returns (uint256) {
        address[] memory path;
        path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint256[] memory amountOutMins = IUniswapV2Router02(router)
            .getAmountsOut(_amount, path);
        return amountOutMins[path.length - 1];
    }

    function estimateDualDexTrade(
        address _router1,
        address _router2,
        address _token1,
        address _token2,
        uint256 _amount
    ) external view returns (uint256) {
        uint256 amtBack1 = getAmountOutMin(_router1, _token1, _token2, _amount);
        uint256 amtBack2 = getAmountOutMin(
            _router2,
            _token2,
            _token1,
            amtBack1
        );
        return amtBack2;
    }

    function flashLoan(
        address tokenIn,
        uint256 amount,
        address tokenOut
    ) private {
        _permissionedPairAddress = factoryContract.getPair(tokenIn, tokenOut);
        address pairAddress = _permissionedPairAddress; // gas efficiency
        require(
            pairAddress != address(0),
            "Requested _token is not available."
        );
        address token0 = IUniswapV2Pair(pairAddress).token0();
        address token1 = IUniswapV2Pair(pairAddress).token1();
        uint256 amount0Out = tokenIn == token0 ? amount : 0;
        uint256 amount1Out = tokenIn == token1 ? amount : 0;
        bytes memory data = abi.encode(SwapType.SimpleLoan, new bytes(0));
        IUniswapV2Pair(pairAddress).swap(
            amount0Out,
            amount1Out,
            address(this),
            data
        );
    }

    // @notice Function is called by the Uniswap V2 pair's `swap` function
    // interal version that executes all similar calls(external ver name needed for call)
    function _uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) internal {
        require(sender == address(this), "only this contract may initiate");

        // decode data
        (SwapType _swapType, bytes memory _otherData) = abi.decode(
            data,
            (SwapType, bytes)
        );

        if (_swapType == SwapType.None) {
            return;
        }

        assert(msg.sender == _permissionedPairAddress);

        if (_swapType == SwapType.SimpleLoan) {
            flashLoanExecute(amount0, amount1, _otherData);
            return;
        }
        if (_swapType == SwapType.SimpleSwap) {
            //            flashSwapExecute(_tokenBorrow, _amount, _tokenPay, msg.sender, _isBorrowingEth, _isPayingEth);
            return;
        }
        //        traingularFlashSwapExecute(_tokenBorrow, _amount, _tokenPay, _triangleData);
    }

    function flashLoanExecute(
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) private {
        address pair = _permissionedPairAddress;
        uint256 _amountTokenIn;
        address[] memory _pathOut = new address[](2);
        address[] memory _pathIn = new address[](2);
        {
            // scope for token{0,1}, avoids stack too deep errors
            address token0 = IUniswapV2Pair(pair).token0();
            address token1 = IUniswapV2Pair(pair).token1();
            assert(amount0 == 0 || amount1 == 0); // this strategy is unidirectional
            _pathOut[0] = amount0 == 0 ? token1 : token0;
            _pathOut[1] = amount0 == 0 ? token0 : token1;
            _pathIn[0] = amount0 == 0 ? token0 : token1;
            _pathIn[1] = amount0 == 0 ? token1 : token0;
            _amountTokenIn = amount0 == 0 ? amount1 : amount0;
        }

        assert(data.length == 0);

        TransferHelper.safeApprove(
            _pathOut[0],
            address(sekkendRouter),
            _amountTokenIn
        );
        uint amountRequired = furstRouter.getAmountsIn(_amountTokenIn, _pathIn)[
            0
        ];
        uint amountReceived = sekkendRouter.swapExactTokensForTokens(
            _amountTokenIn,
            0,
            _pathOut,
            address(this),
            block.timestamp + deadline
        )[1];
        require(amountReceived > amountRequired, "profit < 0"); // fail if we didn't get enough tokens back to repay our flash loan
        TransferHelper.safeTransfer(_pathOut[1], address(pair), amountRequired); // return tokens to V2 pair
        TransferHelper.safeTransfer(
            _pathOut[1],
            _permissionedSender,
            amountReceived - amountRequired
        ); // keep the rest! (tokens)
    }

    //called by the Uniswap V2 pair's `swap` function
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        _uniswapV2Call(sender, amount0, amount1, data);
    }

    //same as uniV2Call but for pancake clones
    function router2Call(
        address _sender,
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external {
        _uniswapV2Call(_sender, _amount0, _amount1, _data);
    }

    // same as uniV2Call but for pancake clones
    function router3Call(
        address _sender,
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external {
        _uniswapV2Call(_sender, _amount0, _amount1, _data);
    }

    // quickswap: 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff
    // matcha0x: 0xDef1C0ded9bec7F1a1670819833240f027b25EfF
    // uniUniversal: 0x4C60051384bd2d3C01bfc845Cf5F4b44bcbE9de5
    // wmatic 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
    // wban-0xe20B9e246db5a0d21BF9209E4858Bc9A3ff7A034
    // curve-0x172370d5Cd63279eFa6d502DAB29171933a610AF
    // weth 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619

    // -------

    // arbi-
    //weth-0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
    // usdc-0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
    // gmx-0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a
    // oreo-0x38eEd6a71A4ddA9d7f776946e3cfa4ec43781AE6
    // wbtc-0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f

    // alien-0x863e9610E9E0C3986DCc6fb2cD335e11D88f7D5f
    //sushi router-0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
    //camelot- 0xc873fEcbd354f5A56E00E710B90EF4201db2448d
}
