// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract KingdomOfSolidity is AccessControl, Pausable, ReentrancyGuard {

    uint256 public constant MAX_BUILDING_LEVEL = 10;
    uint256 public constant BASE_UPGRADE_COST = 50; 
    uint256 public constant MARKET_FEE_PERCENT = 5; 
    
    error AlreadyHasKingdom();
    error KingdomDoesNotExist();
    error InvalidKingdomName();
    error InsufficientResources();
    error MaxLevelReached();
    error InvalidWorkerDistribution();
    error CannotAttackSelf();
    error TargetHasNoArmy();
    error InvalidResourceType();
    error InvalidExchange();

    enum BuildingType { Sawmill, Mine, GoldMine, Farm, Barracks, Walls, Academy }
    enum ResourceType { Gold, Wood, Stone, Food }
    enum TroopType { Swordsman, Archer, Knight }
    enum TechType { Military, Engineering, Economics, Agriculture }
    enum GameEvent { None, DoubleResource, BuildDiscount, TroopDiscount, HighWinReward }

    struct Army {
        uint256 swordsmen;
        uint256 archers;
        uint256 knights;
    }

    struct Buildings {
        uint256 sawmill;
        uint256 mine;
        uint256 goldMine;
        uint256 farm;
        uint256 barracks;
        uint256 walls;
        uint256 academy;
    }

    struct Workers {
        uint256 InSawmill;
        uint256 InMine;
        uint256 InGoldMine;
        uint256 InFarm;
    }

    struct Technologies {
        uint256 military;   
        uint256 engineering; 
        uint256 economics;   
        uint256 agriculture; 
    }

    struct Kingdom {
        string name;
        address owner;
        uint256 level;
        uint256 gold;
        uint256 wood;
        uint256 stone;
        uint256 food;
        uint256 population;
        uint256 happiness;
        uint256 freeWorkers;
        uint256 lastCollectTime;
        bool exists;
        Army army;
        Buildings buildings;
        Workers workers;
        Technologies techs;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant EVENT_MANAGER_ROLE = keccak256("EVENT_MANAGER_ROLE");
    
    mapping(address => Kingdom) public kingdoms;
    address[] public kingdomAddresses;

    uint256 public treasuryGold;
    
    GameEvent public currentEvent = GameEvent.None;

    event KingdomCreated(address indexed owner, string name);
    event ResourcesCollected(address indexed owner, uint256 gold, uint256 wood, uint256 stone, uint256 food);
    event BuildingUpgraded(address indexed owner, BuildingType building, uint256 newLevel);
    event WorkersDistributed(address indexed owner, uint256 sawmill, uint256 mine, uint256 goldMine, uint256 farm);
    event ArmyRecruited(address indexed owner, TroopType troop, uint256 count);
    event BattleExecuted(address indexed attacker, address indexed defender, string result, uint256 goldStolen, uint256 woodStolen);
    event TechResearched(address indexed owner, TechType tech, uint256 newLevel);
    event MarketTraded(address indexed trader, ResourceType sellRes, ResourceType buyRes, uint256 sellAmount, uint256 buyAmount);
    event TreasuryFunded(uint256 amountGold);
    event GameEventStarted(GameEvent activeEvent);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MODERATOR_ROLE, msg.sender);
        _grantRole(EVENT_MANAGER_ROLE, msg.sender);
    }

    modifier onlyKingdomOwner() {
        if (!kingdoms[msg.sender].exists) revert KingdomDoesNotExist();
        _;
    }

    function createKingdom(string calldata _name) external whenNotPaused {
        if (kingdoms[msg.sender].exists) revert AlreadyHasKingdom();
        if (bytes(_name).length == 0 || bytes(_name).length > 32) revert InvalidKingdomName();

        Kingdom storage k = kingdoms[msg.sender];
        k.name = _name;
        k.owner = msg.sender;
        k.level = 1;
        k.gold = 500;
        k.wood = 500;
        k.stone = 500;
        k.food = 500;
        k.population = 20;
        k.freeWorkers = 10;
        k.happiness = 100;
        k.lastCollectTime = block.timestamp;
        k.exists = true;
        k.buildings.sawmill = 1;
        k.buildings.mine = 1;
        k.buildings.goldMine = 1;
        k.buildings.farm = 1;
        k.buildings.walls = 1;

        kingdomAddresses.push(msg.sender);

        emit KingdomCreated(msg.sender, _name);
    }

    function collectResources() public onlyKingdomOwner whenNotPaused nonReentrant {
        Kingdom storage k = kingdoms[msg.sender];
        uint256 timePassed = block.timestamp - k.lastCollectTime;
        if (timePassed == 0) return;
        uint256 minutesPassed = timePassed / 60;
        if (minutesPassed == 0) return;

        uint256 woodProduced;
        uint256 stoneProduced;
        uint256 goldProduced;
        uint256 foodProduced;

        {
            woodProduced = minutesPassed * (k.buildings.sawmill * 2 + k.workers.InSawmill * 5);
            stoneProduced = minutesPassed * (k.buildings.mine * 2 + k.workers.InMine * 5);
            goldProduced = minutesPassed * (k.buildings.goldMine * 1 + k.workers.InGoldMine * 3);
            foodProduced = minutesPassed * (k.buildings.farm * 3 + k.workers.InFarm * 6);

            uint256 ecoTech = k.techs.economics * 10;
            woodProduced += (woodProduced * ecoTech) / 100;
            stoneProduced += (stoneProduced * ecoTech) / 100;
            goldProduced += (goldProduced * ecoTech) / 100;
            foodProduced += (foodProduced * (k.techs.agriculture * 15)) / 100;

            if (currentEvent == GameEvent.DoubleResource) {
                woodProduced *= 2;
                stoneProduced *= 2;
                goldProduced *= 2;
                foodProduced *= 2;
            }
        }

        k.wood += woodProduced;
        k.stone += stoneProduced;
        k.gold += goldProduced;
        k.food += foodProduced;
        k.lastCollectTime = block.timestamp;

        emit ResourcesCollected(msg.sender, goldProduced, woodProduced, stoneProduced, foodProduced);
    }

    function distributeWorkers(uint256 _saw, uint256 _mine, uint256 _gold, uint256 _farm) external onlyKingdomOwner whenNotPaused {
        Kingdom storage k = kingdoms[msg.sender];
        collectResources(); 

        uint256 totalNeeded = _saw + _mine + _gold + _farm;
        uint256 maxWorkers = k.population / 2; 

        if (totalNeeded > maxWorkers) revert InvalidWorkerDistribution();

        k.workers.InSawmill = _saw;
        k.workers.InMine = _mine;
        k.workers.InGoldMine = _gold;
        k.workers.InFarm = _farm;
        k.freeWorkers = maxWorkers - totalNeeded;

        emit WorkersDistributed(msg.sender, _saw, _mine, _gold, _farm);
    }

    function upgradeBuilding(BuildingType _type) external onlyKingdomOwner whenNotPaused {
        Kingdom storage k = kingdoms[msg.sender];
        collectResources();

        uint256 currentLvl = _getBuildingLevel(k, _type);
        if (currentLvl >= MAX_BUILDING_LEVEL) revert MaxLevelReached();

        uint256 cost = (currentLvl + 1) * BASE_UPGRADE_COST;
        if (currentEvent == GameEvent.BuildDiscount) {
            cost = (cost * 80) / 100; 
        }

        if (k.wood < cost || k.stone < cost || k.gold < cost) revert InsufficientResources();

        k.wood -= cost;
        k.stone -= cost;
        k.gold -= cost;
        
        uint256 fee = (cost * MARKET_FEE_PERCENT) / 100;
        treasuryGold += fee;
        emit TreasuryFunded(fee);

        _setBuildingLevel(k, _type, currentLvl + 1);
        k.population += 5; 

        emit BuildingUpgraded(msg.sender, _type, currentLvl + 1);
    }

    function recruitTroops(TroopType _troop, uint256 _count) external onlyKingdomOwner whenNotPaused {
        if (_count == 0) return;
        Kingdom storage k = kingdoms[msg.sender];
        
        uint256 goldCost; uint256 foodCost;
        if (_troop == TroopType.Swordsman) { goldCost = 20 * _count; foodCost = 10 * _count; }
        else if (_troop == TroopType.Archer) { goldCost = 30 * _count; foodCost = 15 * _count; }
        else { goldCost = 60 * _count; foodCost = 30 * _count; } 

        if (currentEvent == GameEvent.TroopDiscount) {
            goldCost = (goldCost * 75) / 100;
        }

        if (k.gold < goldCost || k.food < foodCost) revert InsufficientResources();

        k.gold -= goldCost;
        k.food -= foodCost;

        if (_troop == TroopType.Swordsman) k.army.swordsmen += _count;
        else if (_troop == TroopType.Archer) k.army.archers += _count;
        else k.army.knights += _count;

        emit ArmyRecruited(msg.sender, _troop, _count);
    }

    function researchTechnology(TechType _tech) external onlyKingdomOwner whenNotPaused {
        Kingdom storage k = kingdoms[msg.sender];
        if (k.buildings.academy == 0) revert InsufficientResources(); 

        uint256 currentTechLvl = _getTechLevel(k, _tech);
        uint256 cost = (currentTechLvl + 1) * 150;

        if (k.gold < cost || k.stone < cost) revert InsufficientResources();

        k.gold -= cost;
        k.stone -= cost;

        _setTechLevel(k, _tech, currentTechLvl + 1);

        emit TechResearched(msg.sender, _tech, currentTechLvl + 1);
    }

    function tradeResources(ResourceType _sell, ResourceType _buy, uint256 _amount) external onlyKingdomOwner whenNotPaused nonReentrant {
        if (_amount == 0) return;
        if (_sell == _buy) revert InvalidExchange();
        
        Kingdom storage k = kingdoms[msg.sender];
        collectResources();

        uint256 sellBalance = _getResourceBalance(k, _sell);
        if (sellBalance < _amount) revert InsufficientResources();

        uint256 boughtAmount = _amount / 2;
        if (boughtAmount == 0) revert InvalidExchange();

        uint256 fee = (boughtAmount * MARKET_FEE_PERCENT) / 100;
        uint256 finalReceiveAmount = boughtAmount - fee;

        _subResource(k, _sell, _amount);
        _addResource(k, _buy, finalReceiveAmount);

        if (_buy == ResourceType.Gold && fee > 0) {
            treasuryGold += fee;
            emit TreasuryFunded(fee);
        }

        emit MarketTraded(msg.sender, _sell, _buy, _amount, finalReceiveAmount);
    }

    function attack(address _defender) external onlyKingdomOwner whenNotPaused nonReentrant {
        if (_defender == msg.sender) revert CannotAttackSelf();
        if (!kingdoms[_defender].exists) revert KingdomDoesNotExist();

        collectResources();
        _collectResourcesForAddress(_defender);

        Kingdom storage attacker = kingdoms[msg.sender];
        Kingdom storage defender = kingdoms[_defender];

        uint256 attackPower;
        uint256 defensePower;

    
        {
            attackPower = (attacker.army.swordsmen * 15) + 
                          (attacker.army.archers * 12) + 
                          (attacker.army.knights * 35);

            if (attackPower == 0) revert TargetHasNoArmy();

            attackPower += (attackPower * (attacker.techs.military * 10)) / 100;

            defensePower = (defender.army.swordsmen * 15) + 
                           (defender.army.archers * 12) + 
                           (defender.army.knights * 35);
                                   
            defensePower += defender.buildings.walls * 30;
            defensePower += (defensePower * (defender.techs.engineering * 12)) / 100;

            uint256 randomMultiplier = 90 + (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % 21);
            attackPower = (attackPower * randomMultiplier) / 100;
        }

        uint256 goldStolen = 0;
        uint256 woodStolen = 0;

        if (attackPower > defensePower) {
            uint256 stealPercent = currentEvent == GameEvent.HighWinReward ? 40 : 25;
            
            goldStolen = (defender.gold * stealPercent) / 100;
            woodStolen = (defender.wood * stealPercent) / 100;

            defender.gold -= goldStolen;
            defender.wood -= woodStolen;

            attacker.gold += goldStolen;
            attacker.wood += woodStolen;

            _applyArmyLosses(attacker, 15);
            _applyArmyLosses(defender, 50);

            emit BattleExecuted(msg.sender, _defender, "Attacker Won", goldStolen, woodStolen);
        } else {
            _applyArmyLosses(attacker, 60);
            _applyArmyLosses(defender, 10);

            emit BattleExecuted(msg.sender, _defender, "Defender Defended", 0, 0);
        }
    }

    function setGameEvent(GameEvent _event) external onlyRole(EVENT_MANAGER_ROLE) {
        currentEvent = _event;
        emit GameEventStarted(_event);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function _getBuildingLevel(Kingdom storage k, BuildingType _type) internal view returns (uint256) {
        if (_type == BuildingType.Sawmill) return k.buildings.sawmill;
        if (_type == BuildingType.Mine) return k.buildings.mine;
        if (_type == BuildingType.GoldMine) return k.buildings.goldMine;
        if (_type == BuildingType.Farm) return k.buildings.farm;
        if (_type == BuildingType.Barracks) return k.buildings.barracks;
        if (_type == BuildingType.Walls) return k.buildings.walls;
        return k.buildings.academy;
    }

    function _setBuildingLevel(Kingdom storage k, BuildingType _type, uint256 _level) internal {
        if (_type == BuildingType.Sawmill) k.buildings.sawmill = _level;
        else if (_type == BuildingType.Mine) k.buildings.mine = _level;
        else if (_type == BuildingType.GoldMine) k.buildings.goldMine = _level;
        else if (_type == BuildingType.Farm) k.buildings.farm = _level;
        else if (_type == BuildingType.Barracks) k.buildings.barracks = _level;
        else if (_type == BuildingType.Walls) k.buildings.walls = _level;
        else if (_type == BuildingType.Academy) k.buildings.academy = _level;
    }

    function _getTechLevel(Kingdom storage k, TechType _tech) internal view returns (uint256) {
        if (_tech == TechType.Military) return k.techs.military;
        if (_tech == TechType.Engineering) return k.techs.engineering;
        if (_tech == TechType.Economics) return k.techs.economics;
        return k.techs.agriculture;
    }

    function _setTechLevel(Kingdom storage k, TechType _tech, uint256 _level) internal {
        if (_tech == TechType.Military) k.techs.military = _level;
        else if (_tech == TechType.Engineering) k.techs.engineering = _level;
        else if (_tech == TechType.Economics) k.techs.economics = _level;
        else if (_tech == TechType.Agriculture) k.techs.agriculture = _level;
    }

    function _getResourceBalance(Kingdom storage k, ResourceType _res) internal view returns (uint256) {
        if (_res == ResourceType.Gold) return k.gold;
        if (_res == ResourceType.Wood) return k.wood;
        if (_res == ResourceType.Stone) return k.stone;
        return k.food;
    }

    function _addResource(Kingdom storage k, ResourceType _res, uint256 _amount) internal {
        if (_res == ResourceType.Gold) k.gold += _amount;
        else if (_res == ResourceType.Wood) k.wood += _amount;
        else if (_res == ResourceType.Stone) k.stone += _amount;
        else if (_res == ResourceType.Food) k.food += _amount;
    }

    function _subResource(Kingdom storage k, ResourceType _res, uint256 _amount) internal {
        if (_res == ResourceType.Gold) k.gold -= _amount;
        else if (_res == ResourceType.Wood) k.wood -= _amount;
        else if (_res == ResourceType.Stone) k.stone -= _amount;
        else if (_res == ResourceType.Food) k.food -= _amount;
    }

    function _applyArmyLosses(Kingdom storage k, uint256 percent) internal {
        k.army.swordsmen -= (k.army.swordsmen * percent) / 100;
        k.army.archers -= (k.army.archers * percent) / 100;
        k.army.knights -= (k.army.knights * percent) / 100;
    }

    function _collectResourcesForAddress(address _user) internal {
        Kingdom storage k = kingdoms[_user];
        uint256 timePassed = block.timestamp - k.lastCollectTime;
        if (timePassed == 0) return;
        uint256 minutesPassed = timePassed / 60;
        if (minutesPassed == 0) return;

        uint256 woodProduced;
        uint256 stoneProduced;
        uint256 goldProduced;
        uint256 foodProduced;

        {
            woodProduced = minutesPassed * (k.buildings.sawmill * 2 + k.workers.InSawmill * 5);
            stoneProduced = minutesPassed * (k.buildings.mine * 2 + k.workers.InMine * 5);
            goldProduced = minutesPassed * (k.buildings.goldMine * 1 + k.workers.InGoldMine * 3);
            foodProduced = minutesPassed * (k.buildings.farm * 3 + k.workers.InFarm * 6);

            uint256 ecoTech = k.techs.economics * 10;
            woodProduced += (woodProduced * ecoTech) / 100;
            stoneProduced += (stoneProduced * ecoTech) / 100;
            goldProduced += (goldProduced * ecoTech) / 100;
            foodProduced += (foodProduced * (k.techs.agriculture * 15)) / 100;

            if (currentEvent == GameEvent.DoubleResource) {
                woodProduced *= 2;
                stoneProduced *= 2;
                goldProduced *= 2;
                foodProduced *= 2;
            }
        }

        k.wood += woodProduced;
        k.stone += stoneProduced;
        k.gold += goldProduced;
        k.food += foodProduced;
        k.lastCollectTime = block.timestamp;
    }
}
