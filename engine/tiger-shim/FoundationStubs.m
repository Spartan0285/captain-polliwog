/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// What Leopard added to Foundation, AppKit and CoreFoundation, for a 10.4
// engine that names it.
//
// Most of it is constants - accessibility attribute names, grammar-checking
// keys, notification names - which only have to exist and be unique; a name
// Tiger never posts is simply never matched, which is what an engine running
// on Tiger should see.
//
// The two classes Leopard added, NSMapTable and NSTrackingArea, are in
// MapTableStubs.m and TrackingAreaStubs.m beside this file: each imports
// only the Foundation and AppKit headers that do not declare the class it
// defines, which is the one way to define a class the SDK already knows.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#pragma mark Accessibility, grammar, speech and window constants

NSString * const NSAccessibilityColumnCountAttribute = @"AXColumnCount";
NSString * const NSAccessibilityRowCountAttribute = @"AXRowCount";
NSString * const NSAccessibilityValueDescriptionAttribute = @"AXValueDescription";
NSString * const NSAccessibilityDisclosureTriangleRole = @"AXDisclosureTriangle";
NSString * const NSAccessibilityTimelineSubrole = @"AXTimeline";

NSString * const NSGrammarRange = @"NSGrammarRange";
NSString * const NSGrammarUserDescription = @"NSGrammarUserDescription";
NSString * const NSGrammarCorrections = @"NSGrammarCorrections";

NSString * const NSSpeechPitchBaseProperty = @"PitchBase";
NSString * const NSSpeechResetProperty = @"Reset";
NSString * const NSVoiceLocaleIdentifier = @"VoiceLocaleIdentifier";

NSString * const NSImageNameMultipleDocuments = @"NSMultipleDocuments";

// Tiger posts neither of these; a view that watches for them simply never
// hears one, which is how a window that is always on screen behaves.
NSString * const NSWindowWillOrderOnScreenNotification = @"NSWindowWillOrderOnScreenNotification";
NSString * const NSWindowWillOrderOffScreenNotification = @"NSWindowWillOrderOffScreenNotification";

// The run loop mode set: on Tiger, the modes a browser cares about, named
// one by one rather than through the 10.5 constant.
NSString * const NSRunLoopCommonModes = @"kCFRunLoopCommonModes";
