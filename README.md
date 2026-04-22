# Folgezettel Org-Roam

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Emacs](https://img.shields.io/badge/Emacs-27.1+-blueviolet.svg)](https://www.gnu.org/software/emacs/)
[![org-roam](https://img.shields.io/badge/org--roam-2.0+-green.svg)](https://www.orgroam.com/)

Automatic folgezettel (related to the Luhmann-style but compatible with computer filenames) bidirectional link generation for [org-roam](https://www.orgroam.com/).
This package uses the folgezettel index to determine the parent-child relationship and uses that relationship to create the directional links automatically.
The index is placed before the title of the note and is compatible with the org-roam file naming system.

## What problems are addressed by this plugin?

### True automation of bidirectional linking
Electronic zettelkastens rely on reciprocal hyperlinks to relate parent and child notes. 
The manual insertion of these links is error-prone and time-consuming. 
This package provides true automation for creating these links by leveraging the parent-child relationship defined in the indexing system. 
You do not need to click a button to add the links; they are added automatically.

## Support for export to a paper-based zettelkasten
The folgezettel index determines the order in which a new note is to be placed in a series on notes in a paper-based zettelkasten.
The ability to print these indices with the notes provides a bridge between electronic and paper-based zettelkastens.
This bridge supports hybrid approaches, mirror approaches, and project-based approaches.
In the project-based approach, the notes on paper are used during the assembly of manuscripts where the notes are ordered and rearranged on a physical tabletop or corkboard.

Most electronic zettelkastens rely either on timestamps or a database ID to identify each unique note. 
This approach is hopeless if one wants to print out their zettels to store them in a paper-based zettelkasten. 
Fans of the paper-based approach may object that you should write these notes by hand to better integrate the information into your memory. 
This may be true, but more frequent perusal of the paper zettelkasten may be compensatory and possibly more effective in the long term. 
Often, there is just not enough time available to rewrite the notes by hand.

There is no rule against mixing handwritten and printed notes together. The inclusion of the folgezettel index in the title tells the user where to store the note. Paper-based zettelkastens rely on the folgezettel index (also called the Luhmann-style index or the Scott Scheper index) to specify the linear order of note storage. There is a one-to-one mapping between the zettelkasten graph and the order in which the notes are stored.

This approach supports a hybrid zettelkasten, with part electronic and part paper-based. Of course, it also supports a mirrored zettelkasten in both paper and electronic form.

You can print a note on US letter-size paper, fold it in half with the title on the outside, and store it in this zettelkasten. This folded paper corresponds to A5-sized paper. Luhmann used the smaller A6-sized paper.

If the note spans multiple pages, as may be the case with a structure note, keyword note, structure note, or hub note, you can fold the pages in half together. You can also save paper and space by printing on both sides, resulting in a booklet with two pages per side. For example, an eight-page note would span both sides of two sheets of US letter paper. The text will be rotated by 90°, so you will need to write the index across the top of the outside side of the folded paper. I favor this approach over index cards because it provides more space and because US Letter printer paper is cheaper and more readily available. This more practical approach reduces the friction of adding new notes to your paper-based zettelkasten.

Obsidian offers a fantastic, infinite canvas for displaying and organizing notes in all kinds of configurations. The ability to print out the notes opens up the opportunity to work with paper versions on a large tabletop or a corkboard. Sometimes changing the context from an electronic format to a physical format can stimulate the mind. This alternative physical approach to arranging notes is useful when using the notes in assembling a manuscript. You can use the canvas to combine all the notes you want to print. This could be useful for one-off tasks, such as assembling a manuscript, where you may discard the paper notes when you are done.



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

Folgezettel Org-Roam brings Niklas Luhmann's folgezettel (follow-up slip) numbering system to org-roam. 
When you create a note with a folgezettel address in its title (e.g., "1.2a My Topic"), the package automatically:

1. Identifies the parent note based on the address hierarchy
2. Inserts a backlink to the parent in the new note
3. Inserts a forward link to the child in the parent note

This creates a seamlessly navigable hierarchy of interconnected notes.

## Features

- **Automatic Bidirectional Linking** - Parent and child notes are linked automatically
- **Address Validation** - Prevents invalid folgezettel addresses
- **Duplicate Detection** - Warns if an address is already in use
- **Smart Suggestions** - Suggests the next available child address
- **Cross-Reference Links** - Automatic reciprocal links when inserting manual links
- **Database Sync** - Immediate visibility in org-roam graph and queries
- **Extended Alphabet** - Supports aa, ab, ..., zz, aaa, ... after z

## Installation

### Requirements

- Emacs 27.1 or later
- org-roam 2.0 or later

### From MELPA (Recommended)

Once available on MELPA:

```elisp
M-x package-install RET folgezettel-org-roam RET
```

### Manual Installation

1. Clone the repository:

```bash
git clone https://github.com/MooersLab/folgezettel-org-roam.git
cd folgezettel-org-roam
```

2. Add to your Emacs configuration:

```elisp
(add-to-list 'load-path "/path/to/folgezettel-org-roam")
(require 'folgezettel-org-roam)
(folgezettel-org-roam-mode 1)
```

### Using use-package

```elisp
(use-package folgezettel-org-roam
  :after org-roam
  :load-path "/path/to/folgezettel-org-roam"
  :config
  (folgezettel-org-roam-mode 1)
  :bind
  (:map org-mode-map
        ("C-c n c" . folgezettel-org-roam-insert-next-child)
        ("C-c n p" . folgezettel-org-roam-add-backlink-to-parent)))
```

## Quick Start

### 1. Enable the Mode

```elisp
(require 'folgezettel-org-roam)
(folgezettel-org-roam-mode 1)
```

### 2. Create a Root Note

```
M-x org-roam-node-find RET
Title: 1 Introduction to My Topic
```

### 3. Create a Child Note

With the root note open:

```
M-x folgezettel-org-roam-insert-next-child RET
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

**Parent note (1 Introduction to My Topic):**
```org
#+title: 1 Introduction to My Topic

Your content here...

** Child Notes
[[id:def456][1.1 First Subtopic]]
```

## Folgezettel Address Format

### Address Hierarchy

| Address | Description |
|---------|-------------|
| `1` | Root note |
| `1.2` | Second subtopic of note 1 |
| `1.2a` | First letter branch of 1.2 |
| `1.2aa` | 27th child of 1.2 (after z) |
| `1.2a3` | Third numeric child of 1.2a |
| `1.2a3b` | Second letter child of 1.2a3 |

### Rules

1. **Start with a number** - All addresses begin with a root number
2. **Single period only** - Only one `.` allowed (after the root)
3. **Alternation** - Numbers and letters must alternate after the period
4. **Lowercase only** - Use lowercase letters (a-z)
5. **Extended alphabet** - After z comes aa, ab, ..., zz, aaa, ...

### Parent-Child Relationships

| Child | Parent | Rule |
|-------|--------|------|
| `1.2` | `1` | Remove `.number` |
| `1.2a` | `1.2` | Remove letters |
| `1.2aa` | `1.2` | Remove ALL trailing letters |
| `1.2a3` | `1.2a` | Remove trailing numbers |

## Usage

### Creating Child Notes

The recommended workflow:

```
M-x folgezettel-org-roam-insert-next-child
```

This command:
1. Extracts the current note's folgezettel address
2. Suggests the next available child address
3. Creates the note with automatic bidirectional links

### Adding Links to Existing Notes

For notes created without automatic linking:

```
M-x folgezettel-org-roam-add-backlink-to-parent
```

### Validating Addresses

Check if an address is valid:

```
M-x folgezettel-org-roam-report-validation-errors RET 1.2a RET
```

### Diagnosing Issues

Debug parent-finding problems:

```
M-x folgezettel-org-roam-diagnose-address RET 1.2 RET
```

## Configuration

All options are in the `folgezettel-org-roam` customization group:

```
M-x customize-group RET folgezettel-org-roam RET
```

### Key Options

```elisp
;; Heading for parent links in child notes
(setq folgezettel-org-roam-backlink-heading "Parent Note")

;; Heading for child links in parent notes
(setq folgezettel-org-roam-forward-link-heading "Child Notes")

;; Enable automatic cross-reference links
(setq folgezettel-org-roam-auto-crosslink t)

;; Sync database before queries (recommended)
(setq folgezettel-org-roam-sync-db-before-queries t)
```

### Full Example Configuration

```elisp
(use-package folgezettel-org-roam
  :after org-roam
  :config
  (setq folgezettel-org-roam-parent-link-description "↑ Parent"
        folgezettel-org-roam-backlink-heading "Parent Note"
        folgezettel-org-roam-forward-link-heading "Child Notes"
        folgezettel-org-roam-crosslink-heading "Cross References"
        folgezettel-org-roam-auto-crosslink t
        folgezettel-org-roam-sync-db-before-queries t)
  (folgezettel-org-roam-mode 1)
  :bind
  (:map org-mode-map
        ("C-c n c" . folgezettel-org-roam-insert-next-child)
        ("C-c n p" . folgezettel-org-roam-add-backlink-to-parent)
        ("C-c n v" . folgezettel-org-roam-report-validation-errors)))
```

## Commands

| Command | Description |
|---------|-------------|
| `folgezettel-org-roam-mode` | Toggle the minor mode |
| `folgezettel-org-roam-insert-next-child` | Create a new child note |
| `folgezettel-org-roam-add-backlink-to-parent` | Add bidirectional links manually |
| `folgezettel-org-roam-report-validation-errors` | Validate an address |
| `folgezettel-org-roam-diagnose-address` | Debug address lookup |
| `folgezettel-org-roam-check-duplicate-index` | Check for duplicates |

## Testing

The package includes 64 comprehensive tests.

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
(load-file "test-folgezettel-org-roam.el")
M-x ert RET t RET

;; Run specific category
M-x ert RET ^test-parse RET
```

### Test Categories

| Category | Tests | Description |
|----------|-------|-------------|
| Parsing | 9 | Address parsing |
| Extraction | 5 | Title extraction |
| Letter sequences | 5 | Alphabet incrementing |
| Validation | 16 | Address validation |
| Suggestions | 8 | Child suggestions |
| Link insertion | 6 | File operations |
| Integration | 2 | Full workflows |
| Edge cases | 5 | Boundary conditions |
| Regression | 5 | Fixed bugs |
| Performance | 2 | Speed tests |

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
C-h i d m Folgezettel Org-Roam RET
```

Or:

```
M-x info RET m Folgezettel Org-Roam RET
```

## Troubleshooting

### Parent Note Not Found

1. Verify the parent exists with correct folgezettel in title
2. Run `M-x org-roam-db-sync` to update the database
3. Use `M-x folgezettel-org-roam-diagnose-address` to debug

### Links Not Appearing

Ensure database sync is enabled:

```elisp
(setq folgezettel-org-roam-sync-db-before-queries t)
```

### Invalid Address Errors

Common issues:
- Multiple periods (`1.2.3`) - only one allowed
- Uppercase letters (`1.2A`) - use lowercase
- Special characters - only digits, letters, one period

### Mode Not Working

Verify the mode is active:

```elisp
(folgezettel-org-roam-mode 1)
```

Check the hook is registered:

```elisp
(member 'folgezettel-org-roam--process-new-node
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
git clone https://github.com/MooersLab/folgezettel-org-roam.git
cd folgezettel-org-roam
make check-deps  # Verify dependencies
make test        # Run test suite
make check       # Run all quality checks
```

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Niklas Luhmann for the Zettelkasten method.
- The [org-roam](https://www.orgroam.com/) team for their excellent package.
- The Emacs community for continuous inspiration.


## Status

It works!

## Update history

|Version      | Changes                                                                                                                                   | Date              |
|:-----------|:------------------------------------------------------------------------------------------------------------------------------------------|:--------------------|
| Version 0.1 |  Initi commitExtensive edits of the README.md.                                                                                           | 2026 January 31    |


## Funding
- NIH: R01 CA242845, R01 AI088011
- NIH: P30 CA225520 (PI: R. Mannel); P30GM145423 (PI: A. West)


**Questions?** Open an issue on [GitHub](https://github.com/MooersLab/folgezettel-org-roam/issues).
