# Quick Fix Guide - Keyboard and Field Issues

## Issue #1: Nafath Login Sheet - Small Screen Field Cutoff

**File:** `lib/widgets/nafath_login_sheet.dart` (Line ~340)

### Current Code (PROBLEMATIC)
```dart
@override
Widget build(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),  // ❌ Fixed padding
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ... ID field and other content
          ],
        ),
      ),
    ),
  );
}
```

### Fixed Code (RECOMMENDED)
```dart
@override
Widget build(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final keyboardHeight = AppKeyboardInset.bottomOf(context);
  
  return SafeArea(
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        16, 
        4, 
        16, 
        math.max(20, keyboardHeight + 12),  // ✅ Dynamic padding
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ... ID field and other content
        ],
      ),
    ),
  );
}
```

### Import Needed
```dart
import 'dart:math' as math;
```

### Why This Works
- On 360px screen with 220px keyboard: padding = max(20, 220+12) = 232px
- Sheet content scrolls above keyboard without getting cut off
- On large screens: min 20px padding still applied

---

## Issue #2: National Address Results List - Keyboard Overflow

**File:** `lib/screens/national_address_picker_screen.dart` (Line ~468)

### Current Code (PROBLEMATIC)
```dart
if (_searchResults.isNotEmpty) ...[
  const SizedBox(height: 6),
  Material(
    elevation: 3,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),  // ❌ Fixed height
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _searchResults.length,
        // ... rest of list
      ),
    ),
  ),
],
```

### Fixed Code (RECOMMENDED)
```dart
if (_searchResults.isNotEmpty) ...[
  const SizedBox(height: 6),
  Material(
    elevation: 3,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Calculate available height above keyboard
        final keyboardHeight = AppKeyboardInset.bottomOf(context);
        final screenHeight = MediaQuery.sizeOf(context).height;
        final searchFieldHeight = 56.0; // Approximate height of search field
        
        // Available space = screen height - keyboard - search field
        final availableHeight = screenHeight - keyboardHeight - searchFieldHeight;
        
        // Use at most 60% of available space, but no more than 220px
        final maxListHeight = math.min(
          220.0, 
          availableHeight * 0.6,
        );
        
        // Ensure minimum height for at least 3 items
        final effectiveHeight = math.max(150.0, maxListHeight);
        
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: effectiveHeight),  // ✅ Dynamic
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _searchResults.length,
            // ... rest of list
          ),
        );
      },
    ),
  ),
],
```

### Import Needed
```dart
import 'dart:math' as math;
```

### Why This Works
- On 360px with 220px keyboard: available = 360 - 220 - 56 = 84px → max list = 50px
  - Wait, that's too small! Shows issue is more critical
  - With 84px available, even 150px min is wrong
  - Better calculation:
  
```dart
// Alternative: Show results above search if keyboard open
if (keyboardHeight > 48) {
  // Keyboard open: show list in reduced area
  return ConstrainedBox(
    constraints: BoxConstraints(maxHeight: math.max(100.0, availableHeight * 0.5)),
  );
} else {
  // Keyboard closed: show full results list
  return ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 220),
  );
}
```

---

## Issue #3: National Address Accept Button Hidden by Keyboard

**File:** `lib/screens/national_address_picker_screen.dart` (Line ~644)

### Current Code (PROBLEMATIC)
```dart
if (!keyboardOpen)  // ❌ Button completely hidden when keyboard is open
  Align(
    alignment: Alignment.bottomCenter,
    child: Material(
      color: cs.surface,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(20),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ... address details
              FilledButton.icon(
                onPressed: _mapReady ? _confirmSelection : null,
                icon: const Icon(Icons.check),
                label: Text(_isAr ? 'اعتماد العنوان' : 'Use this address'),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
```

