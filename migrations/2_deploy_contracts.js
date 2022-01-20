// migrations/2_deploy.js
const marketplace = artifacts.require("Marketplace");
const {
  _acceptedToken,
  _ownerCutPerMillion,
  _owner,
} = require("../common/arguments");

module.exports = async function (deployer) {
  await deployer.deploy(
    marketplace,
    _acceptedToken,
    _ownerCutPerMillion,
    _owner
  );
};
