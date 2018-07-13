# weeveNetwork
It is an indisputable fact that data has tremendous value when tokenized and used in a network to support the mechanics and principles of an economy. The Weeve network empowers the economy of things by introducing a commercialisation layer between (IoT) devices and the Blockchain. In the **weeveNetwork**, machines (or *Weeves* thereof) index, process, tokenize and trade harvested data against digital data assets, among them are most notably cryptocoins.

Weeve envisions public or private marketplaces for any form of digital assets ranging from geo-data to electricity or delivery status, where data producers and consumers (resp., buyers and sellers) come together, escrow their supply and demand, and exchange their digital assets for agreed upon prices.

## Smart Contracts
The current smart contracts in this repository are a development state, they are not final nor set in stone. Our development goal is the implementation of the weeveNetwork and its components, namely the registries and marketplaces. We will update this repository regularly in the process of our development.  

### Voting and Challenging
Some weeks ago we implemented device challenges into the weeveNetwork. With our latest update we also brought the same functionality to the registries and marketplaces. Based on Mike Goldins (ConsenSys) PCLR voting we are now providing our users with the ability to challenge registries, marketplaces and single devices, vote on active challenges and resolve them in the end. If a vote on a challenge passes, the affected entity is being excluded and it's stake is slashed. For more details on the voting process and the token mechanics we are referring to our [token paper](https://weeve.network/cache/assets/fo0rvac1gv8v/54LNfLzq5O8sco4mA2QyQ6/6739ded3cd2e825b995ed5e8e7bcc185/Weeve_Token_Model__1_.pdf).

The implementation of the voting contract itself can be found [here](https://github.com/weeveiot/weeveNetwork/blob/master/contracts/weeveVoting.sol). The corresponding calls for registry and marketplace challenges to the voting contract are implemented in the [weeveNetwork](https://github.com/weeveiot/weeveNetwork/blob/master/contracts/weeveNetwork.sol). For device challenges the calls to the voting contract are implemented in the [weeveRegistry](https://github.com/weeveiot/weeveNetwork/blob/master/contracts/weeveRegistry.sol) and the [weeveRegistryLib](https://github.com/weeveiot/weeveNetwork/blob/master/contracts/libraries/weeveRegistryLib.sol).

## Questions or suggestions?
We are always happy to get some feedback and new ideas - we also like to chat about development in general, so feel free to join our gitter!

[![Join the chat at https://gitter.im/weeveiot/weeveNetwork](https://badges.gitter.im/weeveiot/weeveNetwork.svg)](https://gitter.im/weeveiot/weeveNetwork?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)