### Fixed Code (OPTION A - Keep Button Always Visible)
```dart
// Show button above keyboard when keyboard is open
PositionedDirectional(
  end: 16,
  bottom: AppKeyboardInset.bottomOf(context) + 16,  // ✅ Position above keyboard
  start: 16,
  child: keyboardOpen
    ? Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _mapReady ? _confirmSelection : null,
            icon: const Icon(Icons.check),
            label: Text(_isAr ? 'اعتماد العنوان' : 'Use this address'),
          ),
        ),
      )
    : const SizedBox.shrink(),
),
// Keep original bottom sheet without button when keyboard is open
if (!keyboardOpen)
  Align(
    alignment: Alignment.bottomCenter,
    child: Material(
      // ... bottom sheet with full details and button
    ),
  ),
```

### Fixed Code (OPTION B - Auto-Confirm on Selection)
```dart
void _selectAddress(NationalAddressModel address) {
  final latitude = address.latitude;
  final longitude = address.longitude;
  if (latitude == null || longitude == null) {
    setState(() {
      _selected = address;
      _searchResults = const [];
      _error = _isAr ? '未検出坐标' : 'No coordinates detected';
    });
    return;
  }
  
  // Auto-confirm selection after search
  // This closes the sheet immediately, user sees new address in picker
  _confirmSelection();
}
```

### Why This Works
- Option A: Button stays visible above keyboard by using dynamic positioning
- Option B: Eliminates need for button confirmation by auto-confirming
- Both improve UX on small screens

---

## Issue #4: Hard-Coded Font Sizes Breaking on Text Scaling

**File:** Multiple files (Examples below)

### Example 1: Nafath Random Code Display
**File:** `lib/widgets/nafath_login_sheet.dart` (Line ~385)

#### Current Code (PROBLEMATIC)
```dart
Text(
  _random,
  style: const TextStyle(
    fontSize: 36,           // ❌ Hard-coded, ignores accessibility
    fontWeight: FontWeight.w900,
    letterSpacing: 6,
    color: _bank,
  ),
)
```

#### Fixed Code (RECOMMENDED)
```dart
Text(
  _random,
  style: TextStyle(
    fontSize: (Theme.of(context).textTheme.displaySmall?.fontSize ?? 32) 
      * (MediaQuery.textScaleFactorOf(context)),  // ✅ Respects scaling
    fontWeight: FontWeight.w900,
    letterSpacing: 6,
    color: _bank,
  ),
)
```

Or simpler:
```dart
Text(
  _random,
  style: Theme.of(context).textTheme.displaySmall?.copyWith(
    fontWeight: FontWeight.w900,
    letterSpacing: 6,
    color: _bank,
  ) ?? const TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w900,
    letterSpacing: 6,
    color: _bank,
  ),
)
```

### Example 2: Error Messages
**File:** `lib/screens/national_address_picker_screen.dart` (Line ~8885)

#### Current Code (PROBLEMATIC)
```dart
if ((deedDuplicateWarning ?? '').trim().isNotEmpty) ...[
  const SizedBox(height: 8),
  Text(
    deedDuplicateWarning!.trim(),
    style: TextStyle(
      fontSize: 12.5,       // ❌ Hard-coded error text
      height: 1.45,
      fontWeight: FontWeight.w800,
      color: cs.error,
    ),
  ),
],
```

#### Fixed Code (RECOMMENDED)
```dart
if ((deedDuplicateWarning ?? '').trim().isNotEmpty) ...[
  const SizedBox(height: 8),
  Text(
    deedDuplicateWarning!.trim(),
    style: Theme.of(context).textTheme.bodySmall?.copyWith(  // ✅ Theme-based
      height: 1.45,
      fontWeight: FontWeight.w800,
      color: cs.error,
    ) ?? TextStyle(
      fontSize: 12.5,
      height: 1.45,
      fontWeight: FontWeight.w800,
      color: cs.error,
    ),
  ),
],
```

### Example 3: Form Titles
**File:** `lib/screens/add_property_page.dart` (Line ~5710)

