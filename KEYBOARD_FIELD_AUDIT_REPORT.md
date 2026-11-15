# Comprehensive Keyboard, Field Cutoff, and Flow Issues Audit

**Date:** 2026-11-15  
**Focus Areas:** Keyboard handling, field visibility, navigation flow, auto-verification, and font scaling

---

## 1. KEYBOARD HANDLING ISSUES ✅

### 1.1 Architecture Overview
The app implements a comprehensive keyboard handling system through several layers:

#### Core Components:
- **`AppKeyboardStableScope`** - Locks layout dimensions to prevent keyboard from resizing screen
- **`AppKeyboardPad`** - Adds bottom padding matching keyboard height for scrollable content
- **`AppKeyboardSheetPad`** - Constrains sheets to visible area above keyboard
- **`AppOutsideUnfocus`** - Unfocuses fields when tapping outside or over-scrolling
- **`AppSoftKeyboardEnsureVisible`** - Automatically scrolls focused fields into view above keyboard
- **`AppKeyboardInset`** - Centralized source for keyboard metrics

#### Key Metrics Calculated:
```
visibleHeightOf() = screen height - keyboard height
keyboardTopOf() = where keyboard starts
layoutPadBottomOf() = padding to match visible area
scrollContentBottomOf() = additional padding for scroll margin
```

**Status:** ✅ **WORKING**
- Centralized keyboard calculations prevent duplication
- Multiple redundancy layers (rawInset, fromView, inferred, web)
- Handles both reported and inferred keyboard heights

---

### 1.2 Screen-by-Screen Keyboard Analysis

#### **Add Property Page** (`add_property_page.dart`)
```dart
Scaffold(
  resizeToAvoidBottomInset: false,  // ✅ CORRECT - Prevents resize
  body: AppKeyboardPad(               // ✅ CORRECT - Adds padding
    extra: 8,
    child: AppOutsideUnfocus(          // ✅ CORRECT - Unfocus on tap out
      child: Stack(...
        SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          padding: EdgeInsets.fromLTRB(
            12,
            keyboardOpen ? AppKeyboardInset.visibleHeightOf(context) * 0.4 : 12,
            12,
            12,
          ),
```

**Status:** ✅ **WORKING**
- `resizeToAvoidBottomInset: false` prevents layout compression
- `AppKeyboardPad` adds bottom padding dynamically
- `AppOutsideUnfocus` handles gesture dismissal
- Scroll padding adjusts when keyboard opens (40% of visible height)
- Uses `SingleChildScrollView.manual` to prevent auto-dismiss

**Potential Issues:** None identified

---

#### **Nafath Login Sheet** (`nafath_login_sheet.dart`)
```dart
SafeArea(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        ...
        AqarTextField(
          controller: _idCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: _isAr ? 'رقم الهوية / الإقامة' : 'National / Iqama ID',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
```

**Status:** ⚠️ **ISSUES DETECTED**

**Issues:**
1. **No `AppKeyboardPad` wrapper** - Sheet not explicitly padded for keyboard
   - `showAppModalBottomSheet()` does wrap in `AppKeyboardSheetPad` internally ✅
   - But manual `SafeArea` + `SingleChildScrollView` might not handle keyboard well on small screens

2. **No `AppOutsideUnfocus`** - Can't dismiss keyboard by tapping sheet background
   - Sheet is scrollable, not wrapped in gesture detector

3. **Fixed padding `20` at bottom** - Doesn't account for keyboard on small screens
   - On devices < 400px height, keyboard could overlap content

**Field Visibility:** ⚠️ **ID field could be hidden on very small screens**
- Screen height 380px, keyboard 250px = 130px visible
- Text field ~50px + label + error = 70px minimum
- Only ~60px margin left for scrolling

---

#### **National Address Picker Screen** (`national_address_picker_screen.dart`)
```dart
Scaffold(
  appBar: AppBar(...),
  body: Stack(
    children: [
      FlutterMap(...),
      PositionedDirectional(
        top: 12,
        start: 12,
        end: 12,
        child: Column(
          children: [
            Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(14),
              child: Row(
                children: [
                  Expanded(
                    child: AqarTextField(
                      controller: _searchController,
                      enabled: !_searching,
                      decoration: InputDecoration(
                        hintText: _isAr ? 'ابحث...' : 'Search...',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 6),
              Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
```

**Status:** ⚠️ **ISSUES DETECTED**

