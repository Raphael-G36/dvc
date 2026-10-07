// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib, ERC4626, ERC20} from "solmate/tokens/ERC4626.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC3156FlashBorrower, IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156.sol";

/**
 * An ERC4626-compliant tokenized vault offering flashloans for a fee.
 * An owner can pause the contract and execute arbitrary changes.
 */
contract UnstoppableVault is
    IERC3156FlashLender,
    ReentrancyGuard,
    Owned,
    ERC4626,
    Pausable
{
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    uint256 public constant FEE_FACTOR = 0.05 ether;
    uint64 public constant GRACE_PERIOD = 30 days;

    //@question is this even allowed, a uint 64 can hold the summation of uint 64 and uint 64 without causing an overflow.
    uint64 public immutable end = uint64(block.timestamp) + GRACE_PERIOD;

    address public feeRecipient;

    error InvalidAmount(uint256 amount);
    error InvalidBalance();
    error CallbackFailed();
    error UnsupportedCurrency();

    event FeeRecipientUpdated(address indexed newFeeRecipient);

    constructor(
        ERC20 _token,
        address _owner,
        address _feeRecipient
    ) ERC4626(_token, "Too Damn Valuable Token", "tDVT") Owned(_owner) {
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /**
     * @inheritdoc IERC3156FlashLender
     */
    //@note setting maximum flash loan the vault can release.
    function maxFlashLoan(
        address _token
    ) public view nonReadReentrant returns (uint256) {
        if (address(asset) != _token) {
            //@question  why are we returning 0 and not an error or sth else.
            return 0;
        }
        //@note returning the total underling ERC-20 token assets in the vault as the maximum flash loan amount.
        return totalAssets();
    }

    /**
     * @inheritdoc IERC3156FlashLender
     */
    function flashFee( address _token, uint256 _amount ) public view returns (uint256 fee) {
        if (address(asset) != _token) {
            revert UnsupportedCurrency();
        }
        //@question why are we checking the block timestamp and the end variable is already using block.timestamp. can the is the time stamp be thesame as the end variable block time stamp.
        if (block.timestamp < end && _amount < maxFlashLoan(_token)) {
            return 0;
        } else {
            // @ what is this mulWadUp function?
            return _amount.mulWadUp(FEE_FACTOR);
        }
    }

    /**
     * @inheritdoc ERC4626
     */
    // @question what is the purpose of this function? The purpose of the totalAssets function is to provide a way to retrieve the total amount of underlying assets held by the vault. It returns the balance of the underlying asset (ERC-20 token) that the vault manages. This function is marked as nonReadReentrant to prevent reentrancy attacks, ensuring that it cannot be called in a way that would allow for unexpected behavior or manipulation of the vault's state during its execution.
    function totalAssets()
        public
        view
        override
        nonReadReentrant
        returns (uint256)
    {
        return asset.balanceOf(address(this));
    }
    /**
     * @inheritdoc IERC3156FlashLender
     */
    // @note from my Research: The entry point function that triggers the loan. It sends the tokens to the borrower, calls the borrower's execution code, and checks that the money came back.

    //@note Main function to study: flashLoan() is the entry point function that triggers the loan. It sends the tokens to the borrower, calls the borrower's execution code, and checks that the money came back.
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address _token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        //@question can i enter a negative amount? if yes, what will happen?
        if (amount == 0) revert InvalidAmount(0); // fail early

        if (address(asset) != _token) revert UnsupportedCurrency(); // enforce ERC3156 requirement
        // @note totalAssets() is the total amount of underlying assets(The main ERC-20 token like ETH or DVT or any other ERC-20 token) in the vault.
        // @note convertToShares(totalSupply) is the total amount of shares in the vault.
        uint256 balanceBefore = totalAssets();
        // @question where is totalSupply coming from? totalSupply is a function in ERC4626 that returns the total amount of shares in the vault. Does this include those that have been issued already?

        //@note they are asuming this works at a ratio of 1:1
        if (convertToShares(totalSupply) != balanceBefore)
            revert InvalidBalance(); // enforce ERC4626 requirement

        // transfer tokens out + execute callback on receiver
        ERC20(_token).safeTransfer(address(receiver), amount);

        // @note from research flashFee() caculates how much the borrower has to payback to the vault.

        // callback must return magic value, otherwise assume it failed
        uint256 fee = flashFee(_token, amount);

        // @question what is this condition checking for?
        if (
            receiver.onFlashLoan(
                msg.sender,
                address(asset),
                amount,
                fee,
                data
            ) != keccak256("IERC3156FlashBorrower.onFlashLoan")
        ) {
            revert CallbackFailed();
        }

        // @question who is the recipent in this scenario? the feeRecepient is an empty address for now, it hasn't been used since decleration
        // pull amount + fee from receiver, then pay the fee to the recipient
        ERC20(_token).safeTransferFrom(
            address(receiver),
            address(this),
            amount + fee
        );
        // @question can the feeRecipient be changed by anyone? if no, what makes it so?
        // @question the feeRecipient could be another contract yes, how does that affect this ?
        ERC20(_token).safeTransfer(feeRecipient, fee);

        return true;
    }

    /**
     * @inheritdoc ERC4626
     */
    //@question what is the purpose of this function? The purpose of the beforeWithdraw function is to provide a hook that can be overridden in derived contracts to implement custom logic that should be executed before a withdrawal occurs. In this specific implementation, it is marked as nonReentrant to prevent reentrancy attacks, but it does not contain any additional logic. Derived contracts can override this function to add checks, restrictions, or other behaviors that should occur before the withdrawal process is completed.
    function beforeWithdraw(
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant {}

    /**
     * @inheritdoc ERC4626
     */
    //@question what is the purpose of this function? The purpose of the afterDeposit function is to provide a hook that can be overridden in derived contracts to implement custom logic that should be executed after a deposit occurs. In this specific implementation, it is marked as nonReentrant to prevent reentrancy attacks, but it does not contain any additional logic. Derived contracts can override this function to add checks, restrictions, or other behaviors that should occur after the deposit process is completed.
    function afterDeposit(
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant whenNotPaused {}

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient != address(this)) {
            feeRecipient = _feeRecipient;
            emit FeeRecipientUpdated(_feeRecipient);
        }
    }

    // Allow owner to execute arbitrary changes when paused
    function execute(
        address target,
        bytes memory data
    ) external onlyOwner whenPaused {
        (bool success, ) = target.delegatecall(data);
        require(success);
    }

    //@question What do you mean by "pausing/unpausing"? In the context of smart contracts, "pausing" refers to temporarily disabling certain functionalities of the contract, usually for security reasons or during maintenance. When a contract is paused, specific functions (like deposits or withdrawals) may be restricted to prevent potential exploits or issues. Conversely, "unpausing" re-enables those functionalities, allowing users to interact with the contract as normal. In this code snippet, the `setPause` function allows the owner to control whether the contract is paused or unpaused.

    // Allow owner pausing/unpausing this contract.

    // How does this pause logic work? The pause logic is implemented using the `Pausable` contract from OpenZeppelin. When the `setPause` function is called with `true`, it invokes the `_pause()` function, which sets a state variable indicating that the contract is paused. This state variable is checked in functions that are marked with the `whenNotPaused` modifier, preventing their execution while the contract is paused. Conversely, calling `setPause` with `false` invokes `_unpause()`, which resets the state variable, allowing those functions to be executed again.

    function setPause(bool flag) external onlyOwner {
        if (flag) _pause();
        else _unpause();
    }
}