#### Current Code (PROBLEMATIC)
```dart
Text(
  _isAr
    ? 'الخطوة $displayStep من $stepCount · ${_wizardScreenTitle(_isAr)}'
    : 'Step $displayStep of $stepCount · ${_wizardScreenTitle(_isAr)}',
  style: Theme.of(context)
      .textTheme
      .titleSmall
      ?.copyWith(
        fontWeight: FontWeight.w800,
      ),
  textAlign: TextAlign.center,
),
```

**Status:** ✅ **ALREADY CORRECT**
- Uses `Theme.of(context).textTheme.titleSmall`
- This respects text scaling automatically

---

## Issue #5: Deed Number Verification - Missing Progress Indicator

**File:** `lib/screens/add_property_page.dart` (Line ~8870)

### Current Code (PROBLEMATIC)
```dart
AqarTextFormField(
  controller: deedNumber,
  keyboardType: TextInputType.number,
  decoration: deco(_isAr ? 'رقم الصك' : 'Deed number'),  // No suffix icon
  // ...
)
```

### Fixed Code (RECOMMENDED)
```dart
AqarTextFormField(
  controller: deedNumber,
  keyboardType: TextInputType.number,
  decoration: deco(_isAr ? 'رقم الصك' : 'Deed number').copyWith(
    suffixIcon: _buildDeedVerificationIcon(),  // ✅ Add icon
  ),
  // ...
)

Widget _buildDeedVerificationIcon() {
  // Returns appropriate icon based on verification state
  final deed = normalizeDeedNumber(_deedNumber.text);
  
  if (deed.isEmpty) {
    return const SizedBox.shrink();
  }
  
  // While checking (480ms debounce timer active)
  if (_deedDupDebounce?.isActive == true) {
    return const Padding(
      padding: EdgeInsets.all(12),
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
  
  // If error message exists, show error icon
  if ((_deedDuplicateWarning ?? '').isNotEmpty) {
    return Icon(Icons.error_outline, color: Colors.red[700]);
  }
  
  // If deed is complete and no warning, show success
  if (deed.length >= 10 && _deedDuplicateWarning == null) {
    return Icon(Icons.check_circle, color: Colors.green[700]);
  }
  
  return const SizedBox.shrink();
}
```

### Track Verification State
```dart
// Add to _AddPropertyPageState class:
bool get _deedVerifying => _deedDupDebounce?.isActive == true;
bool get _deedVerified => 
  (_deedDuplicateWarning ?? '').isEmpty && 
  normalizeDeedNumber(_deedNumber.text).length >= 10;
```

---

## Issue #6: National ID Field - Auto-Verification State

**File:** `lib/widgets/nafath_login_sheet.dart` (Line ~340)

### Current Code (PROBLEMATIC)
```dart
AqarTextField(
  controller: _idCtrl,
  keyboardType: TextInputType.number,
  inputFormatters: [
    const ArabicDigitsToLatinFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(10),  // Stops at 10 but no feedback
  ],
  decoration: InputDecoration(
    labelText: _isAr ? 'رقم الهوية / الإقامة' : 'National / Iqama ID',
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  ),
)
```

### Fixed Code (RECOMMENDED)
```dart
AqarTextField(
  controller: _idCtrl,
  keyboardType: TextInputType.number,
  inputFormatters: [
    const ArabicDigitsToLatinFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(10),
  ],
  decoration: InputDecoration(
    labelText: _isAr ? 'رقم الهوية / الإقامة' : 'National / Iqama ID',
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    suffixIcon: _nationalId.length == 10  // ✅ Show checkmark when complete
      ? Icon(Icons.check_circle, color: Colors.green[700])
      : null,
  ),
  onChanged: (_) {
    setState(() {});  // Rebuild to update suffix icon
  },
)
```

Or if auto-verifying on complete:
```dart
// In initState:
_idCtrl.addListener(() {
  if (_nationalId.length == 10 && !_busy && !_polling) {
    // Auto-trigger verification
    unawaited(_start());
  }
});
```

---

## Issue #7: RTL Padding Adjustment for Font Scaling

**File:** `lib/screens/add_property_page.dart` (Line ~5705)

