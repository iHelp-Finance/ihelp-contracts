// SPDX-License-Identifier: GPL-3.0
// prettier-ignore

pragma solidity ^ 0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {PRBMathUD60x18} from "@prb/math/contracts/PRBMathUD60x18.sol";

import "../utils/IERC20.sol";

import "./charitypools/CharityPool.sol";

import "hardhat/console.sol";

contract iHelpToken is ERC20CappedUpgradeable, OwnableUpgradeable {
    using PRBMathUD60x18 for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /** Keep track of the current processing state

        Status Meaning:

        -- 0 --> Must run dripStage1 until status changes to 1
        -- 1 --> Must run dripStage2 , changes status to 2 or 3
        -- 2 --> must run dripStage3 1 until status changes to 3
        -- 3 --> must run dripStage4 1 until status changes to 4
        -- 4 --> must run dump()  until status changes to 0
        
     */
    struct ProcessingState {
        uint256 newInterestUS;
        uint256 totalCharityPoolContributions;
        uint256 tokensToCirculate;
        uint256 tokensToCirculateInCurrentPhase;
        uint256 i;
        uint256 ii;
        uint256 status;
    }

    address public operator;
    address public stakingPool;
    address public developmentPool;
    address public holdingPool;

    // Processing gas limit
    uint256 public __processingGasLimit;

    uint256 public __totalCirculating;
    uint256 public __totalSupply;
    uint256 public __tokenPhase;
    uint256 public __interestGenerated;
    uint256 public __tokensLastDripped;
    uint256 public __tokensMintedPerPhase;
    uint256 public __lastProcessedInterestUSD;

    uint256 public developmentShareOfInterest;
    uint256 public stakingShareOfInterest;
    uint256 public charityShareOfInterest;

    mapping(uint256 => uint256) public __tokensPerInterestByPhase;
    mapping(uint256 => uint256) public __cumulativeInterestByPhase;

    mapping(address => uint256) public contributorTokenClaims;
    mapping(address => uint256) public charityInterestShare;
    mapping(address => uint256) public claimableCharityInterest;
    // map the charity pool address to the underlying token
    mapping(address => CharityPool) public __charityPoolRegistry;

    EnumerableSet.AddressSet private charityPoolList;
    ProcessingState public processingState;
    IERC20 public underlyingToken;

    function setTokenPhases() internal {
        uint256 numberPhases = 20;

        uint256 lastInterest = 600000;
        uint256 cumulativeInterest = 0;
        uint256 lastCumulative = 0;

        for (uint256 phase = 1; phase <= numberPhases; phase++) {
            if (phase == 1) {
                lastInterest = lastInterest;
            } else {
                lastInterest = lastInterest * 2;
            }

            cumulativeInterest += lastInterest;
            __cumulativeInterestByPhase[phase] = cumulativeInterest;
            __tokensPerInterestByPhase[phase] = __tokensMintedPerPhase.div(cumulativeInterest - lastCumulative);

            lastCumulative = cumulativeInterest;
        }
    }

    function setProcessiongState(
        uint256 newInterestUS,
        uint256 totalCharityPoolContributions,
        uint256 tokensToCirculate,
        uint256 tokensToCirculateInCurrentPhase,
        uint256 i,
        uint256 ii,
        uint256 status
    ) public onlyOperatorOrOwner {
        processingState.newInterestUS = newInterestUS;
        processingState.totalCharityPoolContributions = totalCharityPoolContributions;
        processingState.tokensToCirculate = tokensToCirculate;
        processingState.tokensToCirculateInCurrentPhase = tokensToCirculateInCurrentPhase;
        processingState.i = i;
        processingState.ii = ii;
        processingState.status = status;
    }

    function transferOperator(address newOperator) public virtual onlyOperatorOrOwner {
        require(newOperator != address(0), "Ownable: new operator is the zero address");
        _transferOperator(newOperator);
    }

    function _transferOperator(address newOperator) internal virtual {
        operator = newOperator;
    }

    modifier onlyOperatorOrOwner() {
        require(msg.sender == operator || msg.sender == owner(), "Funding/is-operator-or-owner");
        _;
    }

    function postUpgrade() external {}

    function initialize(
        string memory _name,
        string memory _symbol,
        address _operator,
        address _stakingPool,
        address _developmentPool,
        address _holdingPool,
        address _underlyingToken
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Capped_init_unchained(20000000 * 1000000000000000000);
        __Ownable_init();

        console.log("Initializing iHelp Token Contract...");

        operator = _operator;
        stakingPool = _stakingPool;
        developmentPool = _developmentPool;
        holdingPool = _holdingPool;
        underlyingToken = IERC20(_underlyingToken);

        __tokensMintedPerPhase = 1000000;

        // scale these later in the contract based on the charity pool decicals
        developmentShareOfInterest = 0.10 * 1e18;
        stakingShareOfInterest = 0.10 * 1e18;
        charityShareOfInterest = 0.80 * 1e18;

        __totalSupply = __tokensMintedPerPhase * 1e18;
        __totalCirculating = 0;

        __tokenPhase = 1;

        __lastProcessedInterestUSD = 0;
        __tokensLastDripped = 0;

        setTokenPhases();

        // mint the initial HELP phase and premine tokens
        _mint(operator, __tokensMintedPerPhase * 1e18);

        uint256 premineTokens = 7000000;
        _mint(_developmentPool, premineTokens * 1e18);

        __processingGasLimit = 300_000 * 1e9;
    }

    function tokenPhase() public view returns (uint256) {
        return __tokenPhase;
    }

    function interestGenerated() public view returns (uint256) {
        return __interestGenerated;
    }

    function tokensMintedPerPhase() public view returns (uint256) {
        return __tokensMintedPerPhase;
    }

    function currentTokensPerInterest() public view returns (uint256) {
        return __tokensPerInterestByPhase[__tokenPhase];
    }

    function tokensPerInterestByPhase(uint256 phase) public view returns (uint256) {
        return __tokensPerInterestByPhase[phase];
    }

    function interestPerTokenByPhase(uint256 phase) public view returns (uint256) {
        return __cumulativeInterestByPhase[phase].div(__tokensMintedPerPhase);
    }

    function setTokenPhase(uint256 phase) public onlyOperatorOrOwner returns (uint256) {
        console.log("setting token phase", phase);
        __tokenPhase = phase;
        return __tokenPhase;
    }

    function registerCharityPool(address _addr) public onlyOperatorOrOwner returns (address) {
        require(_addr != address(0), "Charity pool cannot be null");
        if (address(__charityPoolRegistry[_addr]) == address(0)) {
            console.log("Registering Charity:", _addr);
            __charityPoolRegistry[_addr] = CharityPool(_addr);
            charityPoolList.add(_addr);
        }
        return address(__charityPoolRegistry[_addr]);
    }

    function numberOfCharities() public view returns (uint256) {
        return charityPoolList.length();
    }

    function deregisterCharityPool(address _addr) public onlyOperatorOrOwner {
        console.log("removing charity from lists", _addr);
        delete __charityPoolRegistry[_addr];
        // remove the address from the charityPoolList
        charityPoolList.remove(_addr);
    }

    function getTotalCharityPoolInterest() external view returns (uint256) {
        uint256 totalInterest = 0;
        for (uint256 i = 0; i < charityPoolList.length(); i++) {
            address charity = charityPoolList.at(i);
            totalInterest += __charityPoolRegistry[charity].totalInterestEarned();
        }
        return totalInterest;
    }

    function dripStage1() external onlyOperatorOrOwner {
        // the number of tokens that go to each user is based on their currently allocated capital across all pools
        console.log("calculating incremental charity pool interest generation...");
        uint256 initialGas = gasleft();
        uint256 consumedGas = 0;

        console.log("Intial gas,", initialGas);

        require(processingState.status == 0, "Invalid status");

        for (uint256 i = processingState.i; i < charityPoolList.length(); i++) {
            // Check how much gas was used and break
            consumedGas = initialGas - gasleft();
            console.log("Consumed gas,", consumedGas, "limit", __processingGasLimit);
            if (consumedGas >= __processingGasLimit) {
                processingState.i = i;
                return;
            }
            console.log("");
            address charity = charityPoolList.at(i);
            console.log(charity);

            // string memory charityToken = __charityPoolRegistry[charity].tokenname();

            // get the total from each charity - this represents an accumulated value not just the current capital or interest
            __charityPoolRegistry[charity].calculateTotalIncrementalInterest();

            uint256 totalInterestUSDofCharity = __charityPoolRegistry[charity].newTotalInterestEarnedUSD();

            // capture the share
            charityInterestShare[charity] += totalInterestUSDofCharity;

            // this represents the totalInterest in USD
            processingState.newInterestUS += totalInterestUSDofCharity;

            // get the balance per user that has generated this new interest amount
            uint256 charityAccountedBalance = __charityPoolRegistry[charity].accountedBalanceUSD();

            processingState.totalCharityPoolContributions += charityAccountedBalance;
        }

        __interestGenerated += processingState.newInterestUS;
        processingState.status = 1;
        processingState.i = 0;
        // keep track of the last interest processed so we only processed the changed aggregate interest amount
        console.log("\nincremental calc done...");
    }

    function dripStage2() external onlyOperatorOrOwner {
        require(processingState.status == 1, "Invalid status");

        console.log("DRIPPING...\n");

        // CHECKS, EFFECTS, INTERACTIONS

        // make sure this only happens once per block - for now just made it on demand

        // this value will accumulate the overall accumlated interest balance for each charity over each timestep
        uint256 newInterestUSD = processingState.newInterestUS; // represents capital contributed + interest generated
        uint256 totalCharityPoolContributions = processingState.totalCharityPoolContributions;

        console.log("\nnewInterestUSD", newInterestUSD);
        console.log("totalCharityPoolContributions", totalCharityPoolContributions);
        console.log("tokenPhase", __tokenPhase);

        // based on the total generated interest in the timestep generate the tokens to drip
        uint256 tokensPerInterest = tokensPerInterestByPhase(__tokenPhase);
        // e.g. $1.66 in Wei
        console.log("tokensPerInterest", tokensPerInterest);

        // calculate the units to drip this timestamp
        uint256 tokensToCirculate = newInterestUSD.mul(tokensPerInterest);
        // 1.66 * 10 = 16.66 tokens to circulate (in ihelp currency)

        console.log("totalSupply", __totalSupply);
        console.log("tokensToCirculate", tokensToCirculate);

        // check supply and only only process what is available, mint more if needed at next rate
        // e.g. 10 tokens available - 16.66 tokens needed = -6.66 tokens remaining
        // if newTokenSupply is <= 0, circulate tokens at the current phase rate and mint new ones
        // for this changeover case, we basically need to only generate enough tokens in supply and back out the interest used for that
        // then calculate the new token generation based on the new token interest rate

        uint256 tokensToCirculateInCurrentPhase = 0;

        // Skip by default assignTokensToContributors
        processingState.status = 3;

        if (tokensToCirculate >= __totalSupply) {
            console.log("");
            console.log("splitting interest division...");

            tokensToCirculateInCurrentPhase = __totalSupply;
            console.log("tokensToCirculateInCurrentPhase", tokensToCirculateInCurrentPhase);
            // e.g. 10 token
            __totalSupply -= tokensToCirculateInCurrentPhase;
            __totalCirculating += tokensToCirculateInCurrentPhase;

            if (totalCharityPoolContributions > 0) {
                // Need to call assignTokensToContributors
                uint256 interestForExistingTokenSupply = tokensToCirculateInCurrentPhase.div(tokensPerInterest);

                console.log("interestForExistingTokenSupply", interestForExistingTokenSupply);

                // DISTRIBUTE THIS INTEREST TO ALL

                console.log("newInterestUSD", newInterestUSD);

                uint256 remainingInterestToCirculate = newInterestUSD - interestForExistingTokenSupply;
                // e.g. $10 required - $6 ciruclated = $4 remaining
                console.log("remainingInterestToCirculate", remainingInterestToCirculate);

                __tokenPhase += 1;
                uint256 newTokensPerInterest = tokensPerInterestByPhase(__tokenPhase);
                // e.g. 0.86

                // mint another 1,000,000 tokens to the supply
                // console.log('mint operator',operator);
                _mint(operator, __tokensMintedPerPhase * 1e18);

                __totalSupply += __tokensMintedPerPhase * 1e18;

                uint256 remainingTokensToCirculate = remainingInterestToCirculate.mul(newTokensPerInterest);
                // e..g $4 * $0.86 = $3.44
                console.log("remainingTokensToCirculate", remainingTokensToCirculate);

                tokensToCirculate = remainingTokensToCirculate;
                processingState.status = 2;
            }
        }

        processingState.tokensToCirculate = tokensToCirculate;
        processingState.tokensToCirculateInCurrentPhase = tokensToCirculateInCurrentPhase;
        __totalSupply -= tokensToCirculate;
        __totalCirculating += tokensToCirculate;
        __tokensLastDripped = tokensToCirculate + tokensToCirculateInCurrentPhase;
    }

    function dripStage3() external onlyOperatorOrOwner {
        require(processingState.status == 2, "Invalid status");

        uint256 tokensToCirculateInCurrentPhase = processingState.tokensToCirculateInCurrentPhase;
        bool done = distribute(tokensToCirculateInCurrentPhase);
        if (done) {
            processingState.i = 0;
            processingState.ii = 0;
            processingState.status = 3;
        }
    }

    function dripStage4() external onlyOperatorOrOwner {
        require(processingState.status == 3, "Invalid status");
        uint256 tokensToCirculate = processingState.tokensToCirculate;
        bool done = distribute(tokensToCirculate);
        if (done) {
            processingState.i = 0;
            processingState.ii = 0;
            processingState.status = 4;
        }
    }

    function distribute(uint256 tokensToCirculate) internal returns (bool) {
        console.log("Starting distribution", tokensToCirculate);

        uint256 initialGas = gasleft();
        uint256 consumedGas = 0;
        for (uint256 i = processingState.i; i < charityPoolList.length(); i++) {
            // Check how much gas was used and break
            consumedGas = initialGas - gasleft();
            console.log("Consumed gas,", consumedGas, "limit", __processingGasLimit);

            if (consumedGas >= __processingGasLimit) {
                processingState.i = i;
                return false;
            }

            console.log("");
            address charity = charityPoolList.at(i);
            // console.log("pool:", charity);

            uint256 poolContribution = __charityPoolRegistry[charity].accountedBalanceUSD();
            // console.log("poolContribution", poolContribution);

            if (poolContribution > 0) {
                // console.log("totalCharityPoolContributions", processingState.totalCharityPoolContributions);
                uint256 poolShare = poolContribution.div(processingState.totalCharityPoolContributions);
                // console.log("poolShare", poolShare);

                uint256 poolTokens = poolShare.mul(tokensToCirculate);
                // console.log("poolTokens", poolTokens);

                address[] memory contributorList = __charityPoolRegistry[charity].getContributors();

                for (uint256 ii = processingState.ii; ii < contributorList.length; ii++) {
                    // Check how much gas was used and break
                    consumedGas = initialGas - gasleft();
                    console.log("Consumed gas L2,", consumedGas, "limit", __processingGasLimit);

                    if (consumedGas >= __processingGasLimit) {
                        processingState.i = i;
                        processingState.ii = ii;
                        return false;
                    }
                    // get the contributors balance
                    uint256 userContribution = __charityPoolRegistry[charity].balanceOfUSD(contributorList[ii]);

                    uint256 userShare = userContribution.div(poolContribution);
                    console.log("contributor", contributorList[ii], userContribution, userShare);

                    uint256 contribTokens = userShare.mul(poolTokens);
                    console.log("contribTokens", contribTokens);

                    contributorTokenClaims[contributorList[ii]] += contribTokens;
                }
                processingState.ii = 0;
            }
        }

        return true;
    }

    function calculatePerfectRedeemInterest() public view returns (uint256) {
        uint256 perfectRedeemedInterest = 0;
        for (uint256 i = 0; i < charityPoolList.length(); i++) {
            perfectRedeemedInterest += charityInterestShare[charityPoolList.at(i)];
        }
        return perfectRedeemedInterest;
    }

    // NOTE: call this after calling calculatePerfectRedeemInterest off chain
    function dump(uint256 perfectRedeemedInterest) public onlyOperatorOrOwner {
        require(processingState.status == 4, "Invalid status");

        // check the incrementals add up to the total specific charity amounts
        console.log("\ndumping interest...\n");

        console.log("perfectRedeemedInterest", perfectRedeemedInterest);
        uint256 initialGas = gasleft();
        uint256 consumedGas = 0;
        if (perfectRedeemedInterest > 0) {
            for (uint256 i = processingState.i; i < charityPoolList.length(); i++) {
                consumedGas = initialGas - gasleft();
                if (consumedGas >= __processingGasLimit) {
                    processingState.i = i;
                    return;
                }
                // get the balance of the holding pool before and after the redemption
                uint256 tokenBalanceBefore = underlyingToken.balanceOf(holdingPool);
                console.log("tokenBalanceBefore \n", tokenBalanceBefore);

                // redeem the charity interest to the holding pool
                console.log("\nREDEEM START");
                address charity = charityPoolList.at(i);
                console.log(charity);
                __charityPoolRegistry[charity].redeemInterest();
                console.log("REDEEM END\n");

                uint256 tokenBalanceAfter = underlyingToken.balanceOf(holdingPool);
                console.log("tokenBalanceAfter \n", tokenBalanceAfter);

                // this gets the actual interest generated after the swap
                if (tokenBalanceAfter > tokenBalanceBefore) {
                    uint256 realRedeemedInterest = tokenBalanceAfter - tokenBalanceBefore;

                    console.log("perfectRedeemedInterest,realRedeemedInterest");
                    console.log(charityInterestShare[charity], realRedeemedInterest);

                    // make the redeem interest portion available to the charity
                    address charityWalletAddress = __charityPoolRegistry[charity].charityWallet();

                    uint256 correctedInterestShare = realRedeemedInterest;
                    console.log("correctedInterestShare", correctedInterestShare);

                    // divide this amongst holding, dev and staking pools (and charities)

                    // if the charity wallet address is equal to the holding pool address, this is an off-chain transfer to assign it to the charity contract itself
                    if (charityWalletAddress == holdingPool) {
                        claimableCharityInterest[charity] += correctedInterestShare.mul(charityShareOfInterest);
                    } else {
                        console.log("Sending tokens to the charity wallet", charityWalletAddress);
                        claimableCharityInterest[charityWalletAddress] += correctedInterestShare.mul(
                            charityShareOfInterest
                        );
                    }
                    claimableCharityInterest[developmentPool] += correctedInterestShare.mul(developmentShareOfInterest);
                    claimableCharityInterest[stakingPool] += correctedInterestShare.mul(stakingShareOfInterest);

                    // reset the charity interest share
                    charityInterestShare[charity] = 0;
                } else {
                    console.log("NO CHANGE IN DUMPED STATE.");
                }
            }
        }
        processingState.newInterestUS = 0;
        processingState.totalCharityPoolContributions = 0;
        processingState.status = 0;
        processingState.i = 0;
        processingState.ii = 0;
    }

    function totalCirculating() public view returns (uint256) {
        return __totalCirculating;
    }

    function totalAvailableSupply() public view returns (uint256) {
        return __totalSupply;
    }

    function tokensLastDripped() public view returns (uint256) {
        return __tokensLastDripped;
    }

    function claimableTokens() public view returns (uint256) {
        return getClaimableTokens(msg.sender);
    }

    function getClaimableTokens(address _addr) public view returns (uint256) {
        return contributorTokenClaims[_addr];
    }

    function getClaimableCharityInterestOf(address _addr) public view returns (uint256) {
        return claimableCharityInterest[_addr];
    }

    function getClaimableCharityInterest() public view returns (uint256) {
        return getClaimableCharityInterestOf(msg.sender);
    }

    function balance() public view returns (uint256) {
        return balanceOf(msg.sender);
    }

    // must send from holdingPool account for on-chain transfers
    function claimInterest(address _addr) public {
        console.log("CLAIMING INTEREST");
        console.log(msg.sender, holdingPool, _addr);
        // specific for on-chain transfer. off-chain transfers to charity wallet.
        if (charityPoolList.contains(_addr) == false && holdingPool != _addr) {
            if (msg.sender == holdingPool) {
                uint256 amount = claimableCharityInterest[_addr];

                if (amount > 0) {
                    // charityPool account
                    uint256 bal = underlyingToken.balanceOf(msg.sender);
                    console.log("balance of sender:", bal);

                    claimableCharityInterest[_addr] = 0;

                    bool success = underlyingToken.transferFrom(msg.sender, _addr, amount);
                    require(success, "transfer failed");
                }
            }
        }
    }

    function resetClaimableCharityInterest(address _addr) public onlyOperatorOrOwner {
        claimableCharityInterest[_addr] = 0;
    }

    function claimTokens() public {
        uint256 claimAmount = contributorTokenClaims[msg.sender];
        claimSpecificTokens(claimAmount);
    }

    function claimSpecificTokens(uint256 amount) public {
        uint256 claimAmount = contributorTokenClaims[msg.sender];
        console.log("claiming tokens", msg.sender, amount, claimAmount);

        require(claimAmount >= amount, "not enough claimable balance for amount");

        contributorTokenClaims[msg.sender] -= amount;

        approve(operator, amount);
        _transfer(operator, msg.sender, amount);
    }

    // getters used for iHelp interface definition
    function getUnderlyingToken() public view returns (IERC20) {
        return underlyingToken;
    }

    // getters used for iHelp interface definition
    function getStakingPool() public view returns (address) {
        return stakingPool;
    }

    // getters used for iHelp interface definition
    function getHoldingPool() public view returns (address) {
        return holdingPool;
    }

    function setProcessingGasLimit(uint256 gasLimit) public onlyOperatorOrOwner {
        require(gasLimit > 0, "Limit cannot be 0");
        __processingGasLimit = gasLimit;
    }
}
