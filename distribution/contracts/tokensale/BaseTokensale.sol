pragma solidity ^0.8.0;

import "@c-layer/common/contracts/operable/Operable.sol";
import "@c-layer/common/contracts/lifecycle/Pausable.sol";
import "../interface/ITokensale.sol";


/**
 * @title BaseTokensale
 * @dev Base Tokensale contract
 *
 * @author Cyril Lapinte - <cyril.lapinte@openfiz.com>
 * SPDX-License-Identifier: MIT
 *
 * Error messages
 * TOS01: token price must be strictly positive
 * TOS02: price unit must be strictly positive
 * TOS03: Token transfer must be successfull
 * TOS04: No ETH to refund
 * TOS05: Cannot invest 0 tokens
 * TOS06: Cannot invest if there are no tokens to buy
 * TOS07: Only exact amount is authorized
 */
contract BaseTokensale is ITokensale, Operable, Pausable {

  /* General sale details */
  IERC20 internal token_;
  address payable internal vaultETH_;
  address internal vaultERC20_;

  uint256 internal tokenPrice_;
  uint256 internal priceUnit_;

  uint256 internal totalRaised_;
  uint256 internal totalTokensSold_;

  uint256 internal totalUnspentETH_;
  uint256 internal totalRefundedETH_;

  struct Investor {
    uint256 unspentETH;
    uint256 invested;
    uint256 tokens;
  }
  mapping(address => Investor) internal investors;

  /**
   * @dev constructor
   */
  constructor(
    IERC20 _token,
    address _vaultERC20,
    address payable _vaultETH,
    uint256 _tokenPrice,
    uint256 _priceUnit
  ) {
    require(_tokenPrice > 0, "TOS01");
    require(_priceUnit > 0, "TOS02");

    token_ = _token;
    vaultERC20_ = _vaultERC20;
    vaultETH_ = _vaultETH;
    tokenPrice_ = _tokenPrice;
    priceUnit_ = _priceUnit;
  }

  /**
   * @dev fallback function
   */
  //solhint-disable-next-line no-complex-fallback
  receive() external override payable {
    investETH();
  }

  /* Investment */
  function investETH() public virtual override payable
  {
    Investor storage investor = investorInternal(msg.sender);
    uint256 amountETH = investor.unspentETH + msg.value;

    investInternal(msg.sender, amountETH, false);
  }

  /**
   * @dev returns the token sold
   */
  function token() public override view returns (IERC20) {
    return token_;
  }

  /**
   * @dev returns the vault use to
   */
  function vaultETH() public override view returns (address) {
    return vaultETH_;
  }

  /**
   * @dev returns the vault to receive ETH
   */
  function vaultERC20() public override view returns (address) {
    return vaultERC20_;
  }

  /**
   * @dev returns token price
   */
  function tokenPrice() public override view returns (uint256) {
    return tokenPrice_;
  }

  /**
   * @dev returns price unit
   */
  function priceUnit() public override view returns (uint256) {
    return priceUnit_;
  }

  /**
   * @dev returns total raised
   */
  function totalRaised() public override view returns (uint256) {
    return totalRaised_;
  }

  /**
   * @dev returns total tokens sold
   */
  function totalTokensSold() public override view returns (uint256) {
    return totalTokensSold_;
  }

  /**
   * @dev returns total unspent ETH
   */
  function totalUnspentETH() public override view returns (uint256) {
    return totalUnspentETH_;
  }

  /**
   * @dev returns total refunded ETH
   */
  function totalRefundedETH() public override view returns (uint256) {
    return totalRefundedETH_;
  }

  /**
   * @dev returns the available supply
   */
  function availableSupply() public override view returns (uint256) {
    uint256 vaultSupply = token_.balanceOf(vaultERC20_);
    uint256 allowance = token_.allowance(vaultERC20_, address(this));
    return (vaultSupply < allowance) ? vaultSupply : allowance;
  }

  /* Investor specific attributes */
  function investorUnspentETH(address _investor)
    public override view returns (uint256)
  {
    return investorInternal(_investor).unspentETH;
  }

  function investorInvested(address _investor)
    public override view returns (uint256)
  {
    return investorInternal(_investor).invested;
  }

  function investorTokens(address _investor) public override view returns (uint256) {
    return investorInternal(_investor).tokens;
  }

  /**
   * @dev tokenInvestment
   */
  function tokenInvestment(address, uint256 _amount)
    public virtual override view returns (uint256)
  {
    uint256 availableSupplyValue = availableSupply();
    uint256 contribution = _amount * priceUnit_ / tokenPrice_;

    return (contribution < availableSupplyValue) ? contribution : availableSupplyValue;
  }

  /**
   * @dev refund unspentETH ETH many
   */
  function refundManyUnspentETH(address payable[] memory _receivers)
    public override onlyOperator returns (bool)
  {
    for (uint256 i = 0; i < _receivers.length; i++) {
      refundUnspentETHInternal(_receivers[i]);
    }
    return true;
  }

  /**
   * @dev refund unspentETH
   */
  function refundUnspentETH() public override returns (bool) {
    refundUnspentETHInternal(payable(msg.sender));
    return true;
  }

  /**
   * @dev withdraw all ETH funds
   */
  function withdrawAllETHFunds() public override onlyOperator returns (bool) {
    uint256 balance = address(this).balance;
    withdrawETHInternal(balance);
    return true;
  }

  /**
   * @dev fund ETH
   */
  function fundETH() public override payable onlyOperator {
    emit FundETH(msg.value);
  }

  /**
   * @dev investor internal
   */
  function investorInternal(address _investor)
    internal virtual view returns (Investor storage)
  {
    return investors[_investor];
  }

  /**
   * @dev eval unspent ETH internal
   */
  function evalUnspentETHInternal(
    Investor storage _investor, uint256 _investedETH
  ) internal virtual view returns (uint256)
  {
    return _investor.unspentETH + msg.value - _investedETH;
  }

  /**
   * @dev eval investment internal
   */
  function evalInvestmentInternal(uint256 _tokens)
    internal virtual view returns (uint256, uint256)
  {
    uint256 invested = _tokens * tokenPrice_ / priceUnit_;
    return (invested, _tokens);
  }

  /**
   * @dev distribute tokens internal
   */
  function distributeTokensInternal(address _investor, uint256 _tokens)
    internal virtual
  {
    require(
      token_.transferFrom(vaultERC20_, _investor, _tokens),
      "TOS03");
  }

  /**
   * @dev refund unspentETH internal
   */
  function refundUnspentETHInternal(address payable _investor) internal virtual {
    Investor storage investor = investorInternal(_investor);
    require(investor.unspentETH > 0, "TOS04");

    uint256 unspentETH = investor.unspentETH;
    totalRefundedETH_ = totalRefundedETH_ + unspentETH;
    totalUnspentETH_ = totalUnspentETH_ - unspentETH;
    investor.unspentETH = 0;

    // Multiple sends are required for refundManyUnspentETH
    // solhint-disable-next-line multiple-sends
    _investor.transfer(unspentETH);
    emit RefundETH(_investor, unspentETH);
  }

  /**
   * @dev withdraw ETH internal
   */
  function withdrawETHInternal(uint256 _amount) internal virtual {
    // Send is used after the ERC20 transfer
    // solhint-disable-next-line multiple-sends
    vaultETH_.transfer(_amount);
    emit WithdrawETH(_amount);
  }

  /**
   * @dev invest internal
   */
  function investInternal(address _investor, uint256 _amount, bool _exactAmountOnly)
    internal virtual whenNotPaused
  {
    require(_amount != 0, "TOS05");

    Investor storage investor = investorInternal(_investor);
    uint256 investment = tokenInvestment(_investor, _amount);
    require(investment != 0, "TOS06");

    (uint256 invested, uint256 tokens) = evalInvestmentInternal(investment);

    if (_exactAmountOnly) {
      require(invested == _amount, "TOS07");
    } else {
      uint256 unspentETH = evalUnspentETHInternal(investor, invested);
      totalUnspentETH_ = totalUnspentETH_ - investor.unspentETH + unspentETH;
      investor.unspentETH = unspentETH;
    }

    investor.invested = investor.invested + invested;
    investor.tokens = investor.tokens + tokens;
    totalRaised_ = totalRaised_ + invested;
    totalTokensSold_ = totalTokensSold_ + tokens;

    emit Investment(_investor, invested, tokens);

    /* Reentrancy risks: No state change must come below */
    distributeTokensInternal(_investor, tokens);

    uint256 balance = address(this).balance;
    uint256 withdrawableETH = balance - totalUnspentETH_;
    if (withdrawableETH != 0) {
      withdrawETHInternal(withdrawableETH);
    }
  }
}
