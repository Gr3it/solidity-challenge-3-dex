// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/Math.sol";
import "./LPToken.sol";

contract DEX is LPToken, Ownable {
    IERC20 public immutable token;
    uint256 public fee = 997; //on fee/1000 basis

    constructor(address token_addr) LPToken("LP-Token", "LP") {
        token = IERC20(token_addr);
    }

    event EthToTokenSwap(
        address swapperAddress,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    event TokenToEthSwap(
        address swapperAddress,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    event LiquidityProvided(
        address provider,
        uint256 LPToken,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    event LiquidityRemoved(
        address provider,
        uint256 LPToken,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    function init(uint256 tokens) public payable returns (uint256) {
        require(msg.value > 0, "cannot init with 0 ETH");
        require(tokens > 0, "cannot init with 0 BALL");
        require(totalSupply == 0, "Contract has already liquidity");

        require(
            token.transferFrom(msg.sender, address(this), tokens),
            "Transfer of token failed"
        );

        uint256 liquidity = Math.sqrt(msg.value * tokens);

        require(liquidity > 0, "Insufficend liquidity minted");

        _mint(msg.sender, liquidity);

        return liquidity;
    }

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "Insufficent found");
        require(reserveA > 0 && reserveB > 0, "insufficent liquidity");
        amountB = (amountA * reserveB) / reserveA;
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public view returns (uint256 amountOut) {
        require(amountIn > 0, "Insufficent found");
        require(reserveIn > 0 && reserveOut > 0, "insufficent liquidity");
        uint256 amountInWithFee = amountIn * fee;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public view returns (uint256 amountIn) {
        require(amountOut > 0, "Insufficent found");
        require(reserveIn > 0 && reserveOut > 0, "insufficent liquidity");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * fee;
        amountIn = (numerator / denominator) + 1;
    }

    function ethToToken() public payable returns (uint256 tokenOutput) {
        require(msg.value > 0, "cannot swap 0 ETH");

        uint256 ethBalance = address(this).balance - (msg.value);
        uint256 tokenBalance = token.balanceOf(address(this));

        uint256 amount = getAmountOut(msg.value, ethBalance, tokenBalance);
        require(token.transfer(msg.sender, amount), "transfer reverted");
        emit EthToTokenSwap(msg.sender, msg.value, amount);
        return amount;
    }

    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        require(tokenInput > 0, "cannot swap 0 BALL");

        uint256 ethBalance = address(this).balance;
        uint256 tokenBalance = token.balanceOf(address(this));

        require(
            token.transferFrom(msg.sender, address(this), tokenInput),
            "Transfer of token failed"
        );

        uint256 amount = getAmountOut(tokenInput, tokenBalance, ethBalance);
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Fail transfer of eth to account");
        emit TokenToEthSwap(msg.sender, tokenInput, amount);
        return amount;
    }

    function deposit(uint256 tokenAmount)
        public
        payable
        returns (uint256 tokensDeposited)
    {
        require(tokenAmount > 0, "0 token");
        require(msg.value > 0, "0 eth value");

        uint256 tokenBalance = token.balanceOf(address(this));
        uint256 ethBalance = address(this).balance - msg.value;

        uint256 liquidity = Math.min(
            (msg.value * totalSupply) / ethBalance,
            (tokenAmount * totalSupply) / tokenBalance
        );

        require(liquidity > 0, "0 liquidity");

        require(
            token.transferFrom(msg.sender, address(this), tokenAmount),
            "Transfer of token failed"
        );

        _mint(msg.sender, liquidity);

        emit LiquidityProvided(msg.sender, liquidity, msg.value, tokenAmount);
        return liquidity;
    }

    function withdraw(uint256 amount)
        public
        returns (uint256 eth_amount, uint256 token_amount)
    {
        require(balanceOf[msg.sender] >= amount, "Not enough funds");

        uint256 tokenBalance = token.balanceOf(address(this));
        uint256 ethBalance = address(this).balance;

        uint256 ethAmount = (amount * ethBalance) / totalSupply;
        uint256 tokenAmount = (amount * tokenBalance) / totalSupply;

        _burn(msg.sender, amount);

        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "withdraw(): revert in transferring eth to you!");
        require(token.transfer(msg.sender, tokenAmount));
        emit LiquidityRemoved(msg.sender, amount, ethAmount, tokenAmount);
        return (ethAmount, tokenAmount);
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }
}
