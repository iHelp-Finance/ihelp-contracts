// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.9;

library AnalyticsUtils {
    struct GeneralStats {
        uint256 totalValueLocked;
        uint256 totalInterestGenerated;
        uint256 totalHelpers;
        uint256 totalCharities;
    }

    struct CharityStats {
        uint256 totalValueLocked;
        uint256 totalYieldGenerated;
        uint256 numerOfContributors;
        uint256 totalDirectDonations;
    }

    struct IndividualCharityContributionInfo {
        string  charityName;
        address charityAddress;
        uint256 totalContributions;
        uint256 totalDonations;
    }

    struct StakingPoolStats {
        uint256 iHelpTokensInCirculation;
        uint256 iHelpStaked;
    }

    struct UserStats {
        uint256 totalDirectDonations;
        uint256 totalInterestGenerated;
        uint256 totalContributions;
    }

    struct UserCharityContributions {
        string  charityName;
        address charityAddress;
        uint256 totalContributions;
    }

    struct UserCharityTokenContributions {
        address tokenAddress;
        string currency;
        uint256 totalContributions;
    }

    struct CharityBalanceInfo {
        address charityAddress;
        string charityName;
        uint256 balance;
    }

    struct WalletBalance {
        address tokenAddress;
        string currency;
        uint256 balance;
    }

    struct WalletAllowance {
        address tokenAddress;
        string currency;
        uint256 allowance;
    }
}
