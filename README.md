# Autoslip-Roam
![Version](https://img.shields.io/static/v1?label=autoslip-roam&message=3.0.0&color=brightcolor)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Emacs](https://img.shields.io/badge/Emacs-27.1+-blueviolet.svg)](https://www.gnu.org/software/emacs/)
[![org-roam](https://img.shields.io/badge/org--roam-2.0+-green.svg)](https://www.orgroam.com/)

Automatic folgezettel (computer-compatible Luhmann-style) bidirectional link generation for [org-roam](https://www.orgroam.com/).
This package uses the folgezettel index to determine parent-child relationships and automatically creates directional links based on those relationships.
The index is placed before the note title and is compatible with the org-roam file-naming system.
It is also compatible with printing the note for storage in a paper zettelkasten.
Even though the zettelkasten grows organically as new notes are inserted anywhere in the knowledge graph, the index determines the linear order of the notes for storage in paper form.

## What problems are addressed by this plugin?

### True automation of bidirectional linking
Electronic zettelkastens rely on reciprocal hyperlinks to relate parent and child notes. 
The manual insertion of these links is error-prone and time-consuming. 
This package provides true automation for creating these links by leveraging the parent-child relationship defined in the indexing system. 
You do not need to click a button to add the links; they are added automatically, out of sight and out of mind.

### Bridge to a paper-based zettelkasten
The folgezettel index determines the order in which a new note is to be placed in a series of notes in a paper-based zettelkasten.
The ability to print these indices with the notes provides a bridge between electronic and paper-based zettelkastens.
This bridge supports hybrid, mirror, and project-based approaches.
In the project-based approach, notes on paper are used during the assembly of manuscripts, where they are ordered and rearranged on a physical tabletop or corkboard.

Most electronic zettelkastens rely either on timestamps or a database ID to identify each unique note. 
This approach is hopeless if one wants to print out their zettels to store them in a paper-based zettelkasten. 
Fans of the paper-based approach may object that you should write these notes by hand to better integrate the information into your memory. 
This may be true, but more frequent perusal of the paper zettelkasten may be compensatory and possibly more effective in the long term. 
Often, there is just not enough time available to rewrite the notes by hand.

There is no rule against mixing handwritten and printed notes together. The inclusion of the folgezettel index in the title indicates where to store the note. Paper-based zettelkastens rely on the folgezettel index (or alternatively the Luhmann-style index or the Scott Scheper index, which are not computer-compatible) to specify the linear order of note storage. There is a one-to-one mapping between the zettelkasten graph and the order in which the notes are stored.

This approach supports a hybrid zettelkasten, with part electronic and part paper-based. Of course, it also supports a mirrored zettelkasten in both paper and electronic form.

You can print a note on US letter-size paper, fold it in half with the title facing outward, and store it in this zettelkasten. This folded paper corresponds to A5-sized paper. Luhmann used the smaller A6-sized paper.

If the note spans multiple pages, as may be the case with a structure, keyword, or hub note, you can fold the pages in half together. You can also save paper and space by printing double-sided, resulting in a booklet with two pages per side. For example, an eight-page note would span both sides of two sheets of US letter paper. The text will be rotated by 90°, so you will need to write the index across the top of the outside side of the folded paper. I favor this approach over index cards because it provides more space and because US Letter printer paper is cheaper and more readily available. This more practical approach reduces the friction of adding new notes to your paper-based zettelkasten.

Obsidian offers a fantastic, infinite canvas for displaying and organizing notes in all kinds of configurations. The ability to print out the notes opens up the opportunity to work with paper versions on a large tabletop or a corkboard. Sometimes, changing the context from electronic to physical can stimulate the mind. This alternative physical approach to arranging notes is useful when assembling a manuscript. You can use the canvas to combine all the notes you want to print. This could be useful for one-off tasks, such as assembling a manuscript, where you may discard the paper notes when you are done.

### Adding some order to the zettelkasten
Some hierarchical order is necessary to ease navigation of the zettelkasten because keyword searching does not guarantee that you will retrieve all relevant notes. Luhmann's paper version had order provided by his indexing system. Disorder was provided by cross-links between notes. According to Luhmann, you need both order and disorder. The optimal mix of order and disorder will probably vary with project and user. Luhmann's indexing system started with root nodes numbered with integers, separated by backslashes from the indices of the descendant nodes. I recommend spending an hour early on identifying a list of areas of knowledge you want to store notes on in the zettelkasten. These areas can serve as your root nodes. You can expand this list as your interests evolve.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Folgezettel Address Format](#folgezettel-address-format)
- [Usage](#usage)
- [Configuration](#configuration)
- [Commands](#commands)
- [Testing](#testing)
- [Info Documentation](#info-documentation)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Overview

Autoslip-roam brings the folgezettel numbering system to org-roam. 
When you create a note with a folgezettel address in its title (e.g., "1.2a My Topic"), the package automatically:

1. Identifies the parent note based on the address hierarchy.
2. Inserts a backlink to the parent in the new note.
3. Inserts a forward link to the child in the parent note.

This creates a navigable hierarchy of interconnected notes.

## Features

- **Automatic Bidirectional Linking** - Parent and child notes are linked automatically.
- **Narrowing of Search Results in Minibuffer** - The index narrows the search results in the minibuffer as it is extended, thereby facilitating movement down the chain of thought.
- **Address Validation** - Prevents invalid folgezettel addresses.
- **Duplicate Detection** - Warns if an address is already in use.
- **Smart Suggestions** - Suggests the next available child address.
- **Cross-Reference Links** - Automatic reciprocal links when inserting manual links.
- **Database Sync** - Immediate visibility in org-roam graph and queries.
- **Extended Alphabet** - Supports aa, ab, ..., zz, aaa, ... after z.
- **Navigation Commands** - Jump to parent, list children, or show a tree view of the vault.
- **Chain of Thought** - Show every ancestor from the current note to its root in a dedicated buffer, and optionally insert that chain into the current note.
- **Cross-linked Chains of Thought** - For every note linked under Cross References, show its own ancestor chain so the cross-link is understood in context rather than by name alone.
- **Reparenting** - Move a note (or a whole subtree) to a new folgezettel address, with links and file names kept in sync.
- **Quiet Link Storage** - Optional property-drawer mode that keeps parent and child references out of the visible body of the note, reducing merge-conflict surface.

## Installation

### Requirements

- Emacs 27.1 or later
- org-roam 2.0 or later

### From MELPA (Recommended)

Once available on MELPA:

```elisp
M-x package-install RET autoslip-roam RET
```

### Manual Installation

1. Clone the repository:

```bash
git clone https://github.com/MooersLab/autoslip-roam.git
cd autoslip-roam
```

2. Add to your Emacs configuration:

```elisp
(add-to-list 'load-path "/path/to/autoslip-roam")
(require 'autoslip-roam)
(autoslip-roam-mode 1)
```

### Using use-package

```elisp
(use-package autoslip-roam
  :after org-roam
  :load-path "/path/to/autoslip-roam"
  :config
  (autoslip-roam-mode 1)
  :bind
  (:map org-mode-map
        ("C-c n c" . autoslip-roam-insert-next-child)
        ("C-c n p" . autoslip-roam-add-backlink-to-parent)))
```

## Quick Start

### 1. Enable the Mode

```elisp
(require 'autoslip-roam)
(autoslip-roam-mode 1)
```

### 2. Create a Root Note

```
M-x org-roam-node-find RET
Title: 1. Introduction to My Topic
```

Root note titles carry a trailing period after the integer (e.g., `1.`), matching the style used in numbered outlines like `1. Crystallography`. Legacy titles without the trailing period (e.g., `1 Introduction`) are still recognized and are treated as equivalent to the canonical form.

### 3. Create a Child Note

With the root note open:

```
M-x autoslip-roam-insert-next-child RET
```

The package suggests `1.1` as the first child. Enter a title when prompted.

### 4. Verify the Links

**Child note (1.1 First Subtopic):**
```org
#+title: 1.1 First Subtopic

** Parent Note
[[id:abc123][Parent note]]

Your content here...
```

**Parent note (1. Introduction to My Topic):**
```org
#+title: 1. Introduction to My Topic

Your content here...

** Child Notes
[[id:def456][1.1 First Subtopic]]
```

## Folgezettel Address Format

### Address Hierarchy

| Address | Description |
|---------|-------------|
| `1.` | Root note |
| `1.2` | Second subtopic of note 1 |
| `1.2a` | First letter branch of 1.2 |
| `1.2aa` | 27th child of 1.2 (after z) |
| `1.2a3` | Third numeric child of 1.2a |
| `1.2a3b` | Second letter child of 1.2a3 |

### Rules

1. **Start with a number** - All addresses begin with a root number
2. **Root notes carry a trailing period** - Canonical root form is `N.` (e.g., `1.`). Legacy bare-integer titles (`1 Crystallography`) are still accepted and treated as equivalent.
3. **Single period only** - Only one `.` allowed (the one separating the root from the first subtopic, or the one marking a root note itself)
4. **Alternation** - Numbers and letters must alternate after the period
5. **Lowercase only** - Use lowercase letters (a-z)
6. **Extended alphabet** - After z comes aa, ab, ..., zz, aaa, ...

### Parent-Child Relationships

| Child | Parent | Rule |
|-------|--------|------|
| `1.2` | `1.` | Remove `.number`, leave the root period |
| `1.2a` | `1.2` | Remove letters |
| `1.2aa` | `1.2` | Remove ALL trailing letters |
| `1.2a3` | `1.2a` | Remove trailing numbers |

## Usage

### Creating Child Notes

The recommended workflow:

```
M-x autoslip-roam-insert-next-child
```

This command:
1. Extracts the current note's folgezettel address
2. Suggests the next available child address
3. Creates the note with automatic bidirectional links

### Adding Links to Existing Notes

For notes created without automatic linking:

```
M-x autoslip-roam-add-backlink-to-parent
```

### Validating Addresses

Check if an address is valid:

```
M-x autoslip-roam-report-validation-errors RET 1.2a RET
```

### Diagnosing Issues

Debug parent-finding problems:

```
M-x autoslip-roam-diagnose-address RET 1.2 RET
```

## Configuration

All options are in the `autoslip-roam` customization group:

```
M-x customize-group RET autoslip-roam RET
```

### Key Options

```elisp
;; Heading for parent links in child notes
(setq autoslip-roam-backlink-heading "Parent Note")

;; Heading for child links in parent notes
(setq autoslip-roam-forward-link-heading "Child Notes")

;; Enable automatic cross-reference links
(setq autoslip-roam-auto-crosslink t)

;; Sync database before queries (recommended)
(setq autoslip-roam-sync-db-before-queries t)

;; Where to store parent and child references.
;; 'headings (default) writes visible "Parent Note" and "Child Notes" sections.
;; 'properties writes to a top-level property drawer (quiet mode).
(setq autoslip-roam-link-storage 'headings)

;; Property keys used when link storage is 'properties.
(setq autoslip-roam-parent-property "FZ_PARENT")
(setq autoslip-roam-children-property "FZ_CHILDREN")

;; Rename a note's file on disk when its folgezettel address changes.
(setq autoslip-roam-rename-files-on-reparent t)

;; Heading used above chain-of-thought outlines inserted into notes.
(setq autoslip-roam-chain-heading "Chain of Thought")

;; Heading used above cross-linked chains-of-thought inserted into notes.
(setq autoslip-roam-chain-crosslink-heading "Cross-linked Chains of Thought")
```

### Link Storage Modes

The package supports two modes for recording parent and child references,
selectable with `autoslip-roam-link-storage`:

- `'headings` (default) writes visible `** Parent Note` and `** Child Notes`
  sections in the note body. This is the original behavior and is useful
  when you want to see the links inline while reading or exporting.
- `'properties` writes the references to a top-level property drawer
  (`:FZ_PARENT:` and `:FZ_CHILDREN:`) and leaves the body untouched. This
  reduces merge-conflict surface on shared vaults, keeps exports clean, and
  still records the relationships for programmatic traversal.

Both modes are compatible with `goto-parent`, `list-children`, `show-tree`,
and the reparent commands.

### Full Example Configuration

```elisp
(use-package autoslip-roam
  :after org-roam
  :config
  (setq autoslip-roam-parent-link-description "↑ Parent"
        autoslip-roam-backlink-heading "Parent Note"
        autoslip-roam-forward-link-heading "Child Notes"
        autoslip-roam-crosslink-heading "Cross References"
        autoslip-roam-auto-crosslink t
        autoslip-roam-sync-db-before-queries t)
  (autoslip-roam-mode 1)
  :bind
  (:map org-mode-map
        ("C-c n c" . autoslip-roam-insert-next-child)
        ("C-c n p" . autoslip-roam-add-backlink-to-parent)
        ("C-c n v" . autoslip-roam-report-validation-errors)))
```

## Commands

| Command | Description |
|---------|-------------|
| `autoslip-roam-mode` | Toggle the minor mode |
| `autoslip-roam-insert-next-child` | Create a new child note |
| `autoslip-roam-add-backlink-to-parent` | Add bidirectional links manually |
| `autoslip-roam-report-validation-errors` | Validate an address |
| `autoslip-roam-diagnose-address` | Debug address lookup |
| `autoslip-roam-check-duplicate-index` | Check for duplicates |
| `autoslip-roam-goto-parent` | Visit the parent of the current note |
| `autoslip-roam-list-children` | Pick a direct child of the current note and visit it |
| `autoslip-roam-show-tree` | Display the whole vault as a folgezettel-ordered tree |
| `autoslip-roam-show-chain-of-thought` | Open a buffer that lists every ancestor of the current note |
| `autoslip-roam-insert-chain-of-thought` | Insert the ancestor chain as an org outline at point |
| `autoslip-roam-show-crosslinked-chains` | Open a buffer grouping each cross-linked note's own ancestor chain |
| `autoslip-roam-reparent` | Move the current note to a new folgezettel address |
| `autoslip-roam-reparent-subtree` | Move the current note and all descendants to a new address |

### Navigation

`autoslip-roam-goto-parent` walks from the current note to the node
whose folgezettel address is one step shallower and opens it. This function errors
helpfully when the current note is a root.

`autoslip-roam-list-children` offers a completion list of every direct
child of the current note, ordered by folgezettel, and visits the choice.

`autoslip-roam-show-tree` opens a `*Autoslip Tree*` buffer with one
line per node, indented by depth, sorted in canonical folgezettel order.
Press `RET` on any line to visit that note, `n` and `p` to move between
lines, `g` to refresh, and `q` to close the buffer.

### Chain of Thought

`autoslip-roam-show-chain-of-thought` walks from the current note up
through every ancestor to the root of its folgezettel tree and displays the
chain in a `*Autoslip Chain of Thought*` buffer. Unlike the tree view,
the chain shows only the connecting notes (the ancestors), not the rest of
the subtree. Press `RET` on any line to visit the corresponding note, `i`
to insert the chain into the note that you opened the buffer from, `g` to
refresh, and `q` to close.

`autoslip-roam-insert-chain-of-thought` writes the chain directly at
point in the current note as an indented org bullet list, each item a
link to the corresponding org-roam node. The heading text above the list
comes from `autoslip-roam-chain-heading` (set to nil for no heading).

### Cross-linked Chains of Thought

`autoslip-roam-show-crosslinked-chains` is for the moment when you
have notes cross-linked to the current note, and you want to understand the
context each of those cross-linked notes sits in, not just its title. The
command reads every `[[id:...]]` under the Cross References heading of the
current note, looks up each target note, and renders one ancestor chain
per cross-link in the `*Autoslip Cross-linked Chains*` buffer. Press
`RET` to visit a node, `i` to insert all the chains into the current note,
`g` to refresh, and `q` to close.

### Renumbering (Reparenting)

`autoslip-roam-reparent` changes the folgezettel address of the
current note:

1. It validates the new address and refuses duplicates.
2. It rewrites the title keyword to start with the new address.
3. It removes the old parent's forward link and the old `Parent Note`
   section (or the equivalent property entries), then writes the new ones.
4. When `autoslip-roam-rename-files-on-reparent` is non-nil, it also
   renames the file on disk so the filename prefix matches the new address.

`autoslip-roam-reparent-subtree` does the same for the current note
and recursively applies the shift to every descendant, so moving `1.2a` to
`1.4a` also moves `1.2a3`, `1.2a3b`, and so on. The command pre-checks for
collisions with unrelated notes before making any changes.

### Suggested Key Bindings

```elisp
(with-eval-after-load 'org-roam
  (define-key org-mode-map (kbd "C-c n c") #'autoslip-roam-insert-next-child)
  (define-key org-mode-map (kbd "C-c n p") #'autoslip-roam-add-backlink-to-parent)
  (define-key org-mode-map (kbd "C-c n u") #'autoslip-roam-goto-parent)
  (define-key org-mode-map (kbd "C-c n d") #'autoslip-roam-list-children)
  (define-key org-mode-map (kbd "C-c n t") #'autoslip-roam-show-tree)
  (define-key org-mode-map (kbd "C-c n h") #'autoslip-roam-show-chain-of-thought)
  (define-key org-mode-map (kbd "C-c n H") #'autoslip-roam-insert-chain-of-thought)
  (define-key org-mode-map (kbd "C-c n x") #'autoslip-roam-show-crosslinked-chains)
  (define-key org-mode-map (kbd "C-c n r") #'autoslip-roam-reparent)
  (define-key org-mode-map (kbd "C-c n R") #'autoslip-roam-reparent-subtree))
```

## Testing

The package includes 100 comprehensive tests.

### Running Tests from Command Line

```bash
# Run all tests
make test

# Run unit tests only
make test-unit

# Run integration tests
make test-integration

# Run with verbose output
make test-verbose

# Run a specific test
make test-specific TEST=test-parse-address-single-number
```

### Running Tests in Emacs

```elisp
;; Load and run all tests
(load-file "test-autoslip-roam.el")
M-x ert RET t RET

;; Run specific category
M-x ert RET ^test-parse RET
```

### Test Categories

| Category | Tests | Description |
|----------|-------|-------------|
| Parsing | 7 | Address parsing |
| Extraction | 5 | Title extraction |
| Letter sequences | 5 | Alphabet incrementing |
| Validation | 13 | Address validation |
| Suggestions | 8 | Child suggestions |
| Parent lookup | 6 | Find-parent and index-exists helpers |
| Link insertion | 6 | File operations |
| Integration | 2 | Full workflows |
| Edge cases | 5 | Boundary conditions |
| Regression | 5 | Fixed bugs |
| Performance | 2 | Speed tests |
| Address helpers | 5 | Depth, tokens, canonical ordering |
| Children lookup | 2 | Direct-children discovery |
| Rename helpers | 4 | Address-driven file renaming |
| Link storage | 3 | Property-drawer storage mode |
| Reparent helpers | 3 | Title, backlink, and forward-link rewrites |
| Tree view | 2 | `show-tree` buffer contents |
| Navigation | 3 | `goto-parent` and `list-children` commands |
| Chain of thought | 9 | Ancestor walk, org-list rendering, `show` and `insert` |
| Cross-linked chains | 5 | Cross-link id extraction and `show-crosslinked-chains` |

## Info Documentation

The package includes a comprehensive Info manual accessible within Emacs.

### Building the Info File

```bash
make info
```

### Installing the Info File

**System-wide (requires sudo):**

```bash
sudo make install-info
```

**User-local (no sudo):**

```bash
make install-info-user
```

Then add to your `init.el`:

```elisp
(add-to-list 'Info-additional-directory-list "~/.emacs.d/info")
```

### Accessing the Manual

After installation:

```
C-h i d m Autoslip Roam RET
```

Or:

```
M-x info RET m Autoslip Roam RET
```

## Troubleshooting

### Parent Note Not Found

1. Verify the parent exists with the correct folgezettel in title
2. Run `M-x org-roam-db-sync` to update the database
3. Use `M-x autoslip-roam-diagnose-address` to debug

### Links Not Appearing

Ensure database sync is enabled:

```elisp
(setq autoslip-roam-sync-db-before-queries t)
```

### Invalid Address Errors

Common issues:
- Multiple periods (`1.2.3`) - only one allowed
- Uppercase letters (`1.2A`) - use lowercase
- Special characters - only digits, letters, one period

### Mode Not Working

Verify the mode is active:

```elisp
(autoslip-roam-mode 1)
```

Check the hook is registered:

```elisp
(member 'autoslip-roam--process-new-node
        org-roam-capture-new-node-hook)
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`make test`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

### Development Setup

```bash
git clone https://github.com/MooersLab/autoslip-roam.git
cd autoslip-roam
make check-deps  # Verify dependencies
make test        # Run test suite
make check       # Run all quality checks
```

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspiration from the annual Emacsconf and various Emacs Meetup groups, especially the Austin Emacs Meetup and the Berlin Emacs Meetup.

## Related projects

- [bidirectional-folgezettel for Obsidian](https://github.com/MooersLab/bidirectional-folgezettel)

## Status

The package is actively maintained and used in the author's daily workflow.
Core features (automatic bidirectional linking, validation, child-address
suggestion, cross-reference links, navigation, tree view, chain of thought,
cross-linked chains of thought, reparenting, and the quiet property-drawer
storage mode) are covered by 100 ERT tests that run under `make test`.
Feedback and patches are welcome via the issue tracker.

## Additional considerations for existing org-roam users

## What if you have an existing zettelkasten in org-roam without folgezettel indices?
If you already have a set of topic nodes, perhaps at one level below a master node, you can use them as the root nodes. You will need to number these. I maintain a file called 00. Index of Indices that contains the list of numbered root nodes.

If you have a large graph that was developed from the bottom up, you could ask AI agents to identify candidate root nodes. You could then edit and number these and then ask the agents to apply the numbering scheme described above while honoring the existing links.

## How to export to paper?
My approach is to export the note to PDF, then print it. 
I added a LaTeX preamble drawer to my template for notes to provide a compact format to save paper.

```org-mode
:PREAMBLE:
#+Options: toc:nil \n:nil num:nil
#+STARTUP: noindent overview
#+LaTeX_CLASS: article
#+LaTeX_CLASS_OPTIONS: [11pt,letterpaper]
#+LaTeX_HEADER:\usepackage[letterpaper, total={7in, 9in}]{geometry} % good with line numbers
#+LATEX_HEADER:\usepackage{parskip} % add a blank line between paragraphs upon export to PDF.
#+LATEX_HEADER:\usepackage[all=subtle,title=normal]{savetrees}
:END:
```

## Update history

| Version | Changes | Date |
|:--------|:--------|:-----|
| 3.0.0 | Renamed the package from `folgezettel-org-roam` to `autoslip-roam`. Every public symbol, file, buffer name, mode name, and customization group was renamed in step. Users upgrading from 2.x will need to update their `require` form, their customizations, and any key bindings to the new prefix. Root addresses now canonicalize to `N.` with a trailing period (e.g., `1.`) to match numbered-outline conventions like `1. Crystallography`. Legacy bare-integer titles (`1 Crystallography`) are still recognized and treated as equivalent. | 2026-04-23 |
| 2.5.0 | Added `show-chain-of-thought`, `insert-chain-of-thought`, and `show-crosslinked-chains` commands. Expanded the test suite to 100 tests. | 2026-04-23 |
| 2.4.0 | Added `goto-parent`, `list-children`, `show-tree`, `reparent`, and `reparent-subtree` commands. Added a quiet property-drawer link-storage mode. Expanded the test suite to 86 tests. | 2026-04-22 |
| 0.1 | Initial commit. Extensive edits of the README.md. | 2026-01-31 |

## Funding
- NIH: R01 CA242845, R01 AI088011
- NIH: P30 CA225520 (PI: R. Mannel); P30GM145423 (PI: A. West)

**Questions?** Open an issue on [GitHub](https://github.com/MooersLab/autoslip-roam/issues).
