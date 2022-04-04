pragma solidity ^0.8.4;

library PlayerLib {
    // {"bits": "32", "location": [0, 32], "max": "4,294,967,295"}
    function bricks(uint256 _data) internal pure returns (uint256) {
        return (_data >> 224) & 0xffffffff;
    }

    function addBricks(uint256 _data, uint256 _value) internal pure returns (uint256) {
        _value = ((_data >> 224) & 0xffffffff) + _value;
        require(_value <= 0xffffffff, "bricksAdd_outOfBounds");
        return (_data & 0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff) | (_value << 224);
    }

    function subBricks(uint256 _data, uint256 _value) internal pure returns (uint256) {
        _value = ((_data >> 224) & 0xffffffff) - _value;
        return (_data & 0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff) | (_value << 224);
    }

    // {"bits": "8", "location": [32, 40], "max": "255"}
    function purchasedBricks(uint256 _data) internal pure returns (uint256) {
        return (_data >> 216) & 0xff;
    }

    function addPurchasedBricks(uint256 _data, uint256 _value) internal pure returns (uint256) {
        _value = ((_data >> 216) & 0xff) + _value;
        _value = _value <= 0xff ? _value : 0xff; // math min;
        return (_data & 0xffffffff00ffffffffffffffffffffffffffffffffffffffffffffffffffffff) | (_value << 216);
    }

    // {"bits": "16", "location": [40, 56], "max": "65,535"}
    function swappedBricks(uint256 _data) internal pure returns (uint256) {
        return (_data >> 200) & 0xffff;
    }

    function addSwappedBricks(uint256 _data, uint256 _value) internal pure returns (uint256) {
        _value = ((_data >> 200) & 0xffff) + _value;
        _value = _value <= 0xffff ? _value : 0xffff; // math min;
        return (_data & 0xffffffffff0000ffffffffffffffffffffffffffffffffffffffffffffffffff) | (_value << 200);
    }

    // {"bits": "40", "location": [56, 96], "max": "1,099,511,627,775"}
    function coins(uint256 _data) internal pure returns (uint256) {
        return (_data >> 160) & 0xffffffffff;
    }

    function addCoins(uint256 _data, uint256 _value) internal pure returns (uint256) {
        _value = ((_data >> 160) & 0xffffffffff) + _value;
        require(_value <= 0xffffffffff, "coinsAdd_outOfBounds");
        return (_data & 0xffffffffffffff0000000000ffffffffffffffffffffffffffffffffffffffff) | (_value << 160);
    }

    function subCoins(uint256 _data, uint256 _value) internal pure returns (uint256) {
        _value = ((_data >> 160) & 0xffffffffff) - _value;
        return (_data & 0xffffffffffffff0000000000ffffffffffffffffffffffffffffffffffffffff) | (_value << 160);
    }

    // {"bits": "24", "location": [96, 120], "max": "16,777,215"}
    function coinsPerHour(uint256 _data) internal pure returns (uint256) {
        return (_data >> 136) & 0xffffff;
    }

    function setCoinsPerHour(uint256 _data, uint256 _value) internal pure returns (uint256) {
        require(_value <= 0xffffff, "coinsPerHour_outOfBounds");
        return (_data & 0xffffffffffffffffffffffff000000ffffffffffffffffffffffffffffffffff) | (_value << 136);
    }

    // {"bits": "40", "location": [120, 160], "max": "1,099,511,627,775"}
    function uncollectedCoins(uint256 _data) internal pure returns (uint256) {
        return (_data >> 96) & 0xffffffffff;
    }

    function setUncollectedCoins(uint256 _data, uint256 _value) internal pure returns (uint256) {
        require(_value <= 0xffffffffff, "uncollectedCoins_outOfBounds");
        return (_data & 0xffffffffffffffffffffffffffffff0000000000ffffffffffffffffffffffff) | (_value << 96);
    }

    function addUncollectedCoins(uint256 _data, uint256 _value) internal pure returns (uint256) {
        _value = ((_data >> 96) & 0xffffffffff) + _value;
        require(_value <= 0xffffffffff, "uncollectedCoinsAdd_outOfBounds");
        return (_data & 0xffffffffffffffffffffffffffffff0000000000ffffffffffffffffffffffff) | (_value << 96);
    }

    // {"bits": "24", "location": [160, 184], "max": "16,777,215"}
    function collectedCoins(uint256 _data) internal pure returns (uint256) {
        return (_data >> 72) & 0xffffff;
    }

    function addCollectedCoins(uint256 _data, uint256 _value) internal pure returns (uint256) {
        _value = ((_data >> 72) & 0xffffff) + _value;
        _value = _value <= 0xffffff ? _value : 0xffffff; // math min;
        return (_data & 0xffffffffffffffffffffffffffffffffffffffff000000ffffffffffffffffff) | (_value << 72);
    }

    // {"bits": "20", "location": [184, 204], "max": "1,048,575"}
    function coinsHour(uint256 _data) internal pure returns (uint256) {
        return (_data >> 52) & 0xfffff;
    }

    function setCoinsHour(uint256 _data, uint256 _value) internal pure returns (uint256) {
        require(_value <= 0xfffff, "coinsHour_outOfBounds");
        return (_data & 0xffffffffffffffffffffffffffffffffffffffffffffff00000fffffffffffff) | (_value << 52);
    }

    // {"bits": "24", "location": [204, 228], "max": "16,777,215"}
    function uncollectedAirdrop(uint256 _data) internal pure returns (uint256) {
        return (_data >> 28) & 0xffffff;
    }

    function setUncollectedAirdrop(uint256 _data, uint256 _value) internal pure returns (uint256) {
        require(_value <= 0xffffff, "uncollectedAirdrop_outOfBounds");
        return (_data & 0xfffffffffffffffffffffffffffffffffffffffffffffffffff000000fffffff) | (_value << 28);
    }

    // {"bits": "16", "location": [228, 244], "max": "65,535"}
    function airdropDay(uint256 _data) internal pure returns (uint256) {
        return (_data >> 12) & 0xffff;
    }

    function setAirdropDay(uint256 _data, uint256 _value) internal pure returns (uint256) {
        require(_value <= 0xffff, "airdropDay_outOfBounds");
        return (_data & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000fff) | (_value << 12);
    }

    // {"bits": "2", "location": [244, 246], "max": "3"}
    function pendingStarsProfit(uint256 _data) internal pure returns (uint256) {
        return (_data >> 10) & 0x3;
    }

    function setPendingStarsProfit(uint256 _data, uint256 _value) internal pure returns (uint256) {
        require(_value <= 0x3, "pendingStarsProfit_outOfBounds");
        return (_data & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff3ff) | (_value << 10);
    }

    // {"bits": "2", "location": [246, 248], "max": "3"}
    function pendingStarsBuild(uint256 _data) internal pure returns (uint256) {
        return (_data >> 8) & 0x3;
    }

    function setPendingStarsBuild(uint256 _data, uint256 _value) internal pure returns (uint256) {
        require(_value <= 0x3, "pendingStarsBuild_outOfBounds");
        return (_data & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffcff) | (_value << 8);
    }

    // {"bits": "2", "location": [248, 250], "max": "3"}
    function starsCollect(uint256 _data) internal pure returns (uint256) {
        return (_data >> 6) & 0x3;
    }

    function setStarsCollect(uint256 _data, uint256 _value) internal pure returns (uint256) {
        require(_value <= 0x3, "starsCollect_outOfBounds");
        return (_data & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff3f) | (_value << 6);
    }

    // {"bits": "2", "location": [250, 252], "max": "3"}
    function starsBuild(uint256 _data) internal pure returns (uint256) {
        return (_data >> 4) & 0x3;
    }

    function setStarsBuild(uint256 _data, uint256 _value) internal pure returns (uint256) {
        require(_value <= 0x3, "starsBuild_outOfBounds");
        return (_data & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffcf) | (_value << 4);
    }

    // {"bits": "2", "location": [252, 254], "max": "3"}
    function starsSwap(uint256 _data) internal pure returns (uint256) {
        return (_data >> 2) & 0x3;
    }

    function setStarsSwap(uint256 _data, uint256 _value) internal pure returns (uint256) {
        require(_value <= 0x3, "starsSwap_outOfBounds");
        return (_data & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff3) | (_value << 2);
    }

    // {"bits": "2", "location": [254, 256], "max": "3"}
    function starsProfit(uint256 _data) internal pure returns (uint256) {
        return (_data >> 0) & 0x3;
    }

    function setStarsProfit(uint256 _data, uint256 _value) internal pure returns (uint256) {
        require(_value <= 0x3, "starsProfit_outOfBounds");
        return (_data & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc) | (_value << 0);
    }
}