### Current Code (PROBLEMATIC)
```dart
SingleChildScrollView(
  controller: _scrollCtrl,
  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
  padding: EdgeInsets.fromLTRB(
    12,  // Start (becomes right in RTL)
    keyboardOpen ? AppKeyboardInset.visibleHeightOf(context) * 0.4 : 12,
    12,  // End (becomes left in RTL)
    12,
  ),
```

### Fixed Code (RECOMMENDED)
```dart
SingleChildScrollView(
  controller: _scrollCtrl,
  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
  padding: EdgeInsets.fromLTRB(
    _isAr ? 14 : 12,  // ✅ Wider padding for RTL
    keyboardOpen ? AppKeyboardInset.visibleHeightOf(context) * 0.4 : 12,
    _isAr ? 12 : 14,  // ✅ Adjust opposite side for RTL
    12,
  ),
```

Or use semantic padding:
```dart
Padding(
  padding: EdgeInsetsDirectional.fromSTEB(
    12,  // Start (right edge in RTL, left in LTR)
    keyboardOpen ? AppKeyboardInset.visibleHeightOf(context) * 0.4 : 12,
    14,  // End (left edge in RTL, right in LTR)
    12,
  ),
```

---

## Testing These Fixes

### Devices to Test On:
```
1. iPhone SE (375×667) - Smallest iOS
2. Samsung Galaxy A51 (412×915) - Typical small Android
3. Device at 1.5x font scale setting
4. Landscape orientation at 400px height
5. Web browser at 480px width
```

### Test Cases:
```
[ ] Nafath sheet on 360px: ID field visible with keyboard
[ ] National Address on 400px: Results list scrollable with keyboard
[ ] National Address on 360px: Accept button accessible
[ ] Deed field: Shows spinner while checking, checkmark after
[ ] ID field: Shows checkmark when 10 digits entered
[ ] Font scale 1.5x: No layout overflow
[ ] Arabic at 1.5x: Text doesn't feel cramped
[ ] All screens: Keyboard dismisses properly
```

### Quick Testing Command:
```bash
# Test on small device
flutter run -d <device_id> --dart-define=FLUTTER_TEST_KEYBOARD=true
```

---

## Compilation Check After Fixes

```bash
# Check all files compile
dart analyze lib/

# Format code
dart format lib/

# Run tests
flutter test
```

---

## Files Modified Summary

| File | Issue | Fix | Priority |
|------|-------|-----|----------|
| `nafath_login_sheet.dart` | Small screen field cutoff | Dynamic keyboard padding | CRITICAL |
| `national_address_picker_screen.dart` | Results list overflow | Adaptive max height + button fix | CRITICAL |
| `national_address_picker_screen.dart` | Hard-coded font 12.5px | Use theme-based size | HIGH |
| `add_property_page.dart` | Hard-coded font 14.5px | Use theme-based size | HIGH |
| `add_property_page.dart` | Deed verification no feedback | Add progress/success icon | HIGH |
| `nafath_login_sheet.dart` | Hard-coded font 36px | Use theme + scale factor | HIGH |
| `nafath_login_sheet.dart` | National ID no completion state | Add checkmark at 10 digits | MEDIUM |
| `add_property_page.dart` | RTL padding not optimized | Adjust for text scaling | MEDIUM |

---

## Estimated Fix Time

- Issue #1 (Nafath padding): 15 minutes
- Issue #2 (Address list): 20 minutes  
- Issue #3 (Accept button): 10 minutes
- Issue #4 (Font sizes): 45 minutes (multiple files)
- Issue #5 (Deed verification): 30 minutes
- Issue #6 (ID completion): 15 minutes
- Issue #7 (RTL padding): 10 minutes
- Testing all fixes: 60 minutes

**Total: ~3 hours of focused work**

---

**Last Updated:** 2026-11-15
**Report:** KEYBOARD_FIELD_AUDIT_REPORT.md & AUDIT_EXECUTIVE_SUMMARY.txt
