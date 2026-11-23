# SellOrPost

A WoW: Forever addon that marks bag items as junk in [Baganator](https://www.curseforge.com/wow/addons/baganator) when TradeSkillMaster says vendoring beats the auction house. You see what to sell at any vendor straight away, instead of mailing it to a posting character just to find it can't be posted.

It only reads TSM: it never mails, posts or sells anything. Baganator doesn't sell junk on its own either.

## How it decides

An item is marked when it has a vendor price and either:

- it is grey (poor quality), or
- it is in a TSM group and the TSM price string `first(post, 0.001)` comes out under 1 copper.

`post` is a custom price source you define in TSM (for example, the net gain per item over vendoring, left empty when a stack earns too little). If your Auctioning operations use `ifgte(first(post, 0.001), 1, 1000, 0)` as the post cap, the items marked here are the ones a post scan would show as "Posting disabled.".

Items in no TSM group are never marked (except greys). Groups you hold can be excluded, greys in them included: the longest matching group path wins, so a subgroup can undo its parent.

If TSM can't answer (not loaded, no `post` source), nothing is marked: you get one chat line per session saying why, and `/sellorpost` shows the last failure.

## Setup

1. Install Baganator and TradeSkillMaster.
2. In Baganator's settings, under Plugins > Junk detection, pick **SellOrPost (TSM post rule)**. Baganator picks it on its own when no other junk plugin was chosen.
3. Optional: show junk in its own section with Baganator's category view.

## Commands

- `/sellorpost` (or `/sop`): lists every stack in your bags to vendor and its vendor value.
- `/sellorpost rules`: the group rules in use.
- `/sellorpost rule <group path> on|off|default`: mark or never mark a group and its subgroups. Subgroups are joined with a backtick, as TSM writes them: ``Materials`Leather``.
- `/sellorpost refresh`: forget cached verdicts (they last two minutes) and redraw the bags.

## Licence

MIT. See `LICENSE`.
