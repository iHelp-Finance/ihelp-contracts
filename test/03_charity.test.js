const { expect, use } = require("chai");
const { ethers } = require("hardhat");
const { parseEther } = require("ethers/lib/utils");
const { smock } = require("@defi-wonderland/smock");
const { abi } = require("../artifacts/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol/AggregatorV3Interface.json");
use(smock.matchers);
describe("Charity Pool", function () {
    let charityPool;
    let owner;
    let addr1;
    let addr2;
    let addrs;
    let stakingPool, cTokenUnderlyingMock, developmentPool, holdingPool, cTokenMock, iHelpMock, holdingMock;

    beforeEach(async function () {
        const CharityPool = await smock.mock("CharityPool");

        [owner, addr1, addr2, stakingPool, developmentPool, holdingPool, operator, swapperPool, ...addrs] = await ethers.getSigners();

        const Mock = await smock.mock("ERC20MintableMock");
        const CTokenMock = await smock.mock("CTokenMock");
        const aggregator = await smock.fake(abi);
        iHelpMock = await smock.fake("iHelpToken", { address: addr2.address });

        cTokenUnderlyingMock = await Mock.deploy("Mock", "MOK", 18);
        holdingMock = await Mock.deploy("Mock", "MOK", 9);
        cTokenMock = await CTokenMock.deploy(cTokenUnderlyingMock.address, 1000);

        charityPool = await CharityPool.deploy();
        swapperMock = await smock.fake("Swapper", { address: swapperPool.address });

        await charityPool.initialize(
            "TestCharity",
            operator.address,
            holdingPool.address,
            cTokenUnderlyingMock.address,// address _charityWallet,
            "XTC",
            cTokenMock.address,
            holdingMock.address, //_holdingToken,
            aggregator.address,// address _priceFeed,
            iHelpMock.address,
            swapperMock.address,
            stakingPool.address,
            developmentPool.address,
        );


        aggregator.latestRoundData.returns([0, 100000000, 0, 0, 0]);
        charityPool.getUnderlyingTokenPrice.returns(100000000);
    });

    describe("Deployment", function () {
        it("Should set the right staking pool", async function () {
            expect(await charityPool.stakingPool()).to.equal(stakingPool.address);
        });

        it("Should set the right holding pool", async function () {
            expect(await charityPool.holdingPool()).to.equal(holdingPool.address);
        });

        it("Should set the right development pool", async function () {
            expect(await charityPool.developmentPool()).to.equal(developmentPool.address);
        });

        it("Should set the right token", async function () {
            expect(await charityPool.token()).to.equal(cTokenUnderlyingMock.address);
        });

        it("Should set the right supplyRatePerBlock", async function () {
            expect(await charityPool.supplyRatePerBlock()).to.equal(1000);
        });

        it("Should calculate correct estimatedInterestRate", async function () {
            expect(await charityPool.estimatedInterestRate(10)).to.equal(1000 * 10);
        });

        it("Should get decimals", async function () {
            expect(await charityPool.decimals()).to.equal(18);
        });

        it("Should not set zero address as operator", async function () {
            await expect(charityPool.transferOperator('0x0000000000000000000000000000000000000000')).to.be.revertedWith("Ownable: new operator is the zero address");
        });

        it("Should set new operator", async function () {
            await expect(charityPool.transferOperator(addr1.address)).not.to.be.reverted;
            expect(await charityPool.operator()).to.equal(addr1.address);
        });

        it("Should set new operator as operator", async function () {
            await expect(charityPool.connect(operator).transferOperator(addr1.address)).not.to.be.reverted;
            expect(await charityPool.operator()).to.equal(addr1.address);
        });

        it("Should not allow to set new operator", async function () {
            await expect(charityPool.connect(addr1).transferOperator(addr2.address)).to.be.revertedWith("is-operator-or-owner");
        });

        it("Should set new stakingPool", async function () {
            await expect(charityPool.setStakingPool(addr1.address)).not.to.be.reverted;
            expect(await charityPool.stakingPool()).to.equal(addr1.address);
        });

        it("Should not allow to set new operator", async function () {
            await expect(charityPool.connect(addr1).setStakingPool(addr2.address)).to.be.revertedWith("is-operator-or-owner");
        });

        // it("Should not set zero address as operator", async function () {
        //     await expect(charityPool.setStakingPool('0x0000000000000000000000000000000000000000')).to.be.revertedWith("TODO");
        // });

        it("Should return the balance of cToken", async function () {
            cTokenMock.balanceOfUnderlying.returns(10000);
            expect(await charityPool.balance()).to.equal(10000);
        });
    });


    describe("Deposit", function () {
        beforeEach(async function () {
            await cTokenUnderlyingMock.mint(owner.address, 10000);
            await cTokenUnderlyingMock.increaseAllowance(charityPool.address, 1000);
        });

        it("Should fail to deposit 0", async function () {
            await expect(charityPool.deposit(0)).to.be.revertedWith("Funding/small-amount");
        });

        it("Should emit deposit event", async function () {
            await expect(charityPool.deposit(15))
                .to.emit(charityPool, "Deposited");
        });

        it("Should add address to contributors", async function () {
            await charityPool.deposit(15);
            expect(await charityPool.getContributors()).to.have.members([owner.address]);
        });

        it("Should increase contributor's balance", async function () {
            await charityPool.deposit(15);
            expect(await charityPool.balanceOf(owner.address)).to.equal(15);
        });

        it("Should increase total balance", async function () {
            await charityPool.deposit(15);
            expect(await charityPool.accountedBalance()).to.equal(15);
        });

        it("Should mint to cToken", async function () {
            await charityPool.deposit(15);
            expect(await charityPool.balance()).to.equal(15);
        });

        it("Should calculate usd balance", async function () {
            const deposit = 100;
            const expectedBalanceInUsd = deposit * 1e9; // 18-9 decimalls

            await charityPool.deposit(deposit);
            expect(await charityPool.balanceOfUSD(owner.address)).to.equal(0);
            await charityPool.connect(iHelpMock.wallet).calculateTotalIncrementalInterest();
            expect(await charityPool.balanceOfUSD(owner.address)).to.equal(expectedBalanceInUsd);
        });
    });

    describe("Sponsor", function () {
        beforeEach(async function () {
            await cTokenUnderlyingMock.mint(owner.address, 10000);
            await cTokenUnderlyingMock.increaseAllowance(charityPool.address, 1000);
        });

        it("Should fail to deposit 0", async function () {
            await expect(charityPool.sponsor(0)).to.be.revertedWith("Funding/small-amount");
        });

        it("Should emit deposit event", async function () {
            await expect(charityPool.deposit(15))
                .to.emit(charityPool, "Deposited");
        });

        it("Should add address to contributors", async function () {
            await charityPool.sponsor(15);
            expect(await charityPool.getContributors()).to.have.members([owner.address]);
        });

        it("Should increase contributor's balance", async function () {
            await charityPool.sponsor(15);
            expect(await charityPool.balanceOf(owner.address)).to.equal(15);
        });

        it("Should increase total balance", async function () {
            await charityPool.sponsor(15);
            expect(await charityPool.accountedBalance()).to.equal(15);
        });

        it("Should mint to cToken", async function () {
            await charityPool.deposit(15);
            expect(await charityPool.balance()).to.equal(15);
        });
    });

    describe("Withdraw", function () {
        beforeEach(async function () {
            await cTokenUnderlyingMock.mint(owner.address, 100);
            await cTokenUnderlyingMock.increaseAllowance(charityPool.address, 100);
            await charityPool.deposit(100);
        });

        it("Should withdraw all balance", async function () {
            await charityPool.withdraw();
            expect(await charityPool.balanceOf(owner.address)).to.equal(0);
        });

        it("Should withdraw partial balance", async function () {
            await charityPool.withdrawAmount(10);
            expect(await charityPool.balanceOf(owner.address)).to.equal(90);
        });

        it("Should fail to withdraw over balance", async function () {
            await expect(charityPool.withdrawAmount(101)).to.be.revertedWith("Funding/no-funds");
            expect(await charityPool.balanceOf(owner.address)).to.equal(100);
        });

        it("Should decrease balance", async function () {
            await charityPool.withdraw();
            expect(await charityPool.balanceOf(owner.address)).to.equal(0);
            expect(await charityPool.balance()).to.equal(0);
        });

        it("Should emit withdrawn event", async function () {
            expect(await charityPool.withdraw())
                .to.emit(charityPool, "Withdrawn");
        });
    });

    describe("Direct Donations", function () {
        beforeEach(async function () {
            await cTokenUnderlyingMock.mint(owner.address, parseEther("100"));
            await cTokenUnderlyingMock.increaseAllowance(charityPool.address, parseEther("100"));
        });

        it("Should do nothing when donating 0", async function () {
            expect(await charityPool.directDonation(0))
                .not.to.emit(charityPool, "Rewarded");
        });

        it("Should emit rewarded event", async function () {
            expect(await charityPool.directDonation(100))
                .to.emit(charityPool, "Rewarded");
        });

        it("Should send staking fee", async function () {
            await charityPool.setVariable('holdingToken', cTokenUnderlyingMock.address);
            const amount = parseEther("10");
            const expectedAmountAfterTax = amount.mul(25).div(1000); // 2.5%
            await charityPool.directDonation(amount);
            expect(await cTokenUnderlyingMock.balanceOf(stakingPool.address)).to.equal(expectedAmountAfterTax);
        });

        it("Should swap and send staking fee", async function () {
            const amount = parseEther("10");
            await charityPool.directDonation(amount);
            expect(swapperMock.swap).to.be.calledOnce;
        });

        it("Should send development fee", async function () {
            const amount = parseEther("10");
            const expectedAmountAfterTax = amount.mul(25).div(1000); // 2.5%
            await charityPool.directDonation(amount);
            expect(await cTokenUnderlyingMock.balanceOf(developmentPool.address)).to.equal(expectedAmountAfterTax);
        });

        it("Should send to charity wallet with fee", async function () {
            const amount = parseEther("10");
            const expectedAmountAfterTax = amount.mul(95).div(100); //95%
            await charityPool.directDonation(amount);
            expect(await cTokenUnderlyingMock.balanceOf(cTokenUnderlyingMock.address)).to.equal(expectedAmountAfterTax);
        });
    });

    describe("Interest", function () {
        beforeEach(async function () {
            await cTokenUnderlyingMock.mint(owner.address, parseEther("200"));
            await cTokenUnderlyingMock.increaseAllowance(charityPool.address, parseEther("200"));
        });

        it("Should return interest of cToken", async function () {
            cTokenMock.balanceOfUnderlying.returns(10000);
            expect(await charityPool.interestEarned()).to.equal(10000);
        });

        it("Should return interest", async function () {
            const interest = 10000;
            const deposit = parseEther("200");
            const withdrawal = parseEther("150");
            await charityPool.deposit(deposit);
            await charityPool.withdrawAmount(withdrawal);
            cTokenMock.balanceOfUnderlying.returns(deposit.sub(withdrawal).add(interest));
            expect(await charityPool.accountedBalance()).to.equal(deposit.sub(withdrawal));
            expect(await charityPool.interestEarned()).to.equal(interest);
        });

        it("Should return 0 when there's no interest", async function () {
            cTokenMock.balanceOfUnderlying.returns(0);
            const deposit = 200;
            const withdrawal = 50;
            await charityPool.deposit(deposit);
            await charityPool.withdrawAmount(withdrawal);
            expect(await charityPool.interestEarned()).to.equal(0);
        });

        it("Should calculate redeemable interest", async function () {
            const interest = 10000;
            cTokenMock.balanceOfUnderlying.returns(interest);

            await charityPool.connect(iHelpMock.wallet).calculateTotalIncrementalInterest();
            expect(await charityPool.redeemableInterest()).to.equal(interest);
        });

        it("Should not add new redeemable interest", async function () {
            const interest = 10000;
            cTokenMock.balanceOfUnderlying.returns(interest);

            await charityPool.connect(iHelpMock.wallet).calculateTotalIncrementalInterest();
            expect(await charityPool.redeemableInterest()).to.equal(interest);
            await charityPool.connect(iHelpMock.wallet).calculateTotalIncrementalInterest();
            expect(await charityPool.redeemableInterest()).to.equal(interest);
        });

        it("Should calculate usd", async function () {
            const interest = 10000;
            const expectedInterestInUsd = interest * 1e9; // 18-9 decimalls
            cTokenMock.balanceOfUnderlying.returns(interest);

            await charityPool.connect(iHelpMock.wallet).calculateTotalIncrementalInterest();
            expect(await charityPool.newTotalInterestEarnedUSD()).to.equal(expectedInterestInUsd);
            expect(await charityPool.totalInterestEarnedUSD()).to.equal(expectedInterestInUsd);
            expect(await charityPool.accountedBalanceUSD()).to.equal(0);
        });

        it("Should not add new interest", async function () {
            const interest = 10000;
            const expectedInterestInUsd = interest * 1e9; // 18-9 decimalls
            cTokenMock.balanceOfUnderlying.returns(interest);
            await charityPool.setVariable('currentInterestEarned', interest);

            await charityPool.connect(iHelpMock.wallet).calculateTotalIncrementalInterest();
            expect(await charityPool.newTotalInterestEarnedUSD()).to.equal(0);
            expect(await charityPool.totalInterestEarnedUSD()).to.equal(0);
        });

        it("Should calculate accountedBalanceUSD", async function () {
            const interest = 10000;
            const deposit = parseEther("200");
            const expectedBalanceInUsd = deposit.mul(1e9); // 18-9 decimalls

            cTokenMock.balanceOfUnderlying.returns(deposit.add(interest));

            await charityPool.deposit(deposit);
            await charityPool.connect(iHelpMock.wallet).calculateTotalIncrementalInterest();
            expect(await charityPool.accountedBalanceUSD()).to.equal(expectedBalanceInUsd);
        });

        it("Should redeem interest", async function () {
            const interest = 10000;
            await charityPool.setVariable('redeemableInterest', interest);
            await charityPool.setVariable('currentInterestEarned', interest);
            cTokenMock.redeemUnderlying.returns(() => {
                cTokenUnderlyingMock.setVariable('_balances', {
                    [charityPool.address]: interest
                });
                return 0;
            });

            await charityPool.connect(iHelpMock.wallet).calculateTotalIncrementalInterest();

            await expect(charityPool.connect(iHelpMock.wallet).redeemInterest()).to.emit(charityPool, "Rewarded");

            expect(await charityPool.redeemableInterest()).to.equal(0);
            expect(await charityPool.currentInterestEarned()).to.equal(0);
        });

        it("Should emit rewarded", async function () {
            const interest = 10000;
            cTokenMock.balanceOfUnderlying.returns(interest);
            cTokenMock.redeemUnderlying.returns();

            await charityPool.connect(iHelpMock.wallet).calculateTotalIncrementalInterest();
            expect(await charityPool.connect(iHelpMock.wallet).redeemInterest()).to.emit(charityPool, "Rewarded");
        });

        it("Should not emit rewarded if no interest", async function () {
            const interest = 0;
            cTokenMock.balanceOfUnderlying.returns(interest);

            await charityPool.connect(iHelpMock.wallet).calculateTotalIncrementalInterest();
            expect(await charityPool.connect(iHelpMock.wallet).redeemInterest()).not.to.emit(charityPool, "Rewarded");
        });

        it("Should reset redeemable interest", async function () {
            const interest = 10000;
            cTokenMock.balanceOfUnderlying.returns(interest);
            cTokenMock.redeemUnderlying.returns();
            await charityPool.connect(iHelpMock.wallet).calculateTotalIncrementalInterest();
            expect(await charityPool.redeemableInterest()).to.equal(interest);

            await charityPool.connect(iHelpMock.wallet).redeemInterest();
            expect(await charityPool.redeemableInterest()).to.equal(0);
        });
    });

    describe("Pow", function () {
        it("Should calculate exponents", async function () {
            expect(await charityPool.safepow(0, 0)).to.equal(1);
            expect(await charityPool.safepow(0, 1)).to.equal(0);
            expect(await charityPool.safepow(1, 0)).to.equal(1);
            expect(await charityPool.safepow(1, 1)).to.equal(1);
            expect(await charityPool.safepow(0, 123)).to.equal(0);
            expect(await charityPool.safepow(2, 3)).to.equal(8);
            expect(await charityPool.safepow(parseEther("0"), parseEther("0"))).to.equal(1);
            expect(await charityPool.safepow(10, 18)).to.equal((1e18).toFixed());
        });
    });
});