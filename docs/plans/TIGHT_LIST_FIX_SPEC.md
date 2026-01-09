# Engineering Spec: Tight List Rendering Fix

**Package:** swift-fast-markdown
**Version:** 1.1.2
**Author:** Engineering Agent
**Date:** 2026-01-09
**Status:** Implemented & Verified

---

## 1. Problem Statement

### Symptom
List item text content was not rendering in the iOS Health Sync App. Bullet points (•) appeared, but the text after them was empty.

**Visual Example:**
```
Expected:                    Actual:
Health Summary:              Health Summary:

Activity:                    Activity:
• Steps: 8,543               •
• Calories: 2,100            •

Heart:                       Heart:
• Rate: 72 bpm               •
```

### Root Cause Analysis

The issue stems from how **tight lists** are handled in the CommonMark specification and the md4c parser.

#### CommonMark Tight vs Loose Lists

**Tight list** (no blank lines between items):
```markdown
- Item 1
- Item 2
```

**Loose list** (blank lines between items):
```markdown
- Item 1

- Item 2
```

#### Parser Behavior Difference

| List Type | md4c emits `MD_BLOCK_P` for item content? | Our parser behavior |
|-----------|-------------------------------------------|---------------------|
| Loose     | Yes - wraps content in paragraph block    | Content captured correctly |
| Tight     | **No** - inline content directly in LI    | Content silently dropped |

#### Code Path Analysis

In `MD4CParser.swift`, the `textCallback` function checks:

```swift
guard !context.inlineStack.isEmpty else { return 0 }
```

For loose lists:
1. `MD_BLOCK_P` enters → `beginInlineBlock()` called → `inlineStack` not empty
2. Text callback fires → text captured in inline stack
3. `MD_BLOCK_P` leaves → paragraph with spans created

For tight lists:
1. `MD_BLOCK_LI` enters → no inline block started → `inlineStack` is empty
2. Text callback fires → **early return, text dropped**
3. `MD_BLOCK_LI` leaves → empty blocks array

This is why tight lists rendered with bullets but no content.

---

## 2. Solution Design

### Core Concept: Implicit Paragraph

For tight lists, we treat the list item itself as containing an "implicit paragraph" - we start collecting inline content when entering the LI and wrap it in a paragraph block when leaving.

### Implementation Changes

#### 2.1 BlockState Enum Extension

Added `hasImplicitParagraph` flag to track tight list items:

```swift
case listItem(isTask: Bool, isChecked: Bool, blocks: [MarkdownBlock], hasImplicitParagraph: Bool)
```

#### 2.2 Helper Method

Added method to detect if parent list is tight:

```swift
func isParentListTight() -> Bool {
    for state in blockStack.reversed() {
        if case .list(_, _, _, let isTight, _) = state {
            return isTight
        }
    }
    return false
}
```

#### 2.3 Enter Block Callback (MD_BLOCK_LI)

When entering a tight list item, start inline collection immediately:

```swift
case MD_BLOCK_LI:
    let info = detail?.assumingMemoryBound(to: MD_BLOCK_LI_DETAIL.self)
    let isTask = info?.pointee.is_task != 0
    let mark = info?.pointee.task_mark
    let isChecked = (mark == MD_CHAR(120) || mark == MD_CHAR(88))

    // Check if parent list is tight - if so, md4c won't emit paragraph blocks
    let parentListIsTight = context.isParentListTight()
    if parentListIsTight {
        context.beginInlineBlock()
    }
    context.blockStack.append(.listItem(
        isTask: isTask,
        isChecked: isChecked,
        blocks: [],
        hasImplicitParagraph: parentListIsTight
    ))
```

#### 2.4 Leave Block Callback (MD_BLOCK_LI)

When leaving, wrap collected inline content in a paragraph:

