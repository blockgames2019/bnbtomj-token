const MjCoin = artifacts.require("MjCoin");

module.exports = function (deployer) {
  deployer.deploy(MjCoin,"0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3");
  //deployer.deploy(MjCoin,"0x10ED43C718714eb63d5aA57B78B54704E256024E");
  //deployer.deploy(MjCoin,"0x000000000000000000000000000000000000dEaD","0xd26922E88e297aC5F787CbA944aaf0dbF80Ac938");
};