**Issues:**
1. **No `resizeToAvoidBottomInset` control** - Default is `true`
   - Scaffold will resize when keyboard appears
   - Search field might jump up unexpectedly

2. **Map-based layout** - Search field in `PositionedDirectional(top: 12, ...)`
   - When keyboard opens, the Stack doesn't adjust
   - Search field position is fixed, not responsive to keyboard
   - On small screens, keyboard could overlap search input

3. **ConstrainedBox with fixed `maxHeight: 220`** - Results list doesn't adapt
   - With keyboard open, visible space might be < 220px
   - Results could overflow and be unscrollable
   - No `AppKeyboardSheetPad` wrapping the results

4. **Search field not protected** - No scroll-to-reveal on focus
   - When field gets focus and keyboard opens, field doesn't scroll to center
   - On screens < 400px height with keyboard, field becomes unreachable

5. **No keyboard dismiss behavior** - User can't easily dismiss keyboard
   - No `GestureDetector` on map
   - No `AppOutsideUnfocus` wrapper

---

## 2. FIELD CUTOFF ISSUES ON SMALL SCREENS 🔴

### 2.1 Identified Problems

#### **Nafath Login Fields**
**File:** `lib/widgets/nafath_login_sheet.dart`

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
  ),
)
```

**Problem:** On devices with:
- Screen height: 360-400px (common older phones)
- Keyboard height: 220-260px
- System status bar: 24px
- SafeArea bottom: 0-20px

**Calculation:**
- Available height = 360 - 24 (status) - 220 (keyboard) = 116px
- Sheet content needs: ~60px (ID label + field) + ~60px (button) + margins = 140px
- **Result:** ❌ ID field and button don't fit - content is cut off

**Fix Needed:**
```dart
// Current:
SafeArea(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,

// Should be:
SafeArea(
  child: SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: EdgeInsets.fromLTRB(
      16, 
      4, 
      16, 
      AppKeyboardInset.bottomOf(context) + 12, // Dynamic padding
    ),
```

---

#### **National Address Picker Search Results**
**File:** `lib/screens/national_address_picker_screen.dart`

```dart
ConstrainedBox(
  constraints: const BoxConstraints(maxHeight: 220),  // ❌ FIXED HEIGHT
  child: ListView.separated(
```

**Problem:**
1. Fixed `maxHeight: 220` doesn't consider:
   - Keyboard height
   - Available screen space
   - Safe area insets

2. On small screens with keyboard:
   - Visible height = 360 - 260 (keyboard) = 100px
   - ConstrainedBox tries to use 220px
   - Results list overflows and clipped

**Calculation Example:**
- iPhone SE (375×667)
- Keyboard 260px
- Results list wants 220px
- But visible area = 100px
- **Result:** ❌ Only 2-3 items visible, half-cut off

**Fix Needed:**
```dart
// Current:
ConstrainedBox(
  constraints: const BoxConstraints(maxHeight: 220),

// Should be:
LayoutBuilder(
  builder: (context, constraints) {
    final keyboardHeight = AppKeyboardInset.bottomOf(context);
    final availableHeight = MediaQuery.sizeOf(context).height - 
                           AppKeyboardInset.visibleHeightOf(context);
    final maxListHeight = math.min(220.0, availableHeight * 0.6);
    
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxListHeight),
```

---

### 2.2 AqarTextField Padding Analysis
**File:** `lib/widgets/aqar_text_field.dart`

```dart
scrollPadding: AppKeyboardInset.inputScrollPadding(context),
```

**Status:** ✅ **WORKING**
- Uses dynamic scroll padding from keyboard inset
- Ensures field stays visible when keyboard opens

**Check:** Function `inputScrollPadding()` is properly implemented in `AppKeyboardInset`
```dart
static EdgeInsets inputScrollPadding(BuildContext context) {
  final base = aqarKeyboardScrollBottom(context);
  return EdgeInsets.only(left: 8, top: 10, right: 8, bottom: base);
}

static double aqarKeyboardScrollBottom(BuildContext context) {
  final kb = bottomOf(context);
  if (kb < 8) return 24;
  return math.max(120.0, kb + 56.0);
}
```

**Status:** ✅ **WORKING**
- Provides bottom padding = max(120px, keyboard_height + 56px)
- Ensures 56px margin above keyboard for scrolling comfort
- Left 8px, right 8px for side margins

---

### 2.3 Visual Density and Field Height
**File:** `lib/widgets/aqar_text_field.dart`

```dart
final field = TextField(
  ...
  textAlignVertical: multiline ? TextAlignVertical.top : TextAlignVertical.center,
  ...
);
```

**Status:** ✅ **WORKING**
- Single-line fields use center alignment
- Multiline fields use top alignment
- No hardcoded field heights

**But Missing:**
- No `visualDensity` override specified
- Uses Material default (compact-ish)
- On devices with large font scaling (1.5x), field might become taller
- No `minHeight` specified for text fields

**Potential Issue on Large Font Scaling:**
- User sets text scale to 1.5x (accessibility)
- Field height = ~60px (default 48px + 25% padding)
- With keyboard, visible area = 100px
- Space for 2 fields = 120px (overflow by 20px)
- Result: ❌ Fields don't fit

---

## 3. NAVIGATION AND FLOW ISSUES 🔴

### 3.1 Back Button Navigation

#### **National Address Picker Screen** ✅
```dart
Scaffold(
  appBar: AppBar(
    leading: const AppPageCloseButton(),  // ✅ Close button, not back
```

**Status:** ✅ **CORRECT**
- Uses close button intentionally (not back arrow)
- Returns to previous screen via `Navigator.pop()`
- Prevents confusion about navigation history

---

#### **Add Property Page** ✅
```dart
leading: (!_publishLock && !_saving)
    ? AppPageCloseButton(
        isArabic: _isAr,
        onPressed: () => unawaited(_onComposerClosePressed()),
      )
    : null,
```

**Status:** ✅ **CORRECT**
- Close button disabled during publish/save
- Custom handler `_onComposerClosePressed()` shows exit confirm dialog
- Checks for unsaved changes before allowing exit

---

#### **Nafath Login Sheet** ⚠️
```dart
// No explicit back button - default modal behavior
showAppModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetCtx) => NafathLoginSheet(...)
)
```

**Status:** ⚠️ **ISSUE: No back navigation on failure**
- When error occurs (invalid ID, timeout), user can't go back easily
- Has to dismiss sheet by dragging down
- Swipe-to-dismiss might not be obvious to users

**Fix Needed:**
- Add error recovery button
- Or add small back button in sheet header

---

### 3.2 Location Picker Accept/Reject Flow

#### **National Address Picker - Accept Flow** ⚠️

**Status:** ✅ **ACCEPT BUTTON EXISTS** - But has keyboard visibility issue

**Implementation:**
```dart
// Bottom sheet with explicit accept button
FilledButton.icon(
  onPressed: _mapReady ? _confirmSelection : null,
  icon: const Icon(Icons.check),
  label: Text(_isAr ? 'اعتماد العنوان' : 'Use this address'),
),

void _confirmSelection() {
  final address = _selected ?? const NationalAddressModel();
  Navigator.of(context).pop(
    address.copyWith(
      latitude: _center.latitude,
      longitude: _center.longitude,
    ),
  );
}
```

**Flow:**
1. User moves map or searches for address
2. Bottom sheet shows selected address details
3. Explicit "Use this address" button is visible
4. Button disabled until map is ready
5. On tap, returns to previous screen with selected address

**Issue:** ⚠️ **Button hidden when keyboard open**
```dart
if (!keyboardOpen)  // ❌ Button disappears when user types search
  Align(
    alignment: Alignment.bottomCenter,
    child: Material(...bottomSheet)
  ),
```

**Problem on small screens:**
- Visible area when keyboard open = ~100px
- Search field takes ~50px
- Results list takes remaining 50px
- Accept button is **completely hidden** below keyboard
- User cannot accept selection while search field is focused

**Scenario:**
1. User searches for address
2. Results appear
3. User taps result to select it
4. Keyboard dismisses
5. Bottom sheet with button becomes visible
6. User taps "Use this address"

**Status:** ✅ **ACCEPTABLE** - Button does appear after keyboard closes, but UX is slightly awkward

---

### 3.3 Draft Saving and Restoration

#### **Add Property Page Draft Management** ✅
```dart
void _wizardNext() {
  FocusManager.instance.primaryFocus?.unfocus();
  if (!_validateWizardStep(_wizardStep)) return;
  if (_wizardStep < _kWizardLastStep) {
    setState(() {
      _wizardStep++;
      _error = null;
    });
    unawaited(_persistListingDraft(showSnack: false));  // ✅ Save draft
    _scrollWizardStepToTop();
```

**Status:** ✅ **WORKING**
- Saves draft on each step navigation
- Restores draft on re-open from `initState`
- Uses SharedPreferences for persistence
- Handles migration from old draft format

**But Issue:** Draft might not save if app crashes between steps
- No transaction-based save
- No checksum validation

---

### 3.4 Form Reset on Exit

#### **Add Property Page Form Reset** ✅
```dart
@override
void dispose() {
  ActiveFormGuard.instance.unregister('add_property_listing');
  _appSession?.removeListener(_onConnectivityForDraft);
  _title.dispose();
  _desc.dispose();
  // ... all controllers disposed
```

**Status:** ✅ **WORKING**
- All controllers properly disposed
- Form state cleared on widget destroy
- No memory leaks

---

## 4. SMART FIELD AUTO-VERIFICATION ISSUES 🔴

### 4.1 National ID Field Auto-Verification

**File:** `lib/widgets/nafath_login_sheet.dart`

```dart
AqarTextField(
  controller: _idCtrl,
  keyboardType: TextInputType.number,
  inputFormatters: [
    const ArabicDigitsToLatinFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(10),  // ✅ Stops at 10 digits
  ],
  ...
)
```

**Problem:** ❌ **NO AUTO-VERIFICATION**
- Accepts 10 digits but doesn't auto-trigger verification
- User must manually tap "Continue" button
- No progress indicator showing: "Ready to verify" vs "Incomplete"

**Expected Behavior:**
1. User enters 10 digits
2. Field auto-verifies immediately
3. Shows green checkmark or "Ready" state
4. Button enables automatically

**Current Behavior:**
- User enters digits
- User manually taps button
- Then verification starts
- Button shows loading state

**Fix Needed:**
```dart
class _NafathLoginSheetState extends State<NafathLoginSheet> {
  String? _verifiedNationalId; // Track verified state
  bool _autoVerified = false;
  
  void _checkAutoVerify() {
    final id = _nationalId;
    if (id.length == 10 && id != _verifiedNationalId) {
      setState(() {
        _autoVerified = true;
        _verifiedNationalId = id;
        // Optionally auto-start verification
        // unawaited(_start());
      });
    }
  }
  
  @override
  void initState() {
    super.initState();
    _idCtrl.addListener(_checkAutoVerify);
  }
```

---

### 4.2 Deed Number Auto-Verification from Wathq ✅

**File:** `lib/screens/add_property_page.dart`

**Status:** ✅ **PARTIALLY WORKING - But No Progress Indicator**

**Implementation Found:**
```dart
// In initState:
_deedNumber.addListener(_scheduleDeedDuplicateCheck);

void _scheduleDeedDuplicateCheck() {
  _deedDupDebounce?.cancel();
  _deedDupDebounce = Timer(const Duration(milliseconds: 480), () {
    unawaited(_refreshDeedDuplicateWarning());
  });
}

Future<void> _refreshDeedDuplicateWarning() async {
  final msg = await _blockingDuplicateSaleDeedMessage();
  if (!mounted) return;
  if (msg == _deedDuplicateWarning) return;
  setState(() => _deedDuplicateWarning = msg);
}
```

**Display:**
```dart
if ((deedDuplicateWarning ?? '').trim().isNotEmpty) ...[
  const SizedBox(height: 8),
  Text(
    deedDuplicateWarning!.trim(),
    style: TextStyle(
      fontSize: 12.5,  // ❌ Hard-coded
      fontWeight: FontWeight.w800,
      color: cs.error,
    ),
  ),
],
```

**What's Working:**
- Deed number triggers 480ms debounced check after every keystroke
- Queries Wathq API via `DeedNumberIntegrity.verifyWithAuthority()`
- Checks for duplicate active sales with same deed
- Shows error message in red text if duplicate found

**Issues:**
1. ❌ **No Loading Indicator** - User doesn't see that check is in progress
   - Field looks normal while API call is happening (480-2000ms delay)
   - No spinner, checkmark, or "checking..." message

2. ❌ **No Success State** - When deed is verified as unique
   - No green checkmark or "verified" badge
   - Just absence of error message
   - User unsure if field was checked or just empty

3. ❌ **Hard-Coded Font Size** - `fontSize: 12.5` ignores text scale
   - At 1.5x font scale: 12.5px → 18.75px
   - Error message becomes more prominent and might overflow

**Better Behavior Would Be:**
```dart
TextField(
  controller: _deedNumber,
  suffixIcon: _deedVerifying 
    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
    : (_deedVerified ? Icon(Icons.check_circle, color: Colors.green) : null),
  decoration: InputDecoration(
    labelText: _isAr ? 'رقم الصك' : 'Deed number',
    hintText: _deedVerifying ? 'Checking...' : '',
  ),
),
```

---

## 5. FONT SCALING ISSUES 🔴

### 5.1 Hard-Coded Text Sizes

**File:** `lib/widgets/aqar_text_field.dart`

```dart
final effectiveStyle = AqarEditableDefaults.styleFor(context, style);

final field = TextField(
  ...
  style: effectiveStyle,
  ...
);
```

**Status:** ✅ **USING DEFAULTS**
- No hardcoded font sizes in AqarTextField
- Delegates to `AqarEditableDefaults.styleFor()` which respects theme

**But Need to Check:** `AqarEditableDefaults`

---

#### **Add Property Page - Hard-Coded Sizes Found**
**File:** `lib/screens/add_property_page.dart`

```dart
const TextStyle(
  fontWeight: FontWeight.w900,
  fontSize: 14.5,  // ❌ HARD-CODED
),

const TextStyle(
  fontSize: 12.5,  // ❌ HARD-CODED
  fontWeight: FontWeight.w700,
),

const TextStyle(
  fontSize: 36,     // ❌ HARD-CODED
  fontWeight: FontWeight.w900,
  letterSpacing: 6,
  color: _bank,
),
```

**Problem:** Hard-coded font sizes ignore:
- Device text scale settings
- User accessibility preferences
- User font size customization in Settings > Display

**On Device with 1.5x text scale:**
- 14.5px becomes 21.75px (reasonable)
- 36px becomes 54px (too large for phone)
- Form fields overflow their containers

**Example - Nafath Random Code Display:**
```dart
Text(
  _random,
  style: const TextStyle(
    fontSize: 36,           // ❌ HARD-CODED
    fontWeight: FontWeight.w900,
    letterSpacing: 6,
    color: _bank,
  ),
)
```

With 1.5x font scale:
- 36px → 54px height
- Code box height = ~18px + 54px + 18px = 90px
- On sheet with keyboard, only 100px visible
- Code box takes 90%, leaves 10px for other content
- Sheet content doesn't fit

**Fix Needed:**
```dart
Text(
  _random,
  style: TextStyle(
    fontSize: Theme.of(context).textTheme.displaySmall?.fontSize ?? 32,
    fontWeight: FontWeight.w900,
    letterSpacing: 6,
    color: _bank,
  ),
)
```

---

### 5.2 Label and Hint Scaling

**File:** `lib/widgets/aqar_text_field.dart` (InputDecoration handling)

```dart
// In aqarMergeInputDecoration - need to check this function
final mergedDecoration = decoration != null
    ? aqarMergeInputDecoration(context, decoration)
    : decoration;
```

**Status:** ⚠️ **NEEDS VERIFICATION**
- InputDecoration labels and hints might be hard-coded
- Need to check `aqarMergeInputDecoration()` implementation

---

### 5.3 RTL/LTR with Font Scaling

**File:** `lib/screens/add_property_page.dart`

```dart
return AppKeyboardCenterFieldScope(
    child: Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: PopScope(
```

**Status:** ✅ **WORKING**
- Directionality set correctly
- RTL padding uses `EdgeInsets.fromLTRB()` which adapts to direction
- Form fields should mirror correctly

**But With Font Scaling:**
- Arabic text typically needs wider margins (RTL)
- 1.5x scale pushes margin requirements higher
- Padding constants might be insufficient

**Example Issue:**
```dart
EdgeInsets.fromLTRB(12, 12, 12, 12)  // ❌ HARD-CODED margin
```

With Arabic at 1.5x scale:
- Text width increases 50%
- Fixed 12px margin becomes too narrow
- Text might overflow or feel cramped

**Fix Needed:**
```dart
EdgeInsets.fromLTRB(
  _isAr ? 16 : 12,  // RTL: wider left margin
  12,
  _isAr ? 12 : 16,  // RTL: narrower right margin
  12,
)
```

---

## 6. SUMMARY OF FINDINGS

### ✅ WORKING WELL
1. **Keyboard Height Calculations** - Centralized, redundant, reliable
2. **Add Property Page Keyboard** - Proper use of AppKeyboardPad, AppOutsideUnfocus, resizeToAvoidBottomInset
3. **Back Button Navigation** - Close buttons prevent history confusion
4. **Draft Persistence** - Saves on each step, restores on reopen
5. **Form Disposal** - No memory leaks, controllers properly cleaned

### ⚠️ NEEDS FIXES
1. **Nafath Login Sheet** - No dynamic padding for keyboard, fixed bottom margin
2. **National Address Search** - Fixed ConstrainedBox height (220px) not responsive
3. **Hard-Coded Font Sizes** - Doesn't respect user text scale settings
4. **Deed Verification Missing Visual Feedback** - No loading indicator or success checkmark
5. **National ID Field Missing Auto-Verification Trigger** - No progress state when 10 digits entered

### 🔴 CRITICAL ISSUES
1. **Nafath Fields on Small Screens** - Content cutoff on devices < 400px height with keyboard open
2. **Deed Number Auto-Verify** - No progress indicator, no auto-trigger after 10+ digits
3. **National ID Auto-Verify** - No visual confirmation when field complete
4. **Font Scaling Breaks Layout** - Hard-coded sizes overflow at 1.5x+ text scale
5. **National Address Results Overflow** - Fixed height constraint with flexible keyboard

---

## 7. RECOMMENDED FIXES (PRIORITY ORDER)

### CRITICAL (Week 1)
1. **Add dynamic padding to Nafath sheet**
   - Use `AppKeyboardInset.bottomOf()` for padding
   - Ensure content visible on all screen sizes with small screens (< 400px height)

2. **Make National Address results list keyboard-aware**
   - Use `AppKeyboardInset.visibleHeightOf()` for max height
   - Ensure at least 4-5 items visible even with keyboard open
   - Remove `if (!keyboardOpen)` constraint from accept button OR move it above keyboard

3. **Add visual feedback for deed number verification**
   - Show loading spinner in suffix icon while checking
   - Show green checkmark when deed verified as unique
   - Replace hard-coded `fontSize: 12.5` with theme-based size

### HIGH (Week 1-2)
4. **Replace hard-coded font sizes everywhere**
   - Audit all `const TextStyle(fontSize: X.X)` patterns
   - Use `Theme.of(context).textTheme.*` or `MediaQuery.textScaleFactor`
   - Priority: Nafath random code (36px), error messages (12.5px), form titles

5. **Add auto-verification trigger for National ID**
   - National ID: Show checkmark when 10 digits entered
   - No API call needed, just visual confirmation that field is complete
   - Optional: Auto-trigger Nafath check when ID is complete

### MEDIUM (Week 2)
6. **Improve error recovery in Nafath sheet**
   - Add "Back" button in error state
   - Allow clearing field and retrying

7. **Add confirmation button to National Address picker**
   - Show explicit "Confirm" button after selection
   - Or show success toast + auto-close

---

## 8. TESTING RECOMMENDATIONS

### Device Configurations to Test:
- [ ] iPhone SE (375×667) - smallest iOS screen
- [ ] Samsung Galaxy A51 (412×915) - small Android screen
- [ ] Android phone with 1.5x font scale
- [ ] iPad in Split View (50% width)
- [ ] Web at 480px width (mobile view)

### Test Scenarios:
- [ ] Type in ID field with keyboard open on 360px screen
- [ ] Search address with long result list and keyboard open
- [ ] Navigate back from National Address picker
- [ ] Verify deed number displays progress
- [ ] Set device font size to 1.5x and re-test layouts

---

## 9. CODE LOCATIONS FOR FIXES

### Files to Modify:
1. `lib/core/gestures/app_keyboard_inset.dart` - Add missing method
2. `lib/widgets/nafath_login_sheet.dart` - Add dynamic padding
3. `lib/screens/national_address_picker_screen.dart` - Make results adaptive
4. `lib/screens/add_property_page.dart` - Replace hard-coded font sizes
5. `lib/widgets/aqar_text_field.dart` - Update scroll padding reference
6. `lib/core/input/aqar_editable_defaults.dart` - Ensure theme-based sizing

---

**Report Generated:** Comprehensive audit of keyboard handling, field visibility, navigation, auto-verification, and font scaling issues.