pragma solidity ^0.8.4;

import "./PlayerLib.sol";

contract App {
    using PlayerLib for uint256;

    mapping(address => uint256) players;

    address constant FEE_ADDR = 0x0000000000000000000000000000000000000000;

    event Log(address addr, uint256 player, uint256 commandSize, uint256 command);

    fallback() external payable {
        require(msg.sender == tx.origin, "fallback_onlyEOA");
        uint256 player = players[msg.sender];

        if (player.airdropDay() == 0) {
            player = register(player);
        }
        player = update(player);

        if (msg.value > 0) {
            player = buy(player);
        }

        // run iterator
        uint256 payloadSize = msg.data.length;
        uint256 payloadOffset = 0;

        while (payloadOffset < payloadSize) {
            uint256 commandSize = uint8(msg.data[payloadOffset]);

            require(commandSize > 0 && commandSize <= 32, "commandSize_outOfBounds");
            payloadOffset += 1;

            uint256 command;
            bytes memory b = msg.data[payloadOffset:(payloadOffset + commandSize)];
            assembly {
                command := mload(add(b, 0x20))
            }
            command = command >> ((32 - commandSize) * 8);

            if (commandSize == 1) {
                player = claim(player, command);
            } else if (commandSize == 4) {
                player = swap(player, command);
            } else if (commandSize == 5) {
                player = sell(player, command);
            } else if (commandSize == 15) {
                player = editMap(player, command);
            } else if (commandSize == 24) {
                player = transfer(player, command);
            } // otherwise just log it

            emit Log(msg.sender, player, commandSize, command);
            payloadOffset += commandSize;
        }

        players[msg.sender] = player;
    }

    function register(uint256 _player) internal view returns (uint256) {
        // - start bonus 20 bricks
        // - next day first airdrop
        return _player.addBricks(20).setAirdropDay(block.timestamp / 86400 + 1);
    }

    function update(uint256 _player) internal view returns (uint256) {
        uint256 hourNow = block.timestamp / 3600;
        uint256 hoursPassed = hourNow - _player.coinsHour();

        if (hoursPassed > 0) {
            _player = _player.addUncollectedCoins(_player.coinsPerHour() * hoursPassed).setCoinsHour(hourNow);
        }

        uint256 dayNow = block.timestamp / 86400;
        uint256 airdropDay = _player.airdropDay();

        if (dayNow >= airdropDay && _player.uncollectedAirdrop() == 0) {
            uint256 coins = _player.coinsPerHour();

            // bonus per day 3.5 hours of yield or, if there is no yield, then 0.02 coins
            _player = _player.setUncollectedAirdrop(coins > 0 ? (coins * 35) / 10 : 2);
        }

        return _player;
    }

    function buy(uint256 _player) internal returns (uint256) {
        uint256 bricks = msg.value / 4e15; //  1 matic -> 250 bricks
        require(bricks > 0, "buy_requireNonZero");
        _player = _player.addBricks(bricks).addPurchasedBricks(bricks);
        sendFee(bricks);

        emit Log(msg.sender, _player, 0, bricks);

        return _player;
    }

    function swap(uint256 _player, uint256 _bricks) internal returns (uint256) {
        require(_bricks > 0, "swap_requireNonZero");

        // 0.80 coins -> 1 brick
        _player = _player.subCoins(_bricks * 80).addBricks(_bricks).addSwappedBricks(_bricks);
        if (_player.purchasedBricks() >= 100) {
            sendFee(_bricks);
        }
        return _player;
    }

    function sell(uint256 _player, uint256 _coins) internal returns (uint256) {
        require(_player.purchasedBricks() >= 100, "sell_paywall");
        require(_coins >= 10_00, "sell_tooLittleAmount"); // 10 coins minimum

        uint256 total = address(this).balance / 4e13; // 250.00 coins -> 1 matic
        _coins = _coins <= total ? _coins : total;
        require(_coins > 0, "sell_requireNonZero");

        _player = _player.subCoins(_coins);
        payable(msg.sender).transfer(_coins * 4e13);

        return _player;
    }

    function transfer(uint256 _player, uint256 _command) internal returns (uint256) {
        require(_player.purchasedBricks() >= 100, "transfer_paywall");

        uint256 bricks = _command & type(uint32).max;
        require(bricks >= 100, "transfer_tooLittleAmount");

        // because 20 bricks is a starting bonus
        require(bricks + 20 <= _player.bricks(), "transfer_tooMuchAmount");

        address to = address(uint160(_command >> 32));
        require(msg.sender != to, "transfer_sameAddress");

        uint256 recipient = players[to];
        require(recipient != 0, "transfer_notRegistered");

        _player = _player.setCoinsPerHour(0).subBricks(bricks);
        bricks = (bricks * 9) / 10; // 10% burns
        recipient = recipient.addBricks(bricks);
        players[to] = recipient;

        emit Log(to, recipient, 0, bricks);

        return _player;
    }

    function sendFee(uint256 _bricks) internal {
        if (msg.sender != FEE_ADDR) {
            // 10% fee of bricks in coins
            players[FEE_ADDR] = players[FEE_ADDR].addCoins(_bricks * 10);
        }
    }

    function claim(uint256 _player, uint256 _type) internal view returns (uint256) {
        if (_type == 1) {
            // collect coins
            uint256 coins = _player.uncollectedCoins();
            require(coins > 0, "collect_requireNonZero");
            return _player.addCoins(coins).addCollectedCoins(coins).setUncollectedCoins(0);
        } else if (_type == 2) {
            // daily coin airdrop
            uint256 airdropAmount = _player.uncollectedAirdrop();
            require(airdropAmount > 0, "airdrop_requireNonZero");
            return _player.addCoins(airdropAmount).setUncollectedAirdrop(0).setAirdropDay(block.timestamp / 86400 + 1); // next day
        } else if (_type == 3) {
            // achievement: collector
            uint256 stars = _player.starsCollect();
            uint256 target = _player.collectedCoins();
            if (stars == 0 && target >= 500_00) {
                // target: 500 coins
                // reward: 50 bricks
                return _player.setStarsCollect(1).addBricks(50);
            } else if (stars == 1 && target >= 5_000_00) {
                // target: 5,000 coins
                // reward: 500 bricks
                return _player.setStarsCollect(2).addBricks(500);
            } else if (stars == 2 && target >= 50_000_00) {
                // target: 50,000 coins
                // reward: 5,000 bricks
                return _player.setStarsCollect(3).addBricks(5_000);
            }
        } else if (_type == 4) {
            // achievement: builder
            uint256 stars = _player.starsBuild();
            uint256 target = _player.pendingStarsBuild();
            if (stars == 0 && target >= 1) {
                // reward: 100 bricks
                return _player.setStarsBuild(1).addBricks(100);
            } else if (stars == 1 && target >= 2) {
                // reward: 1,000 bricks
                return _player.setStarsBuild(2).addBricks(1_000);
            } else if (stars == 2 && target == 3) {
                // reward: 10,000 bricks
                return _player.setStarsBuild(3).addBricks(10_000);
            }
        } else if (_type == 5) {
            // achievement: trader
            uint256 stars = _player.starsSwap();
            uint256 target = _player.swappedBricks();
            if (stars == 0 && target >= 500) {
                // target: 500 bricks
                // reward: 100 bricks
                return _player.setStarsSwap(1).addBricks(100);
            } else if (stars == 1 && target >= 5_000) {
                // target: 5,000 bricks
                // reward: 1,000 bricks
                return _player.setStarsSwap(2).addBricks(1_000);
            } else if (stars == 2 && target >= 50_000) {
                // target: 50,000 bricks
                // reward: 10,000 bricks
                return _player.setStarsSwap(3).addBricks(10_000);
            }
        } else if (_type == 6) {
            // achievement: investor
            uint256 stars = _player.starsProfit();
            uint256 target = _player.pendingStarsProfit();
            if (stars == 0 && target >= 1) {
                // reward: 150 bricks
                return _player.setStarsProfit(1).addBricks(150);
            } else if (stars == 1 && target >= 2) {
                // reward: 1,500 bricks
                return _player.setStarsProfit(2).addBricks(1_500);
            } else if (stars == 2 && target == 3) {
                // reward: 15,000 bricks
                return _player.setStarsProfit(3).addBricks(15_000);
            }
        }
        revert("claim_noChanges");
    }

    function editMap(uint256 _player, uint256 _map) internal pure returns (uint256) {
        uint256 count;
        uint256 bricks;
        uint256 coinsPerHour;
        uint256 c0;
        uint256 c1;
        uint256 c2;
        uint256 c3;

        // 1 lvl
        count = (_map >> 112) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 1; // per hour: 0.01 coins
            bricks += count * 20; // cost: 20 bricks
            c0 += count; // 0 star
        }
        // 2 lvl
        count = (_map >> 104) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 4; // per hour: 0.04 coins
            bricks += count * 70; // cost: 70 bricks
            c0 += count;
        }
        // 3 lvl
        count = (_map >> 96) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 11; // per hour: 0.11 coins
            bricks += count * 180; // cost: 180 bricks
            c0 += count;
        }
        // 4 lvl
        count = (_map >> 88) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 22; // per hour: 0.22 coins
            bricks += count * 340; // cost: 340 bricks
            c1 += count; // 1 star
        }
        // 5 lvl
        count = (_map >> 80) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 46; // per hour: 0.46 coins
            bricks += count * 700; // cost: 700 bricks
            c1 += count;
        }
        // 6 lvl
        count = (_map >> 72) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 1_00; // per hour: 1 coin
            bricks += count * 1_500; // cost: 1,500 bricks
            c2 += count; // 2 stars
        }
        // 7 lvl
        count = (_map >> 64) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 2_72; // per hour: 2.72 coins
            bricks += count * 4_000; // cost: 4,000 bricks
            c2 += count;
        }
        // 8 lvl
        count = (_map >> 56) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 5_54; // per hour: 5.54 coins
            bricks += count * 8_000; // cost: 8,000 bricks
            c2 += count;
        }
        // 9 lvl
        count = (_map >> 48) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 10_60; // per hour: 10.6 coins
            bricks += count * 15_000; // cost: 15,000 bricks
            c2 += count;
        }
        // 10 lvl
        count = (_map >> 40) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 18_00; // per hour: 18 coins
            bricks += count * 25_000; // cost: 25,000 bricks
            c3 += count; // 3 stars
        }
        // 11 lvl
        count = (_map >> 32) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 36_70; // per hour: 36,7 coins
            bricks += count * 50_000; // cost: 50,000 bricks
            c3 += count;
        }
        // 12 lvl
        count = (_map >> 24) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 75_00; // per hour: 75 coins
            bricks += count * 100_000; // cost: 100,000 bricks
            c3 += count;
        }
        // 13 lvl
        count = (_map >> 16) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 153_00; // per hour: 153 coins
            bricks += count * 200_000; // cost: 200,000 bricks
            c3 += count;
        }
        // 14 lvl
        count = (_map >> 8) & 0xff;
        if (count > 0) {
            coinsPerHour += count * 234_00; // per hour: 234 coins
            bricks += count * 300_000; // cost: 300,000 bricks
            c3 += count;
        }
        // 15 lvl
        count = _map & 0xff;
        if (count > 0) {
            coinsPerHour += count * 400_00; // per hour: 400 coins
            bricks += count * 500_000; // cost: 500,000 bricks
            c3 += count;
        }

        require(c0 + c1 + c2 + c3 <= 60, "setMap_tooManyBuildings");

        require(_player.bricks() >= bricks, "setMap_notEnoughBricks");
        _player = _player.setCoinsPerHour(coinsPerHour);

        uint256 stars = _player.pendingStarsBuild();
        if (stars == 0 && c1 + c2 + c3 >= 3) stars = 1; // target: 3 buildings >= 4 lvl
        if (stars == 1 && c2 + c3 >= 7) stars = 2; // target:  7 buildings >= 6 lvl
        if (stars == 2 && c3 >= 4) stars = 3; // target:  4 buildings >= 10 lbl
        _player = _player.setPendingStarsBuild(stars);

        stars = _player.pendingStarsProfit();
        if (stars == 0 && coinsPerHour >= 1_00) stars = 1; // target: 1 coins / hr
        if (stars == 1 && coinsPerHour >= 10_00) stars = 2; // target: 10 coins / hr
        if (stars == 2 && coinsPerHour >= 100_00) stars = 3; // target:  100 coins / hr
        _player = _player.setPendingStarsProfit(stars);

        return _player;
    }
}