```swift
case MD_BLOCK_LI:
    guard case .listItem(let isTask, let isChecked, var blocks, let hasImplicitParagraph) =
        context.blockStack.popLast() else { return 0 }

    // For tight lists, wrap collected inline content in a paragraph
    if hasImplicitParagraph {
        let spans = context.endInlineBlock()
        if !spans.isEmpty {
            let paragraphRange = context.computeRange(from: spans)
            let paragraphId = context.nextID(kind: .paragraph, range: paragraphRange)
            let implicitParagraph = ParagraphBlock(
                id: paragraphId,
                spans: spans,
                range: paragraphRange
            )
            blocks.append(.paragraph(implicitParagraph))
        }
    }
    // ... rest unchanged
```

---

## 3. Verification

### Test Results

All 109 tests pass:

```
Test Suite 'All tests' passed at 2026-01-09 00:11:30.626.
Executed 109 tests, with 0 failures (0 unexpected) in 1.309 (1.315) seconds
```

### Diagnostic Output

**Before fix (tight list):**
```
[0] List (tight: true, items: 2)
  Item[0]: blocks=0  ← EMPTY!
  Item[1]: blocks=0  ← EMPTY!
```

**After fix (tight list):**
```
[0] List (tight: true, items: 2)
  Item[0]: blocks=1
    Paragraph: 'Item 1'
  Item[1]: blocks=1
    Paragraph: 'Item 2'
```

### Rendered Output

```
Health Summary:

Activity:

•   Steps: 8,543
•   Calories: 2,100

Heart:

•   Rate: 72 bpm
```

---

## 4. New Tests Added

### ListRenderingTests.swift

| Test | Purpose |
|------|---------|
| `testTightListItemsHaveContent` | Verifies tight list items have non-empty blocks |
| `testLooseListItemsHaveContent` | Verifies loose list items work correctly |
| `testHealthSummaryListContent` | End-to-end test with real health data format |
| `testRenderedListContainsText` | Verifies AttributedString output contains list text |

### TightListDebugTest.swift

| Test | Purpose |
|------|---------|
| `testTightVsLooseListParsing` | Diagnostic test comparing tight vs loose list behavior |

---

## 5. Files Modified

| File | Changes |
|------|---------|
| `Sources/SwiftFastMarkdown/Parser/MD4CParser.swift` | Core fix: implicit paragraph handling |
| `Tests/SwiftFastMarkdownTests/ListRenderingTests.swift` | New comprehensive list tests |
| `Tests/SwiftFastMarkdownTests/TightListDebugTest.swift` | Diagnostic test |

---

## 6. Risk Assessment

### Low Risk
- Change is additive - only affects tight lists that were previously broken
- Loose lists continue to work exactly as before
- Paragraph wrapping matches expected document structure

### Edge Cases Considered
- Empty list items → No paragraph created (empty spans check)
- Mixed tight/loose in nested lists → Each level tracks its own `isTight` flag
- Task lists in tight format → Works correctly (isTask/isChecked preserved)

---

## 7. Rollback Plan

If issues arise, revert the following changes in MD4CParser.swift:
1. Remove `hasImplicitParagraph` from `listItem` case
2. Remove `isParentListTight()` helper
3. Remove implicit paragraph logic from enter/leave callbacks

The package will revert to v1.1.1 behavior (tight lists broken, loose lists work).

---

## 8. Release Checklist

- [x] Root cause identified
- [x] Fix implemented in MD4CParser.swift
- [x] Unit tests added (ListRenderingTests, TightListDebugTest)
- [x] All 109 tests pass
- [x] Engineering spec created
- [ ] Tag v1.1.2 and push
- [ ] Update iOS app dependency
- [ ] Update CHANGELOG.md
- [ ] Verify on physical device

---

## 9. Lessons Learned

1. **CommonMark specification matters** - The tight vs loose list distinction is a fundamental part of CommonMark that affects parser output structure.

2. **Silent failures are dangerous** - The `guard !context.inlineStack.isEmpty else { return 0 }` silently dropped text instead of signaling an error. Consider adding debug logging for such cases.

3. **Diagnostic tests are invaluable** - Creating `TightListDebugTest` with detailed output immediately revealed `blocks=0` was the issue, pointing directly to the parser rather than the renderer.

4. **First-principles debugging** - Following the data flow from input markdown through parsing to rendering exposed the exact point of failure.
