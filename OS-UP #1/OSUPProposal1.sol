//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Grimoire {
    bytes32 constant public COMPONENT_KEY_STATE_MANAGER = 0xd1d09e8f5708558865b8acd5f13c69781ae600e42dbc7f52b8ef1b9e33dbcd36;
}

library EthereansGrimoire {
    bytes32 constant public SUBDAO_KEY_ETHEREANSOS_V1 = 0x1d3784c94477427ee3ebf963dc80bcdc1be400c47ff2754fc2a9cd7328837eb4;
}

library ExternalGrimoire {
    bytes32 constant public COMPONENT_KEY_SUBDAOS_MANAGER = 0x5b87d6e94145c2e242653a71b7d439a3638a93c3f0d32e1ea876f9fb1feb53e2;
    bytes32 constant public COMPONENT_KEY_DELEGATIONS_MANAGER = 0x49b87f4ee20613c184485be8eadb46851dd4294a8359f902606085b8be6e7ae6;
}

library ExternalGetters {
    function subDAOsManager(IOrganization organization) internal view returns(ISubDAOsManager) {
        return ISubDAOsManager(organization.get(ExternalGrimoire.COMPONENT_KEY_SUBDAOS_MANAGER));
    }
}

library ExternalState {
    string constant public STATEMANAGER_ENTRY_NAME_DELEGATIONS_ATTACH_INSURANCE = "delegationsAttachInsurance";
}

library Getters {
    function stateManager(IOrganization organization) internal view returns(IStateManager) {
        return IStateManager(organization.get(Grimoire.COMPONENT_KEY_STATE_MANAGER));
    }
}

library State {
    using BytesUtilities for bytes;

    bytes32 constant public ENTRY_TYPE_UINT256 = 0xec13d6d12b88433319b64e1065a96ea19cd330ef6603f5f6fb685dde3959a320;

    function setUint256(IStateManager stateManager, string memory name, uint256 val) internal returns(uint256 oldValue) {
        return stateManager.set(IStateManager.StateEntry(name, ENTRY_TYPE_UINT256, abi.encode(val))).asUint256();
    }
}

interface ILazyInitCapableElement {
    function host() external view returns(address);
}

interface IOrganization is ILazyInitCapableElement {

    struct Component {
        bytes32 key;
        address location;
        bool active;
        bool log;
    }

    function get(bytes32 key) external view returns(address componentAddress);
    function set(Component calldata) external returns(address replacedComponentAddress);

    function batchSet(Component[] calldata) external returns (address[] memory replacedComponentAddresses);
}

interface ISubDAO {
    struct SubDAOProposalModel {
        address source;
        string uri;
        bool isPreset;
        bytes[] presetValues;
        bytes32[] presetProposals;
        address creationRules;
        address triggeringRules;
        uint256 votingRulesIndex;
        address[][] canTerminateAddresses;
        address[][] validatorsAddresses;
    }

    function setPresetValues(uint256 modelIndex, bytes[] calldata newPresetValues) external returns(bytes[] memory oldPresetValues, bytes32[] memory deprecatedProposalIds);

    function proposalModels() external view returns(SubDAOProposalModel[] memory);
    function setProposalModels(SubDAOProposalModel[] calldata newValue) external returns(SubDAOProposalModel[] memory oldValue);
}

interface ISubDAOsManager {
    function get(bytes32 key) external view returns(address subdaoAddress);
    function submit(bytes32 key, bytes calldata payload, address restReceiver) external payable returns(bytes memory response);
}

interface IStateManager {

    struct StateEntry {
        string key;
        bytes32 entryType;
        bytes value;
    }

    function get(string calldata key) external view returns(StateEntry memory);
    function set(StateEntry calldata newValue) external returns(bytes memory replacedValue);
}

library BytesUtilities {

    function asUint256(bytes memory bs) internal pure returns(uint256 x) {
        if (bs.length >= 32) {
            assembly {
                x := mload(add(bs, add(0x20, 0)))
            }
        }
    }
}

