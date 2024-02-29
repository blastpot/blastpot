![blastpot_logo](https://github.com/blastpot/blastpot/assets/75406541/c58a7645-d3ed-4d59-aa62-2f61e79992aa)

# Blastpot

![ci](https://github.com/blastpot/blastpot/actions/workflows/CI.yml/badge.svg)
[![codecov](https://codecov.io/gh/blastpot/blastpot/graph/badge.svg?token=N7J7YYW291)](https://codecov.io/gh/blastpot/blastpot)

## Abstract

## Motivation

## Mechanism

### Blastpot

![image](https://github.com/blastpot/blastpot/assets/75406541/084aca83-bd6a-4154-9943-1f54136859c9)

For each iteration of a pot bids are lined up sequentially defining their range. A user's bid range is defined by the last upper limit of the bid range plus the user's bid amount. When a random number is chosen it constrains around the bid range max to determine the winner.

![image](https://github.com/blastpot/blastpot/assets/75406541/43cf5c68-2611-4c1c-a26b-73982b258f83)

If the random number lies within your specified bid range then you are the winner of the pot.

### Yield Pot

![image](https://github.com/blastpot/blastpot/assets/75406541/a297071c-2ee3-4dd6-8897-4cb985d3d41f)

To allow for removal while maintaining efficient bid range management a red black tree is used to order all of the bids. Each bid must be unique because of this. 

![image](https://github.com/blastpot/blastpot/assets/75406541/e7f474f0-5c3c-48c3-8176-62fe985896c0)

Similar to the vanilla blastpot, the tree is transformed into a sequential bid range. From there the random number provided by PYTH is used to determine the winning bid range.

## Developer Guide

### Running Tests

[Install Foundry](https://github.com/foundry-rs/foundry/tree/master/foundryup)

In order to run unit tests, run:

```sh
forge install
forge test
```

For longer fuzz campaigns, run:

```sh
FOUNDRY_PROFILE="intense" forge test
```

### Running Slither

After installing [Poetry](https://python-poetry.org/docs/#installing-with-the-official-installer) and [Slither](https://github.com/crytic/slither#how-to-install) run:
[Slither on Apple Silicon](https://github.com/crytic/slither/issues/1051)
```sh
poetry install
poetry shell
slither src/ --config-file slither.config.json
```


### Updating Gas Snapshots

To update the gas snapshots, run:

```sh
forge snapshot
```

### Generating Coverage Report

To see project coverage, run:

```shell
forge coverage
```

## License

[MIT](https://github.com/blastpot/blastpot/blob/master/LICENSE) © 2024 Blastpot