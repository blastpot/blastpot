//               ,--,                                   ,----,                                 ,----,
//            ,---.'|                                 ,/   .`|,-.----.       ,----..         ,/   .`|
//     ,---,. |   | :      ,---,       .--.--.      ,`   .'  :\    /  \     /   /   \      ,`   .'  :
//   ,'  .'  \:   : |     '  .' \     /  /    '.  ;    ;     /|   :    \   /   .     :   ;    ;     /
// ,---.' .' ||   ' :    /  ;    '.  |  :  /`. /.'___,/    ,' |   |  .\ : .   /   ;.  \.'___,/    ,'
// |   |  |: |;   ; '   :  :       \ ;  |  |--` |    :     |  .   :  |: |.   ;   /  ` ;|    :     |
// :   :  :  /'   | |__ :  |   /\   \|  :  ;_   ;    |.';  ;  |   |   \ :;   |  ; \ ; |;    |.';  ;
// :   |    ; |   | :.'||  :  ' ;.   :\  \    `.`----'  |  |  |   : .   /|   :  | ; | '`----'  |  |
// |   :     \'   :    ;|  |  ;/  \   \`----.   \   '   :  ;  ;   | |`-' .   |  ' ' ' :    '   :  ;
// |   |   . ||   |  ./ '  :  | \  \ ,'__ \  \  |   |   |  '  |   | ;    '   ;  \; /  |    |   |  '
// '   :  '; |;   : ;   |  |  '  '--' /  /`--'  /   '   :  |  :   ' |     \   \  ',  /     '   :  |
// |   |  | ; |   ,/    |  :  :      '--'.     /    ;   |.'   :   : :      ;   :    /      ;   |.'
// |   :   /  '---'     |  | ,'        `--'---'     '---'     |   | :       \   \ .'       '---'
// |   | ,'             `--''                                 `---'.|        `---`
// `----'                                                       `---`

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";
import {IBlast} from "./interfaces/IBlast.sol";
import {Blastpot} from "./Blastpot.sol";
import {Owned} from "solmate/auth/Owned.sol";

error MismatchedBidInput();

/// @title Blastpot
/// @notice BlastpotRouter manages bid to the Blastpot roullete-style contract that leverages
///         the entropy of the PYTH network for provable fairness.
///
/// @author Pluto (@homeslashpluto)
contract BlastpotRouter is Owned {
    address public blast;

    constructor(address _blast) Owned(msg.sender) {
        blast = _blast;
    }

    function updateBlast(address _blast) external onlyOwner {
        blast = _blast;
    }

    function claimGas(address to) external onlyOwner returns (uint256 gas) {
        gas = IBlast(blast).claimAllGas(address(this), to);
    }

    /// @notice Bids on multiple pots
    /// @param _pots The pots to bid on
    /// @param _amounts The amounts to bid
    function bid(address[] memory _pots, uint256[] memory _amounts) external payable {
        if (_pots.length != _amounts.length) revert MismatchedBidInput();
        for (uint256 i = 0; i < _pots.length; i++) {
            Blastpot pot = Blastpot(payable(_pots[i]));
            address token = pot.TOKEN();
            IERC20(token).transferFrom(msg.sender, address(this), _amounts[i]);

            if (IERC20(token).allowance(address(this), address(pot)) < _amounts[i]) {
                IERC20(token).approve(address(pot), type(uint256).max);
            }
            pot.bid(msg.sender, _amounts[i]);
        }
    }
}