contract Proposal {
    using Getters for IOrganization;
    using ExternalGetters for IOrganization;
    using State for IStateManager;

    bytes32 private immutable MYSELF_KEY = keccak256(abi.encodePacked(address(this), block.number, tx.gasprice, block.coinbase, block.difficulty, msg.sender, block.timestamp));

    string public uri;

    address public newDelegationsManagerInstance;
    address public tokensFromETHModel;
    address public tokensToETHModel;
    ISubDAO.SubDAOProposalModel public lastProposalModel;
    uint256 public delegationsManagerAttachInsurance;

    constructor(string memory _uri, address _newDelegationsManagerInstance, address _tokensFromETHModel, address _tokensToETHModel, ISubDAO.SubDAOProposalModel memory _lastProposalModel, uint256 _delegationsManagerAttachInsurance) {
        uri = _uri;
        newDelegationsManagerInstance = _newDelegationsManagerInstance;
        tokensFromETHModel = _tokensFromETHModel;
        tokensToETHModel = _tokensToETHModel;
        lastProposalModel = _lastProposalModel;
        delegationsManagerAttachInsurance = _delegationsManagerAttachInsurance;
    }

    function execute(bytes32) external {
        newSubDAOProposalModels(mountNewDelegationsManager(IOrganization(ILazyInitCapableElement(msg.sender).host())));
    }

    function mountNewDelegationsManager(IOrganization root) private returns (ISubDAOsManager subDAOsManager) {

        subDAOsManager = root.subDAOsManager();

        IOrganization.Component memory component = IOrganization.Component({
            key : ExternalGrimoire.COMPONENT_KEY_DELEGATIONS_MANAGER,
            location : newDelegationsManagerInstance,
            active : false,
            log : true
        });

        root.set(component);

        IOrganization.Component memory mySelf = IOrganization.Component({
            key : MYSELF_KEY,
            location : address(this),
            active : true,
            log : false
        });

        IOrganization.Component[] memory components = new IOrganization.Component[](2);
        components[0] = component;
        components[1] = mySelf;

        subDAOsManager.submit(EthereansGrimoire.SUBDAO_KEY_ETHEREANSOS_V1, abi.encodeWithSelector(root.batchSet.selector, components), address(0));
    }

    function newSubDAOProposalModels(ISubDAOsManager subDAOsManager) private {
        ISubDAO subDAO = ISubDAO(subDAOsManager.get(EthereansGrimoire.SUBDAO_KEY_ETHEREANSOS_V1));

        ISubDAO.SubDAOProposalModel[] memory proposalModels = subDAO.proposalModels();

        for(uint256 i = 0; i < 6; i++) {
            subDAO.setPresetValues(i, proposalModels[i].presetValues);
        }

        ISubDAO.SubDAOProposalModel memory prop = proposalModels[proposalModels.length - 2];
        prop.source = tokensFromETHModel;
        proposalModels[proposalModels.length - 2] = prop;

        prop = proposalModels[proposalModels.length - 1];
        prop.source = tokensToETHModel;
        proposalModels[proposalModels.length - 1] = prop;

        ISubDAO.SubDAOProposalModel[] memory newProposalModels = new ISubDAO.SubDAOProposalModel[](proposalModels.length + 1);
        for(uint256 i = 0; i < proposalModels.length; i++) {
            newProposalModels[i] = proposalModels[i];
            newProposalModels[i].presetProposals = new bytes32[](newProposalModels[i].presetProposals.length);
        }
        newProposalModels[newProposalModels.length - 1] = lastProposalModel;

        subDAO.setProposalModels(newProposalModels);

        IOrganization(address(subDAO)).stateManager().setUint256(ExternalState.STATEMANAGER_ENTRY_NAME_DELEGATIONS_ATTACH_INSURANCE, delegationsManagerAttachInsurance);

        IOrganization(address(subDAO)).set(IOrganization.Component({
            key : MYSELF_KEY,
            location : address(0),
            active : false,
            log : false
        }));
    }
}