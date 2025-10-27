# CLAUDE.md - Automated Upstream Porting Guide for Pikchr

This document provides complete instructions for porting upstream changes from the pikchr diagram language to this Go port. It's designed to enable future Claude Code sessions to work autonomously on converting upstream commits.

---

## Table of Contents

1. [Overview & Porting Philosophy](#overview--porting-philosophy)
2. [Prerequisites & Setup](#prerequisites--setup)
3. [Identifying Work to Do](#identifying-work-to-do)
4. [Step-by-Step Porting Process](#step-by-step-porting-process)
5. [Testing Changes](#testing-changes)
6. [Committing Changes](#committing-changes)
7. [Troubleshooting & When to Collaborate](#troubleshooting--when-to-collaborate)
8. [For Future Claude Sessions](#for-future-claude-sessions)

---

## Overview & Porting Philosophy

### Project Purpose

This repository (`gopikchr`) is a Go port of the pikchr diagram language parser. It tracks the upstream pikchr repository and ports changes as they occur.

### Porting Philosophy

**Principle: Similarity to C Code > Idiomatic Go**

Similar to the golemon port, this port prioritizes staying close to the original C code over making it fully idiomatic Go. The code is intentionally C-like Go code. This approach:

- Makes tracking upstream changes easier
- Allows for more mechanical conversions
- Reduces the risk of introducing bugs through over-abstraction
- Maintains structural similarity for future ports

### What Makes Pikchr Different from Golemon

**Key differences:**
1. **Source file**: We port `pikchr.y` (a Lemon grammar file), not `.c` files
2. **Both versions use parser generators**: C uses `lemonc`, Go uses `golemon`
3. **Grammar rules never change**: Only the embedded C/Go code in actions is converted
4. **Testing is critical**: Must verify C and Go produce **identical** output

### The Five Core Conversion Patterns

All pikchr conversions follow these fundamental patterns (see PIKCHR_PORTING_GUIDE.md for details):

1. **Function Signatures**: `static void func(Pik *p, ...)` → `func (p *Pik) func(...)`
2. **Pointer Access**: `pObj->field` → `pObj.field`
3. **Memory Management**: `malloc/realloc/free` → `bytes.Buffer` + GC
4. **String Handling**: `char *z, int n` → `[]byte` or `string`
5. **Macros**: `#define X` → `const X`

### Detailed Porting Reference

For detailed conversion patterns, see these comprehensive guides:

- **[PIKCHR_PORTING_GUIDE.md](PIKCHR_PORTING_GUIDE.md)** - Comprehensive 13-section guide with 100+ examples
- **[PIKCHR_PORTING_SUMMARY.md](PIKCHR_PORTING_SUMMARY.md)** - Executive summary with key insights
- **[README_PORTING_DOCS.md](README_PORTING_DOCS.md)** - Navigation guide for all documentation

---

## Prerequisites & Setup

### Required Environment

1. **This Repository** (`gopikchr`):
   ```bash
   ~/gh/p_gopikchr/gopikchr
   ```

2. **Upstream Pikchr Repository** (sibling directory):
   ```bash
   ~/gh/p_gopikchr/pikchr
   ```

   The pikchr repository must be cloned as a sibling directory:
   ```bash
   cd ~/gh/p_gopikchr/
   git clone https://github.com/drhsqlite/pikchr.git
   ```

3. **Golemon Parser Generator** (sibling directory):
   ```bash
   ~/gh/p_gopikchr/golemon/bin/golemon
   ~/gh/p_gopikchr/golemon/bin/lemonc
   ```

   The golemon repository with built binaries is required.

   **IMPORTANT**: The lemonc binary is built from `~/gh/p_gopikchr/golemon/intermediate/lemon.c`.
   This lemon.c file is periodically updated from `~/gh/p_gopikchr/pikchr/lemon.c` to get
   the latest enhancements. If you encounter lemon-related errors (e.g., `%include <file>`
   not supported), you may need to:

   ```bash
   cp ~/gh/p_gopikchr/pikchr/lemon.c ~/gh/p_gopikchr/golemon/intermediate/lemon.c
   cd ~/gh/p_gopikchr/golemon
   ./build.sh
   ```

4. **Build Tools**:
   - Go 1.x or later
   - GCC (for building C version)
   - Bash (for test scripts)

### Directory Structure

```
~/gh/p_gopikchr/
├── gopikchr/                   # This repository
│   ├── c/                      # C version (for testing)
│   │   ├── pikchr.y            # Copy of upstream pikchr.y
│   │   ├── pikchr.c            # Generated from pikchr.y using lemonc
│   │   ├── pikchr              # Compiled C binary
│   │   ├── pikchr.out          # Test output from C version
│   │   └── diff.sh             # Compares c/pikchr.y with upstream
│   ├── internal/               # Go version
│   │   ├── pikchr.y            # Go-ported grammar file
│   │   ├── pikchr.go           # Generated from pikchr.y using golemon
│   │   ├── pikchr.out          # Test output from Go version
│   │   └── dotest.sh           # Generates pikchr.go from pikchr.y
│   ├── examples/               # Test cases from upstream
│   ├── tests/                  # Additional test cases
│   ├── output/                 # Test output comparison
│   ├── dotest.sh               # Main test script
│   ├── notes.md                # Change log notes
│   └── CLAUDE.md               # This file
├── pikchr/                     # Upstream pikchr repository
│   └── pikchr.y                # Upstream source
└── golemon/                    # Parser generator
    └── bin/
        ├── golemon             # Go parser generator
        └── lemonc              # C parser generator
```

### File Flow

The conversion process uses three stages:

1. **Upstream Source** (`~/gh/p_gopikchr/pikchr/pikchr.y`)
2. **Intermediate** (`c/pikchr.y` - copied from upstream)
3. **Go Port** (`internal/pikchr.y` - manually ported)
4. **Generated** (`internal/pikchr.go` - auto-generated by golemon)

Changes flow: `upstream pikchr.y` → `c/pikchr.y` → `internal/pikchr.y` → `internal/pikchr.go`

---

## Identifying Work to Do

### How the Upstream Tracking Works

A GitHub Action (`.github/workflows/check-upstream.yml`) runs daily to check for new commits in the upstream pikchr repository.

When new commits are found, the Action:
1. Skips commits that only change markdown files
2. Creates one issue per commit
3. Labels each issue with `upstream-changes`
4. Sets the issue author to `github-actions`

### Finding Issues to Work On

To find issues that need porting:

```bash
gh issue list --label upstream-changes --state open
```

**Example output:**
```
105  OPEN  Port changes from upstream: Add tcl v8/9 compatibility...  upstream-changes
104  OPEN  Port changes from upstream: A more precise computation...   upstream-changes
103  OPEN  Port changes from upstream: Improved boundry box...        upstream-changes
```

### IMPORTANT: Verify Issues Before Processing

**Not all open issues require porting!** Before spending time on an issue, verify whether it needs action:

#### Step 1: Check if upstream repo is up to date

```bash
cd ~/gh/p_gopikchr/pikchr
git checkout master  # or main/trunk depending on the repo
git pull
```

The pikchr repo may have new commits that weren't present when you started.

#### Step 2: Find the last ported commit

```bash
cd ~/gh/p_gopikchr/gopikchr
git log --oneline --grep="track upstream commit" | head -1
```

Example output: `c958377 track upstream commit 0624fc4904: use font-size of "initial"`

This tells you that `0624fc4904` (July 24, 2024) was the last commit ported.

#### Step 3: Check if issue commit is already incorporated

For each open issue, determine if the commit is:
- **BEFORE** the last ported commit → Already incorporated, close the issue
- **AFTER** the last ported commit → Needs porting
- **C-specific or docs-only** → Not applicable, close the issue

**CRITICAL: Use git log --reverse to verify chronological order!**

Issue numbers do NOT reflect chronological order. A rename from A→B might have:
- Issue #100: "Add feature A"
- Issue #96: "Rename A to B" (created later but commits happened in this order)

To check chronological order:

```bash
cd ~/gh/p_gopikchr/pikchr
# Find where commits appear chronologically
git log --oneline --reverse --all | grep -n "<issue-commit-sha>\|<last-ported-commit-sha>"
```

Lower line number = earlier commit. The commit that appears FIRST is the earlier one.

**Example verification:**

```bash
# Check what the issue commit changed
cd ~/gh/p_gopikchr/pikchr
git show --stat <commit-sha>

# Check chronological order vs last ported commit
git log --oneline --reverse --all | grep -n "<issue-sha>\|<last-ported-sha>"

# If issue commit line number is LESS than last ported commit:
#   → Check if feature exists in internal/pikchr.y
#   → If yes, close as already incorporated
#   → If no, it may have been renamed/refactored - investigate

# If it only changed docs or pikchr.c (not pikchr.y), check if relevant
# If it changed pikchr.y, check what features were added/changed
```

#### Common reasons to close without porting:

1. **Already incorporated**: Commit is before the last ported commit
   - Verify by checking if the feature exists in `internal/pikchr.y`
   - Example: Monospace support - check if `TP_MONO` exists in both files

2. **Documentation only**: Commit only changes `doc/*` or markdown files
   - Example: Adding contributors agreement (`doc/copyright-release.html`)

3. **C-specific portability**: Changes only affect C implementation
   - Example: Cygwin ctype.h fixes - Go doesn't use ctype.h
   - Example: Build system changes, compiler-specific workarounds

4. **Generated file only**: Changes only affect `pikchr.c` (generated from `pikchr.y`)
   - Check if the change should have been in `pikchr.y` first

#### Example Verification Process:

```bash
# For issue about "monospace" support:
cd ~/gh/p_gopikchr/pikchr
git checkout bbf832db99  # The issue's commit
grep -c "TP_MONO" pikchr.y   # Returns 5

cd ~/gh/p_gopikchr/gopikchr
grep -c "TP_MONO" internal/pikchr.y   # Returns 5

# Same count = feature is incorporated → close issue
```

**CRITICAL**: Always run verification from the `~/gh/p_gopikchr/gopikchr` directory when using `gh issue` commands. The working directory can get lost when working with multiple repos.

### Issue Format

Each issue contains:

```
Title: Port changes from upstream: <first line of commit message>

Body:
New commit found in upstream pikchr repository that needs to be ported.

Commit: <full-commit-sha>
Author: <author-name>
Date: <commit-date>

Message:
<full-commit-message>

Original commit: https://github.com/drhsqlite/pikchr/commit/<full-commit-sha>
```

### Which Issue to Work On

**Rule: Process issues in order by issue number (oldest first)**

This ensures that changes are applied in chronological order, which is important for maintaining consistency with upstream.

```bash
# Get the oldest open issue
gh issue list --label upstream-changes --state open | tail -1
```

### Extracting Information from an Issue

From the issue body, extract:
- **Full commit SHA**: The 40-character hash
- **Short commit SHA**: First 10 characters (for commit messages)
- **Issue number**: For the "Closes #N" message
- **Brief description**: First line of commit message (for commit title)

**Example:**
```bash
# View issue details
gh issue view 83

# Extract commit SHA (look for "Commit: <sha>" line in the output)
```

---

## Step-by-Step Porting Process

### Process Overview

For each upstream commit, you will:
1. Check out the upstream commit in the pikchr repo
2. Copy pikchr.y to the c/ directory
3. Review the changes
4. Analyze the intent and determine what action is needed
5. Port changes to internal/pikchr.y (if appropriate)
6. Regenerate internal/pikchr.go using golemon
7. Test that C and Go produce identical output
8. Update notes.md
9. Commit and close the issue

### Detailed Steps

#### Step 1: Check out the upstream commit

```bash
cd ~/gh/p_gopikchr/pikchr
git checkout <commit-sha>
```

**Purpose**: This ensures you're looking at the exact version of pikchr.y from the upstream commit.

**Example:**
```bash
cd ~/gh/p_gopikchr/pikchr
git checkout 0624fc4904a9c8d628d8e4ede7386b590d123d68
```

#### Step 2: Return to gopikchr directory

```bash
cd ~/gh/p_gopikchr/gopikchr
```

#### Step 3: Copy pikchr.y to c/ directory

```bash
cp ~/gh/p_gopikchr/pikchr/pikchr.y c/
```

**Purpose**: This creates a snapshot of the upstream file for comparison.

**Alternative**: You can also use the diff script:
```bash
cd c
./diff.sh
```
This shows you the changes without copying. But you should copy afterward to track the change.

#### Step 4: Review the changes

```bash
git diff c/pikchr.y
```

**What you're looking for:**
- Changes in `c/pikchr.y` - these need to be ported to `internal/pikchr.y`

**Understanding the diff:**
- Red lines (deletions) = old version
- Green lines (additions) = new version from upstream
- The diff shows what changed in the upstream commit

**Example diff:**
```diff
diff --git a/c/pikchr.y b/c/pikchr.y
-    " style='font-size:100%'",-1);
+    " style='font-size:initial;'",-1);
```

#### Step 5: Analyze the Intent and Determine Action

**CRITICAL**: Before making any changes to the Go code, stop and think about what the change actually means and whether it applies to Go.

**Questions to ask yourself:**

1. **What problem does this change solve?**
   - Bug fix (logic error, edge case, etc.)?
   - New feature or functionality?
   - Code refactoring or cleanup?
   - Documentation or comment change?
   - Build system or tooling change?

2. **Does this problem exist in Go?**
   - **Grammar rules**: Changes to grammar productions always apply
   - **Embedded C code**: Must be converted using porting patterns
   - **C-specific issues**: Memory safety, buffer overflows → usually don't apply
   - **Algorithm/logic issues**: Usually still apply
   - **New features**: Usually still apply

3. **What action should I take?**

**Decision Matrix:**

| Change Type | Does it Apply to Go? | Action |
|------------|---------------------|---------|
| Grammar rule change | Yes | Port directly (grammar rules are identical) |
| Bug fix in action code | Yes | Port using porting patterns |
| New feature | Yes | Port using porting patterns |
| C-specific security fix | Maybe | Analyze if Go has same issue |
| Documentation/comments | Yes | Port comments (maintain parallel structure) |
| pikchr.c only (not pikchr.y) | Maybe | Analyze case-by-case - may not apply |
| **Unclear or complex change** | **Unknown** | **STOP and ask the user** |

**Examples:**

**Example 1: Simple string change**
```diff
-    " style='font-size:100%'",-1);
+    " style='font-size:initial;'",-1);
```

**Analysis:**
- **Problem**: CSS value change (better default)
- **Applies to Go?**: Yes - same output string
- **Action**: Port directly, converting C syntax to Go:
  ```go
  -    " style='font-size:100%'")
  +    " style='font-size:initial;'")
  ```

**Example 2: Bug fix in logic**
```diff
-  if (x < 0) return;
+  if (x <= 0) return;
```

**Analysis:**
- **Problem**: Off-by-one error in conditional
- **Applies to Go?**: Yes - same logic bug
- **Action**: Port the fix to Go

**Example 3: New function in C**
```diff
+ static void newHelper(Pik *p, int x) {
+   // implementation
+ }
```

**Analysis:**
- **Problem**: Adding new helper function
- **Applies to Go?**: Yes - same functionality needed
- **Action**: Port using pattern: `func (p *Pik) newHelper(x int) { }`

**Example 4: C-only file changes**
```
Commit only touches pikchr.c, not pikchr.y
```

**Analysis:**
- **Problem**: Change to generated file or C-specific code
- **Applies to Go?**: Unknown - need to investigate
- **Action**:
  - Check if this is a generated-code-only change (skip)
  - Check if this needs to be reflected in pikchr.y (port)
  - **When in doubt, ask the user**

**Example 5: Version changes**
```diff
+ const char *pikchr_version(void){
+   return RELEASE_VERSION " " MANIFEST_DATE;
+ }
```

**Analysis:**
- **Problem**: Adding version information
- **Applies to Go?**: Yes - public API should be consistent
- **Action**:
  - **CRITICAL**: Keep version info synced with upstream!
  - Check `VERSION` file in upstream repo for version number
  - Use upstream commit date for manifest date (format: "YYYY-MM-DD HH:MM:SS")
  - Update `ReleaseVersion` and `ManifestDate` constants in `internal/pikchr.y`
  - Create/update `c/VERSION.h` with matching values for C builds
  - Port the function using Go patterns

**Version Sync Checklist:**
1. Get version from upstream: `git show <commit>:VERSION`
2. Get commit date: `git show --format="%ci" <commit> | head -1`
3. Update `internal/pikchr.y` constants
4. Update `c/VERSION.h` (format: `#define RELEASE_VERSION "1.0"`)
5. Regenerate and test

---

**⚠️ IMPORTANT: When in Doubt, Discuss with the User**

If you're uncertain about how to handle a change, **STOP and collaborate with the user**. It's better to ask than to make incorrect assumptions. Explain:
- What the upstream change does
- Why you're uncertain about how to handle it
- What options you see for how to proceed

The user can provide context, help analyze whether the change applies to Go, and guide the approach. See the "Troubleshooting & When to Collaborate" section for detailed guidance on when and how to ask for help.

#### Step 6: Port changes from c/pikchr.y to internal/pikchr.y

**Process:**
1. Look at the diff in `c/pikchr.y`
2. Find the equivalent code in `internal/pikchr.y`
3. Apply the changes using the porting patterns from PIKCHR_PORTING_GUIDE.md

**Key considerations:**
- Use the 5 core conversion patterns (see Overview section)
- Maintain the structural similarity to the C code
- The grammar rules themselves never change
- Only the embedded C code in actions needs conversion

**Common conversions:**

| C Syntax | Go Syntax | Notes |
|----------|-----------|-------|
| `pik_append(p, "text", -1);` | `p.pik_append("text")` | Method call, no length needed |
| `p->field` | `p.field` | Pointer dereference → dot notation |
| `pObj->x = 5;` | `pObj.x = 5` | Same |
| `char *z;` | `var z string` | String declaration |
| `if( x ){` | `if x != 0 {` or `if x {` | Conditional (depends on type) |
| `malloc/realloc` | `bytes.Buffer` or slice | Memory management |

**Example:**

C code:
```c
static void func(Pik *p, PObj *pObj){
  p->zOut = realloc(p->zOut, newSize);
  pObj->x = p->field + 10;
  pik_append(p, "text", -1);
}
```

Go code:
```go
func (p *Pik) func(pObj *PObj) {
  // realloc replaced by bytes.Buffer - no allocation needed
  pObj.x = p.field + 10
  p.pik_append("text")
}
```

#### Step 6.5: Update version information (if needed)

If the upstream commit changes version information or dates, use the `update_version.py` script:

```bash
./update_version.py <commit-sha>
```

**What this does:**
- Extracts the commit date from the upstream pikchr repository
- Updates `c/VERSION.h` with the correct date and version
- Updates version constants in `internal/pikchr.y`

**Example:**
```bash
./update_version.py 9c5ced3599
```

This ensures that version strings and manifest dates stay synchronized with the upstream commit.

**When to use it:**
- When porting commits that change version numbers
- When porting commits that reference dates (like `pikchr_date` or `pikchr_version()`)
- As a final check before committing to ensure dates are accurate

**IMPORTANT**: Always run this script BEFORE regenerating pikchr.go, so the generated file includes the updated constants.

#### Step 7: Regenerate internal/pikchr.go using golemon

After porting changes to `internal/pikchr.y`, regenerate the Go parser:

```bash
cd internal
../../golemon/bin/golemon pikchr.y
go fmt ./pikchr.go
```

**Or use the convenience script:**
```bash
cd internal
./dotest.sh
```

**Purpose**: The `.y` grammar file is the source; `pikchr.go` is generated from it.

**What this does:**
1. Runs golemon parser generator on `pikchr.y`
2. Produces `pikchr.go` with the parser code
3. Formats the Go code

**If golemon fails:**
- Check for syntax errors in `internal/pikchr.y`
- Compare with `c/pikchr.y` to see if you missed a conversion
- See "Troubleshooting" section below

#### Step 8: Verify and stage all changes

Before testing, review what you've changed:

```bash
git diff
```

**Expected changes:**
- `c/pikchr.y` (copied from upstream)
- `internal/pikchr.y` (ported from c/pikchr.y)
- `internal/pikchr.go` (regenerated from internal/pikchr.y)

---

## Testing Changes

**CRITICAL**: Pikchr requires that the C and Go implementations produce **identical output** on all test cases.

### Main Test Script

```bash
./dotest.sh
```

**What this does:**
1. Generates `c/pikchr.c` from `c/pikchr.y` using lemonc
2. Generates `internal/pikchr.go` from `internal/pikchr.y` using golemon
3. Compiles C binary (`c/pikchr`)
4. Compiles Go binary (`gopikchr`)
5. Runs both on all files in `examples/` and `tests/`
6. Diffs the output - **must be identical**

**Expected result:**
```
...
Testing files in dir: examples
 file1.pikchr
 - Diffing output for file1.pikchr
 file2.pikchr
 - Diffing output for file2.pikchr
...
DONE: no failures
```

**If tests fail:**

Look at the diff output to understand what's different:
```bash
# Manual test of a single file
./c/pikchr examples/file1.pikchr > output/file1-c.html
./gopikchr examples/file1.pikchr > output/file1-go.html
diff output/file1-c.html output/file1-go.html
```

Common causes:
- Incorrect porting (logic error in conversion)
- Missed a change in `internal/pikchr.y`
- Golemon generated different code (rare)

See "Troubleshooting" section for more help.

### Quick Build Test (without full testing)

If you just want to verify the code compiles:

```bash
# Build C
gcc -DPIKCHR_SHELL=1 -o c/pikchr c/pikchr.c

# Build Go
go build ./cmd/gopikchr
```

### Understanding Test Failures

**The golden rule**: C and Go output must be **byte-for-byte identical**.

If they differ:
1. **Review the ported code** - did you apply the porting patterns correctly?
2. **Check for subtle differences** - spacing, formatting, floating-point precision
3. **Verify the upstream change** - is the C version working correctly?
4. **Ask for help** - if you're stuck, stop and collaborate with the user

---

## Committing Changes

### Commit Message Format

**CRITICAL**: Use this exact format to auto-close the issue:

```
track upstream commit <short-sha>: <brief description>

https://github.com/drhsqlite/pikchr/commit/<full-sha>

Closes #<issue-number>
```

**Parameters:**
- `<short-sha>`: First 10 characters of the commit SHA
- `<brief-description>`: First line of upstream commit message
- `<full-sha>`: Full 40-character commit SHA
- `<issue-number>`: The GitHub issue number

**Example:**
```
track upstream commit 0624fc4904: use font-size of "initial"

https://github.com/drhsqlite/pikchr/commit/0624fc4904a9c8d628d8e4ede7386b590d123d68

Closes #86
```

### Update notes.md

Before committing, add a note to `notes.md` documenting the change:

```markdown
### commit <full-sha>

    <commit message from upstream>

    FossilOrigin-Name: <fossil-origin-if-present>

 <files changed>

* <brief note about what was done>
```

**Example:**
```markdown
### commit 0624fc4904a9c8d628d8e4ede7386b590d123d68

    In the previous check-in, a better value for font-size is "initial".

    FossilOrigin-Name: 1562bd171ab868db152cffc7c0c2aca9dc416ef5acd66e8de6d9d6a0b9ebeff6

 pikchr.c | 2 +-
 pikchr.y | 2 +-

* Copy the fix over
```

### Files to Include

Typically, include these files:
```bash
git add c/pikchr.y
git add internal/pikchr.y
git add internal/pikchr.go
git add notes.md
```

**Note**: `c/pikchr.c` and `c/pikchr.out`, `internal/pikchr.out` are often regenerated but not always committed (check git status).

### Creating the Commit

**Using a heredoc for proper formatting:**

```bash
git commit -m "$(cat <<'EOF'
track upstream commit 0624fc4904: use font-size of "initial"

https://github.com/drhsqlite/pikchr/commit/0624fc4904a9c8d628d8e4ede7386b590d123d68

Closes #86
EOF
)"
```

**Why use a heredoc?**
- Ensures proper multi-line formatting
- Preserves the blank line between title and body
- The blank line is required for GitHub to parse "Closes #N"

### Pushing the Commit

```bash
git push
```

**What happens next:**
- GitHub automatically closes the issue (because of "Closes #86")
- The commit appears in the repository history
- The next Claude session can pick up the next issue

### Verification

After pushing, verify:
```bash
gh issue view <issue-number>
```

The issue should show as "CLOSED" with the commit linked.

---

## Troubleshooting & When to Collaborate

### When Automatic Conversion is Unclear

Not all C-to-Go conversions are mechanical. When you encounter situations that require judgment or deeper understanding, **collaborate with the user**.

### Red Flags - Stop and Ask

**Scenario 1: Semantic Changes or New Features**

If the upstream commit adds significant new functionality or changes behavior substantially, pause and discuss.

**Example:**
```
Issue: "Add support for new diagram element type 'cloud'"
```

This suggests a major new feature. Questions to ask:
- Should we port the entire feature now?
- Are there dependencies we need to understand first?
- How should we test this?

**Action:** Ask the user:
```
"This upstream change adds a new 'cloud' diagram element with ~200 lines of new code.

Questions:
1. Should I port this entire feature in one commit?
2. Are there any Go-specific considerations for this feature?
3. Should we add new test cases beyond what's in examples/?"
```

**Scenario 2: Changes to pikchr.c only (not pikchr.y)**

If the upstream commit only touches `pikchr.c` (the generated file), it might be:
- A generated-code-only change (can skip)
- A change that should have been in pikchr.y (might need manual porting)
- A fix that needs to be reflected in the generator

**Action:** Explain what you found and ask:
```
"The upstream commit only changes pikchr.c, not pikchr.y.

The change appears to be: [description]

Options:
1. Skip it (generated-code-only change)
2. Port it to internal/pikchr.y manually
3. Check if golemon needs updating

Which approach should I take?"
```

**Scenario 3: Test Failures After Porting**

If `dotest.sh` shows differences between C and Go output:

**Action:** Share the diff and your analysis:
```
"After porting the changes, the C and Go output differ:

[show relevant diff]

I ported the C code:
  [show C code]
as:
  [show Go code]

This follows pattern X from the porting guide, but produces different output.

Possible issues:
1. [hypothesis 1]
2. [hypothesis 2]

Should I try approach [A] or [B]?"
```

**Scenario 4: Golemon Generation Errors**

If `golemon pikchr.y` fails with errors:

**Action:** Share the error and your analysis:
```
"After porting changes to internal/pikchr.y, golemon fails with:

[error message]

The change I made was:
  [show change]

I believe the issue is:
  [hypothesis]

Should I try [solution]?"
```

### Green Flags - Proceed Autonomously

You can proceed without asking when:

1. **Simple value changes**: String constants, numeric values, CSS properties
2. **Comment changes**: Documentation updates, comment fixes
3. **Mechanical conversions**: Following clear patterns from the porting guides
4. **Tests pass**: `dotest.sh` completes with "DONE: no failures"

### Collaboration Guidelines

**Be proactive but not presumptuous:**
- ✅ Do: Explain what you found and propose options
- ✅ Do: Show your reasoning and analysis
- ✅ Do: Offer 2-3 concrete approaches
- ❌ Don't: Make major architectural decisions without discussion
- ❌ Don't: Skip difficult conversions hoping they'll work
- ❌ Don't: Commit broken code to "fix it later"

**Document your decisions:**

When you make a judgment call (after user confirmation), add a comment:

```go
// Port note: Upstream changed X to Y in commit 0624fc4904.
// Go's Z provides this natively, so no changes needed.
```

### Common Issues and Solutions

| Issue | Likely Cause | Solution |
|-------|-------------|----------|
| Golemon fails | Syntax error in internal/pikchr.y | Check for missing semicolons, braces, proper Go syntax |
| Test output differs | Incorrect porting logic | Compare C and Go action code line-by-line |
| Build error in Go | Type mismatch or undefined function | Review porting patterns for correct type conversions |
| Diff shows no changes | Upstream change doesn't apply | Discuss with user; may be C-specific or generated-code-only |
| Can't find equivalent code | Code was refactored in Go version | Search for similar logic; discuss with user if unclear |

---

## For Future Claude Sessions

### Critical Reminders for Automated Processing

#### Working Directory Management

**CRITICAL**: When working with multiple sibling directories, the shell working directory does NOT automatically revert to the main repo. Always explicitly `cd` to the correct repo before running commands:

```bash
# ❌ WRONG - assumes you're in the right directory
gh issue list --label upstream-changes --state open

# ✅ CORRECT - explicit directory change
cd ~/gh/p_gopikchr/gopikchr && gh issue list --label upstream-changes --state open
```

**Best practice**: Start every command that needs to be in a specific repo with `cd <repo-path> &&`.

#### Verification Before Porting

**ALWAYS verify an issue needs porting before starting work:**

1. Update the upstream pikchr repo: `cd ~/gh/p_gopikchr/pikchr && git pull`
2. Find the last ported commit in gopikchr
3. Check if the issue commit is before/after the last ported commit
4. For older commits, verify if features are already incorporated
5. For all commits, check if changes apply to Go

**Time saved**: Verifying takes 1-2 minutes; porting takes 15-60 minutes. Always verify first!

### Automated Workflow

When asked to "port upstream changes" or "process pending issues", follow this workflow:

#### 0. **FIRST: Verify the issue** (see "Verify Issues Before Processing" section)

This step is critical and will save significant time by avoiding unnecessary work.

#### 1. **List open issues**
```bash
cd ~/gh/p_gopikchr/gopikchr && gh issue list --label upstream-changes --state open
```

#### 2. **Select the oldest issue**
```bash
# Get the issue with the smallest number
cd ~/gh/p_gopikchr/gopikchr && gh issue list --label upstream-changes --state open | tail -1
```

#### 3. **Extract information**
```bash
cd ~/gh/p_gopikchr/gopikchr && gh issue view <issue-number>
```
Extract:
- Commit SHA (full)
- Short SHA (first 10 chars)
- Issue number
- Brief description (for commit message)

#### 4. **Follow the porting process**
- Steps 1-8 from "Step-by-Step Porting Process" section
  - Pay special attention to Step 5 (Analyze Intent)
- Test with `dotest.sh`
- Update `notes.md`
- Commit with proper format

#### 5. **Verify issue is closed**
```bash
gh issue view <issue-number>
```

#### 6. **Repeat for next issue**
Continue with the next oldest issue until:
- All issues are processed, or
- You encounter an issue that needs user collaboration

### Working on Multiple Issues

**Approach: One at a time, in order**

Process issues sequentially:
1. Port issue #83
2. Test and commit
3. Verify issue closed
4. Port issue #84
5. Test and commit
6. Continue...

**Do not batch commits**: Each upstream commit should result in one commit in this repository. This maintains the 1:1 correspondence with upstream.

### When to Stop and Ask

Stop automatic processing and ask the user when you encounter:
- An issue that requires semantic judgment (see "Troubleshooting" section)
- Test failures you can't resolve (`dotest.sh` shows differences)
- An upstream change that fundamentally conflicts with the Go implementation
- More than 3 consecutive issues (check in with user on progress)
- A pikchr.c-only change (no pikchr.y changes)

### Communication with User

After processing each issue, provide a brief update:

**Example:**
```
✓ Issue #83 completed: Ported contributors agreement addition
  - Changes were documentation-only in preamble
  - Tests pass: C and Go output identical
  - Committed: track upstream commit a1b2c3d4ef

✓ Issue #84 completed: Fixed arc bounding box calculation
  - Updated bbox computation in pik_draw_arc
  - Tests pass: C and Go output identical
  - Committed: track upstream commit e5f6a7b8cd

⚠ Issue #85 requires discussion: Add TCL v9 compatibility
  - Changes only affect pikchr.c (build system)
  - Uncertain if Go port needs equivalent changes
  - Pausing for guidance
```

This keeps the user informed and shows progress.

### Success Criteria

You've successfully completed the porting workflow when:
1. ✅ All `upstream-changes` issues are closed
2. ✅ All commits follow the correct format
3. ✅ Tests pass (`dotest.sh` shows "DONE: no failures")
4. ✅ Each upstream commit has a corresponding commit in this repo
5. ✅ `notes.md` is updated with all changes

### Long-term Maintenance

**This process repeats indefinitely:**
- GitHub Action creates new issues as upstream changes occur
- Future Claude sessions (or maintainers) process issues using this guide
- The Go port stays in sync with upstream pikchr

**Keeping this guide updated:**
If you discover new porting patterns or edge cases, consider updating:
- This CLAUDE.md file (for process improvements)
- The detailed porting guides (for new conversion patterns)
- The troubleshooting section (for new common issues)

---

## Quick Command Reference

```bash
# Find issues to work on
gh issue list --label upstream-changes --state open

# View issue details
gh issue view <number>

# Port workflow
cd ~/gh/p_gopikchr/pikchr
git checkout <commit-sha>
cd ~/gh/p_gopikchr/gopikchr
cp ~/gh/p_gopikchr/pikchr/pikchr.y c/
git diff c/pikchr.y

# After porting changes to internal/pikchr.y...
cd internal
./dotest.sh  # or manually: ../../golemon/bin/golemon pikchr.y && go fmt pikchr.go
cd ..

# Test
./dotest.sh

# Update notes.md (manually add entry)

# Commit
git add c/pikchr.y internal/pikchr.y internal/pikchr.go notes.md
git commit -m "$(cat <<'EOF'
track upstream commit <short-sha>: <brief description>

https://github.com/drhsqlite/pikchr/commit/<full-sha>

Closes #<issue-number>
EOF
)"
git push

# Verify
gh issue view <number>  # Should show CLOSED
```

---

## Additional Resources

- **[PIKCHR_PORTING_GUIDE.md](PIKCHR_PORTING_GUIDE.md)** - Comprehensive conversion patterns with 100+ examples
- **[PIKCHR_PORTING_SUMMARY.md](PIKCHR_PORTING_SUMMARY.md)** - Executive summary of porting philosophy
- **[README_PORTING_DOCS.md](README_PORTING_DOCS.md)** - Navigation guide for all documentation
- **[README.md](README.md)** - Project overview and goals
- **Upstream Pikchr**: https://github.com/drhsqlite/pikchr
- **Pikchr Website**: https://pikchr.org

---

**Last Updated**: 2025-10-27
**Version**: 1.2
