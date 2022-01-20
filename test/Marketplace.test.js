// test/Marketplace.test.js
// Load dependencies
const { expect } = require("chai");
const BigNumber = web3.utils.BN;
require("chai")
  .use(require("chai-as-promised"))
  .use(require("chai-bignumber")(BigNumber))
  .should();

// Load compiled artifacts
const marketplace = artifacts.require("Marketplace");

// Start test block
contract("marketplace", async function (accounts) {
  // creator is aution deployer, bidder is a space token bidder using his mana token, beneficiary gets space token
  const [creator, bidder, beneficiary] = accounts;
  let marketplaceContract;

  console.log("   ================ Account Info ==============");
  console.log("  *** Creator     : ", creator);
  console.log("  *** Bidder      : ", bidder);
  console.log("  *** Beneficiary : ", beneficiary);
  console.log("   ============================================");

  const _acceptedTokenAddress = "";
  const _ownerCutPerMillion = new BigNumber(100);

  const params = {
    from: creator,
  };

  describe("CHECK MARKETPLACE", () => {
    beforeEach(async function () {
      // Deploy a new Box contract for each test
      marketplaceContract = await marketplace.new(
        _acceptedTokenAddress,
        _ownerCutPerMillion,
        creator
      );

      console.log(
        "*** Marketplace Contract address: ",
        marketplaceContract.address
      );
    });
  });
});
