// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../contexts/Manageable.sol";
import "../interfaces/IBEP20.sol";
import "../interfaces/IPancakeFactory.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IPancakeRouter02.sol";
import "./TokenDividendTracker.sol";

contract MjCoin is IBEP20, Manageable {
    using SafeMath for uint256;

    uint256 private _total = 13141 * 10**18;

    uint256 private _numTokensSellToAddToLiquidity = 1 * 10**17;


    uint8 private _decimal = 18;
    string private _name = "MJ";
    string private _symbol = "MJ";

    address private _adminAddress = 0x8B658528ED776Ba40F0cb30e5934d1F5a846a775;

    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _tAllowances;

    uint256 public _buyFeeManagementPercentage = 2; // foundation
    uint256 public _buyBurnFeePercentage = 1;
    uint256 public _buyFeePoolPercentage = 1; // pool

    uint256 public _sellFeeManagementPercentage = 3; // foundation
    uint256 public _sellFeePoolPercentage = 1; // pool

    bool swapAndLiquifyEnabled = true;
    bool inSwapAndLiquify;
    
    address private _manage1 = 0x93ee919F6B15658b0c51e1D78c2E1521eB9ACe63;
    //address private _manage2 = 0xE9979F3140C44B55c4b68709387B9111D2CD4702;
    address private _manage3 = 0x36c6f322316D4bc7CFa2A4435B7c096bC83E82E8;
    address private _manage4 = 0x0409Eb6B3382526E7D842aDD7443366FD8C1ca50;
    address private _manage5 = 0x6B84A2Ef6d6cf4c44A206fe08BCc66F3955FE8fC;
    address private _manage6 = 0xaA8fc54D7a875bBf7d2493F411a14C960639ea0e;
    address private _manage7 = 0xc09227C0dd7D1A0977F0624C5264903d85F43817;

    uint256 private _manage1fee = 30;
    //uint256 private _manage2fee = 20;
    uint256 private _manage3fee = 30;
    uint256 private _manage4fee = 15;
    uint256 private _manage5fee = 10;
    uint256 private _manage6fee = 10;
    uint256 private _manage7fee = 5;
    
    uint256 public _totalFeeRatio = 100;

    mapping(address => bool) private _isExcludedFromFees;
    mapping (address => bool) _isDividendExempt;

    TokenDividendTracker public _dividendTracker;

    IPancakeRouter02 public _pancakeRouter;
    IPancakePair public _pancakePair;

    uint256 public minPeriod = 86400;
    uint256 distributorGas = 200000;

    address private _fromAddress;
    address private _toAddress;

    uint256 public _AmountLiquidityFee = 0;
    uint256 public _AmountLpRewardFee  = 0; 

    mapping(address => bool) public _automatedMarketMakerPairs;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );


    constructor(address pancakeRouter) {
        _pancakeRouter = IPancakeRouter02(pancakeRouter);
        _pancakePair = IPancakePair(
            IPancakeFactory(_pancakeRouter.factory()).createPair(
                _contextAddress(),
                _pancakeRouter.WETH()
            )
        );

        _dividendTracker = new TokenDividendTracker(address(_pancakePair));
        _setAutomatedMarketMakerPair(address(_pancakePair), true);

        _isExcludedFromFees[_contextAddress()] = true;
        _isExcludedFromFees[_msgSender()] = true;
        _isExcludedFromFees[_adminAddress] = true;
        // _isExcludedFromFees[_manage1] = true;
        // _isExcludedFromFees[_manage3] = true;
        // _isExcludedFromFees[_manage4] = true;
        // _isExcludedFromFees[_manage5] = true;
        // _isExcludedFromFees[_manage6] = true;
        // _isExcludedFromFees[_manage7] = true;

        _isDividendExempt[_contextAddress()] = true;
        _isDividendExempt[address(0)] = true;
        _isDividendExempt[address(_dividendTracker)] = true;


        //addManager(_adminAddress);
        _tOwned[_msgSender()] = _total;
        emit Transfer(address(0), _msgSender(), _total);
    }

    function totalSupply() external view returns (uint256) {
        return _total;
    }


    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _tOwned[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");

        _total -= amount;

        emit Transfer(account, address(0), amount);
    }

    function decimals() external view returns (uint8) {
        return _decimal;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function getOwner() external view returns (address) {
        return executiveManager();
    }

    function balanceOf(address account) external view returns (uint256) {
        return _tOwned[account];
    }

    function pancake_pair() public view returns (address) {
        return address(_pancakePair);
    }

    function _transfer(
        address from,
        address to,
        uint256 tAmount
    ) private {
        require(
            from != address(0) && to != address(0),
            "cannot transfer tokens from or to the zero address"
        );

        if (tAmount == 0) {
            return;
        }

        uint256 fromAccountTBalance = _tOwned[from];
        require(
            fromAccountTBalance >= tAmount,
            "insufficent from account token balance"
        );

        uint256 contractTokenBalance = _tOwned[address(this)];

        bool overMinTokenBalance = contractTokenBalance >=
            _numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != address(_pancakePair) &&
            swapAndLiquifyEnabled
        ) {
            swapAndLiquify(contractTokenBalance);
            if(_AmountLiquidityFee > 0){
                swapAndLiquify(_AmountLiquidityFee);
                _AmountLiquidityFee = 0;
            }
            if(_AmountLpRewardFee > 0){
                swapLPRewardToken(_AmountLpRewardFee);
                _AmountLpRewardFee = 0;
            }
        }

        uint256 tManagementFeeAmount = 0;
        uint256 tReflectionsFeeAmount = 0;
        uint256 tBurnFeeAmount = 0;
        bool takefee = true;
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takefee = false;
        }

        if (takefee) {
            if (_automatedMarketMakerPairs[from]) {
                tBurnFeeAmount = tAmount.mul(_buyBurnFeePercentage).div(_totalFeeRatio);
                tManagementFeeAmount = tAmount.mul(_buyFeeManagementPercentage).div(_totalFeeRatio);
            }
            if (_automatedMarketMakerPairs[to]) {
                tManagementFeeAmount = tAmount.mul(_sellFeeManagementPercentage).div(_totalFeeRatio);
                tReflectionsFeeAmount = tAmount.mul(_sellFeePoolPercentage).div(_totalFeeRatio);
            }
        }

        uint256 tTransferAmount = tAmount
            .sub(tManagementFeeAmount)
            .sub(tBurnFeeAmount)
            .sub(tReflectionsFeeAmount);

        _takeburnFee(from,tBurnFeeAmount);
        _takeLPFee(from, tReflectionsFeeAmount);
        _takeManageFee(from, tManagementFeeAmount);

        _tOwned[from] = _tOwned[from].sub(tAmount);
        _tOwned[to] += tTransferAmount;

        emit Transfer(from, to, tTransferAmount);

        if(_fromAddress == address(0) )_fromAddress = from;
        if(_toAddress == address(0) )_toAddress = to;  
        if(!_isDividendExempt[_fromAddress] && _fromAddress != address(_pancakePair) )   try _dividendTracker.setShare(_fromAddress) {} catch {}
        if(!_isDividendExempt[_toAddress] && _toAddress != address(_pancakePair) ) try _dividendTracker.setShare(_toAddress) {} catch {}
        _fromAddress = from;
        _toAddress = to;

       if(!overMinTokenBalance && 
            from != _contextAddress() &&
            to != _contextAddress() &&
            from !=address(this) &&
            _dividendTracker.LPRewardLastSendTime().add(minPeriod) <= block.timestamp
        ) {
            try _dividendTracker.process(distributorGas) {} catch {}    
        }
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }

    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return _tAllowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 tAmount
    ) private {
        require(
            owner != address(0),
            "cannot approve allwoance from the zero address"
        );
        require(
            spender != address(0),
            "cannot approve allwoance to the zero address"
        );

        _tAllowances[owner][spender] = tAmount;
        emit Approval(owner, spender, tAmount);
    }

    function transferFrom(
        address sender,
        address to,
        uint256 amount
    ) external returns (bool) {
        _transfer(sender, to, amount);
        _approve(
            sender,
            _msgSender(),
            _tAllowances[sender][_msgSender()].sub(
                amount,
                "transfer amount exceeds spender's allowance"
            )
        );
        return true;
    }

    function _takeburnFee(address sender, uint256 tAmount) private {
        if (tAmount == 0) return;
        _burn(sender, tAmount);
    }

    function _takeManageFee(address sender, uint256 tAmount) private {
        if (tAmount <= 0) return;

        uint256 m1fee = tAmount.mul(_manage1fee).div(100);
        _tOwned[_manage1] = _tOwned[_manage1].add(m1fee);
        emit Transfer(sender, _manage1, m1fee);

        // uint256 m2fee = tAmount.mul(_manage2fee).div(100);
        // _tOwned[_manage2] = _tOwned[_manage2].add(m2fee);
        // emit Transfer(sender, _manage2, m2fee);

        uint256 m3fee = tAmount.mul(_manage3fee).div(100);
        _tOwned[_contextAddress()] = _tOwned[_contextAddress()].add(m3fee);
        _AmountLpRewardFee = _AmountLpRewardFee.add(m3fee);   
        emit Transfer(sender, _contextAddress(), m3fee);

        uint256 m4fee = tAmount.mul(_manage4fee).div(100);
        _tOwned[_manage4] = _tOwned[_manage4].add(m4fee);
        emit Transfer(sender, _manage4, m4fee);

        uint256 m5fee = tAmount.mul(_manage5fee).div(100);
        _tOwned[_manage5] = _tOwned[_manage5].add(m5fee);
        emit Transfer(sender, _manage5, m5fee);

        uint256 m6fee = tAmount.mul(_manage6fee).div(100);
        _tOwned[_manage6] = _tOwned[_manage6].add(m6fee);
        emit Transfer(sender, _manage6, m6fee);

        uint256 m7fee = tAmount.mul(_manage7fee).div(100);
        _tOwned[_manage7] = _tOwned[_manage7].add(m7fee);
        emit Transfer(sender, _manage7, m7fee);
        return;
    }


    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _pancakeRouter.WETH();

        _approve(address(this), address(_pancakeRouter), tokenAmount);

        // make the swap
        _pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(_pancakeRouter), tokenAmount);

        // add the liquidity
        _pancakeRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );
    }

    function swapLPRewardToken(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _pancakeRouter.WETH();
        _approve(address(this), address(_pancakeRouter), tokenAmount);
        _pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(_dividendTracker),
            block.timestamp
        );
    }

    function _takeLPFee(address sender, uint256 tAmount) private {
        if (tAmount <= 0) return;
        _tOwned[_contextAddress()] = _tOwned[_contextAddress()].add(tAmount);
        _AmountLiquidityFee = _AmountLiquidityFee.add(tAmount);    
        emit Transfer(sender, _contextAddress(), tAmount);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            _automatedMarketMakerPairs[pair] != value,
            "RedCheCoin Automated market maker pair is already set to that value"
        );
        _automatedMarketMakerPairs[pair] = value;
    }

    function excludedFromFees(address account, bool value)
        external
        onlyManagement
    {
        _isExcludedFromFees[account] = value;
    }
}
