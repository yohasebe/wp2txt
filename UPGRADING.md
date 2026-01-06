# Upgrading to wp2txt 2.0.0

This document describes the breaking changes in wp2txt 2.0.0 and how to migrate your code.

## Breaking Changes

### 1. Horizontal Rule Detection (REMOVE_HR_REGEX)

**What changed**: The horizontal rule regex now requires 4 or more hyphens instead of 3.

**Why**: This aligns with the MediaWiki specification where `----` (4 hyphens) is the minimum for a horizontal rule. Lines with `---` (3 hyphens) are not horizontal rules in MediaWiki.

**Before (1.x)**:
```
---   → removed (incorrectly treated as HR)
----  → removed
```

**After (2.0)**:
```
---   → preserved (not a horizontal rule)
----  → removed
```

**Migration**: If your code relied on `---` being removed, you'll need to handle this separately. In most cases, this change improves accuracy.

## Behavior Changes (Non-Breaking)

### 1. Unicode Character Reference Handling

**What changed**: `chrref_to_utf` now correctly handles all Unicode codepoints including emoji and CJK Extension characters.

**Before (1.x)**:
```ruby
chrref_to_utf("&#x1F600;")  # → Invalid character or error
chrref_to_utf("&#128512;")  # → Invalid character or error
```

**After (2.0)**:
```ruby
chrref_to_utf("&#x1F600;")  # → "😀"
chrref_to_utf("&#128512;")  # → "😀"
```

**Migration**: No changes needed. This is a bug fix that improves output quality.

### 2. Encoding Error Handling

**What changed**: `convert_characters` no longer calls `exit` on encoding errors.

**Before (1.x)**:
```ruby
convert_characters(invalid_utf8)  # → Could exit the program!
```

**After (2.0)**:
```ruby
convert_characters(invalid_utf8)  # → Returns scrubbed string
```

**Migration**: No changes needed. Your program will no longer unexpectedly exit on encoding errors.

### 3. Ruby 4.0 Compatibility

**What changed**: `command_exist?` now uses `IO.popen` instead of `open("| ...")`.

**Before (1.x)**:
```ruby
# Used Kernel#open with pipe - doesn't work in Ruby 4.0
open("| which bzip2")
```

**After (2.0)**:
```ruby
# Uses IO.popen - works in all Ruby versions
IO.popen(["which", "bzip2"], err: File::NULL, &:read)
```

**Migration**: No changes needed. The gem now works with Ruby 4.0.

## New Features

### Multilingual Support

wp2txt 2.0 adds support for category and redirect detection in 30+ languages. This is fully backward compatible.

**Supported category namespaces**:
- English: `Category`
- German: `Kategorie`
- French: `Catégorie`
- Japanese: `カテゴリ`
- Chinese: `分类`, `分類`
- Russian: `Категория`
- And 25+ more languages

**Supported redirect keywords**:
- English: `REDIRECT`
- German: `WEITERLEITUNG`
- French: `REDIRECTION`
- Japanese: `転送`
- Chinese: `重定向`
- Russian: `ПЕРЕНАПРАВЛЕНИЕ`
- And 20+ more languages

## Version Requirements

- **Minimum Ruby version**: 3.0.0 (Ruby 2.x is no longer supported)
- **Tested Ruby versions**: 3.0, 3.1, 3.2, 3.3, 4.0 (head)

## Questions?

If you encounter any issues during the upgrade, please open an issue at:
https://github.com/yohasebe/wp2txt/issues
