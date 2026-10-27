# Changelog

Everything players will notice, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- The addon list now calls Circ "Circ - Trade Ledger", the same word the window uses.

### Fixed

- Searching no longer suggests items that don't exist in the game, such as test gear and
  leftovers with names like "zzOLD..." or "S03 - ...".
- With the Settings tab open, `/circ nudges`, `/circ tooltip` and `/circ minimap` now
  update its checkboxes right away.
- After a ledger's channel was taken over twice in one day, Circ stopped watching for
  takeovers until the next reload. It now repeats its advice at most every 5 minutes and
  offers to move the ledger again once the day has passed.
- When no recipes are recognized after a scan, the Prices tab now says where to report it
  (github.com/LatentRune/circ/issues) instead of asking to "send the lines".

## [0.13.2] - test build

The last build before the public repository.
