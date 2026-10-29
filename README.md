# Trick or Treat

A Halloween deck for Balatro. Every blind you select flips a card: Trick or Treat.

## What it does

Pick the **Trick or Treat Deck** at the start of a run. Every time you select a blind (Small, Big or Boss), a card flips in the middle of the screen. It's 50/50:

- **Treat: a Candy.** It copies the Joker to its right, the same way Blueprint does. It's Negative, so it doesn't take a Joker slot, and it melts after 3 rounds.
- **Trick: a Ghost.** It possesses one of your Jokers at random, and that Joker is debuffed. It's Negative, so it doesn't take a Joker slot, and it leaves after 3 rounds and lets go of the Joker.

Skipped blinds don't flip. Every other deck plays exactly as normal.

## How it plays

- **A round is one blind played.** The blind a Candy or Ghost arrives on counts as round 1. Each card shows how long it has left.
- **Candy lands on the right end of your Jokers.** Drag it to the left of the Joker you want to copy. Candies chain like Blueprints, and Blueprint and Brainstorm can copy a Candy.
- **A Ghost holds on to its Joker.** Moving the Ghost doesn't change anything. If you sell the possessed Joker, or it gets destroyed, the Ghost jumps to another one.
- **No Joker to possess?** The Ghost waits and takes the next Joker you get.
- **Two Ghosts never share a Joker.**
- **A Ghost cancels a Candy.** If a Ghost possesses the Joker a Candy is copying, the Candy copies nothing.
- **Ghosts can't be sold or destroyed.** That includes Ceremonial Dagger, Madness, Ankh and Hex.
- **Candy and Ghosts only come from the flip.** They never show up in the shop, in packs, or from Judgement. Invisible Joker and Ankh won't copy them.
- **Both sell for $0.** Only Candy can actually be sold.

## Installation

1. Install [Steamodded](https://github.com/Steamodded/smods) 1.0.0~BETA-1620a or newer.
2. Download the latest release, unzip it, and put the folder in your `Mods` folder:

```
Mods/
  TrickOrTreat/
    TrickOrTreat.lua
    TrickOrTreat.json
    assets/
      1x/candy_ghost_jokers.png
      1x/deck_back.png
      2x/candy_ghost_jokers.png
      2x/deck_back.png
```

### Config

- **Candy melts after** (default 3 rounds)
- **Ghost leaves after** (default 3 rounds)

These apply to Candies and Ghosts that arrive after the change.

## License

MIT
